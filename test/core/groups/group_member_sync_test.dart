// SPDX-License-Identifier: GPL-3.0-only

/// 群事件编解码与成员收敛：乱序、重复、越权三种真实分布式问题。
///
/// 纯函数 + 内存账本，不涉及数据库；数据库侧由 group_service_test 覆盖。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/groups/group_member_sync.dart';

PeerId peerOf(String suffix) {
  const String base = '7fk3m9x2a1c';
  return PeerId.parse('p_$base${suffix.padLeft(2, '0').substring(0, 2)}');
}

Hlc hlcAt(int millis) =>
    Hlc(millis: millis, counter: 0, origin: peerOf('01').value);

GroupEvent event({
  GroupEventKind kind = GroupEventKind.invite,
  String groupId = 'g1',
  PeerId? actor,
  PeerId? subject,
  String? name = '群名',
  String role = kGroupRoleMember,
  int millis = 1000,
}) =>
    GroupEvent(
      kind: kind,
      groupId: groupId,
      actor: actor ?? peerOf('01'),
      subject: subject,
      hlc: hlcAt(millis),
      ts: DateTime.utc(2026, 11, 4),
      name: name,
      role: role,
    );

void main() {
  group('GroupEvent 编解码', () {
    test('往返不丢字段', () {
      final GroupEvent original = event(
        kind: GroupEventKind.roleChange,
        subject: peerOf('02'),
        role: kGroupRoleOwner,
      );
      final GroupEvent back = GroupEvent.fromJson(original.toJson());
      expect(back.kind, original.kind);
      expect(back.groupId, original.groupId);
      expect(back.actor, original.actor);
      expect(back.subject, original.subject);
      expect(back.hlc, original.hlc);
      expect(back.ts, original.ts);
      expect(back.name, original.name);
      expect(back.role, original.role);
    });

    test('缺字段抛 invalidArgument，不静默补默认值', () {
      expect(
        () => GroupEvent.fromJson(<String, Object?>{'kind': 'invite'}),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.invalidArgument,
          ),
        ),
      );
    });

    test('非法 kind / 非法 actor 都被拒', () {
      expect(
        () => GroupEvent.fromJson(<String, Object?>{
          'kind': 'nope',
          'gid': 'g1',
          'actor': peerOf('01').value,
          'hlc': '1000:0:x',
          'ts': 1,
        }),
        throwsA(isA<LanFileException>()),
      );
      expect(
        () => GroupEvent.fromJson(<String, Object?>{
          'kind': 'invite',
          'gid': 'g1',
          'actor': 'not-a-peer',
          'hlc': '1000:0:x',
          'ts': 1,
        }),
        throwsA(isA<LanFileException>()),
      );
    });

    test('WS 帧往返', () {
      final GroupEvent original = event(subject: peerOf('02'));
      final WsFrame frame = original.toFrame();
      final WsFrame decoded = WsFrame.fromJson(frame.toJson());
      final GroupEvent? back = GroupEvent.tryFromFrame(decoded);
      expect(back, isNotNull);
      expect(back!.groupId, original.groupId);
      expect(GroupEvent.tryFromFrame(WsFrame(WsFrame.ack, const <String, Object?>{})),
          isNull);
    });
  });

  group('成员账本收敛', () {
    test('重复应用同一事件只生效一次', () {
      final GroupMemberLedger ledger = GroupMemberLedger(self: peerOf('02'));
      final GroupEvent invite = event(subject: peerOf('02'));
      expect(ledger.apply(invite), isTrue);
      expect(ledger.apply(invite), isFalse);
      expect(ledger.membersOf('g1'), hasLength(2));
    });

    test('乱序到达最终成员表一致', () {
      final GroupEvent invite = event(subject: peerOf('02'), millis: 1000);
      final GroupEvent accept = event(
        kind: GroupEventKind.accept,
        actor: peerOf('02'),
        subject: peerOf('02'),
        millis: 1200,
      );
      final GroupEvent later = event(
        kind: GroupEventKind.accept,
        actor: peerOf('03'),
        subject: peerOf('03'),
        millis: 1100,
      );

      final GroupMemberLedger inOrder =
          GroupMemberLedger(self: peerOf('02'));
      inOrder.apply(invite);
      inOrder.apply(later);
      inOrder.apply(accept);

      final GroupMemberLedger shuffled =
          GroupMemberLedger(self: peerOf('02'));
      shuffled.apply(later);
      shuffled.apply(accept);
      shuffled.apply(invite);

      expect(
        inOrder.membersOf('g1').map((GroupMemberRecord m) => m.peerId).toSet(),
        shuffled.membersOf('g1').map((GroupMemberRecord m) => m.peerId).toSet(),
      );
    });

    test('退出后不再是成员', () {
      final GroupMemberLedger ledger = GroupMemberLedger(self: peerOf('02'));
      ledger.apply(event(subject: peerOf('02')));
      expect(ledger.isMemberOf('g1'), isTrue);
      ledger.apply(event(
        kind: GroupEventKind.leave,
        actor: peerOf('02'),
        subject: peerOf('02'),
        millis: 2000,
      ));
      expect(ledger.isMemberOf('g1'), isFalse);
    });

    test('解散后 isArchived 为真，成员与历史不清空', () {
      final GroupMemberLedger ledger = GroupMemberLedger(self: peerOf('02'));
      ledger.apply(event(subject: peerOf('02')));
      ledger.apply(event(
        kind: GroupEventKind.dissolve,
        millis: 3000,
        name: null,
      ));
      expect(ledger.isArchived('g1'), isTrue);
      expect(ledger.membersOf('g1'), hasLength(2));
    });

    test('群主恒排在成员表首位', () {
      final GroupMemberLedger ledger = GroupMemberLedger(self: peerOf('02'));
      ledger.apply(event(subject: peerOf('02')));
      ledger.apply(event(
        kind: GroupEventKind.accept,
        actor: peerOf('03'),
        subject: peerOf('03'),
        millis: 900,
      ));
      final List<GroupMemberRecord> members = ledger.membersOf('g1');
      expect(isGroupOwner(members.first), isTrue);
      expect(members.first.peerId, peerOf('01'));
    });

    test('转让群主后 owner 记录随之改', () {
      final GroupMemberLedger ledger = GroupMemberLedger(self: peerOf('02'));
      ledger.apply(event(subject: peerOf('02')));
      ledger.apply(event(
        kind: GroupEventKind.roleChange,
        subject: peerOf('02'),
        role: kGroupRoleOwner,
        millis: 4000,
      ));
      final GroupMemberRecord? owner = findGroupOwner(ledger.membersOf('g1'));
      expect(owner?.peerId, peerOf('02'));
    });

    test('越权事件被 isAuthorized 判否', () {
      final GroupMemberLedger ledger = GroupMemberLedger(self: peerOf('02'));
      ledger.apply(event(subject: peerOf('02')));

      // A 是群主；B 尝试踢 C。
      final GroupEvent kickByMember = event(
        kind: GroupEventKind.removeMember,
        actor: peerOf('02'),
        subject: peerOf('03'),
        millis: 5000,
      );
      expect(ledger.isAuthorized(kickByMember), isFalse);

      final GroupEvent kickByOwner = event(
        kind: GroupEventKind.removeMember,
        actor: peerOf('01'),
        subject: peerOf('03'),
        millis: 5100,
      );
      expect(ledger.isAuthorized(kickByOwner), isTrue);
    });

    test('未知群只接受 invite', () {
      final GroupMemberLedger ledger = GroupMemberLedger(self: peerOf('02'));
      expect(
        ledger.isAuthorized(event(
          kind: GroupEventKind.dissolve,
          groupId: 'unknown',
          millis: 6000,
        )),
        isFalse,
      );
      expect(
        ledger.isAuthorized(event(
          groupId: 'unknown',
          subject: peerOf('02'),
          millis: 6100,
        )),
        isTrue,
      );
    });
  });

  group('角色归一化', () {
    test('owner 之外的任何值都按 member', () {
      expect(normalizeGroupRole('owner'), kGroupRoleOwner);
      expect(normalizeGroupRole('member'), kGroupRoleMember);
      expect(normalizeGroupRole('admin'), kGroupRoleMember);
      expect(normalizeGroupRole(''), kGroupRoleMember);
    });

    test('成员排序：群主 > 加入时间 > peerId', () {
      final List<GroupMemberRecord> raw = <GroupMemberRecord>[
        GroupMemberRecord(
          groupId: 'g1',
          peerId: peerOf('03'),
          role: kGroupRoleMember,
          joinedAt: DateTime.utc(2026, 1, 1),
        ),
        GroupMemberRecord(
          groupId: 'g1',
          peerId: peerOf('01'),
          role: kGroupRoleOwner,
          joinedAt: DateTime.utc(2026, 3, 1),
        ),
        GroupMemberRecord(
          groupId: 'g1',
          peerId: peerOf('02'),
          role: kGroupRoleMember,
          joinedAt: DateTime.utc(2026, 1, 1),
        ),
      ];
      final List<GroupMemberRecord> sorted = sortGroupMembers(raw);
      expect(sorted.first.role, kGroupRoleOwner);
      // 后两条同为 2026-01-01，按 peerId 兜底。
      expect(sorted[1].peerId.value.compareTo(sorted[2].peerId.value),
          lessThan(0));
    });
  });
}
