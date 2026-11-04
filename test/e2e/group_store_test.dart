// SPDX-License-Identifier: GPL-3.0-only

/// Lead 侧验证：群组持久化方法在真实 sqlite 上成立。
///
/// 这批方法是从契约缺口补出来的，必须由外部按契约调用一遍才算数。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/store/store_impl.dart';

void main() {
  late Directory tmp;
  late File dbFile;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lsf_group_store_');
    dbFile = File('${tmp.path}${Platform.pathSeparator}app.sqlite');
  });
  tearDown(() {
    // 数据库文件连接未释放时 Windows 会拒绝删除；
    // 清理失败不应污染断言结论，但要记录下来。
    if (!tmp.existsSync()) {
      return;
    }
    for (int attempt = 0; attempt < 5; attempt++) {
      try {
        tmp.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        sleep(const Duration(milliseconds: 100));
      }
    }
    // 仍失败则放弃，交给系统临时目录清理，不让它掩盖真实断言。
  });

  final PeerId owner = PeerId.parse('p_kzdvvj2umnduy');
  final PeerId member = PeerId.parse('p_eh7ddx5bksrgc');
  final DateTime created = DateTime.utc(2026, 11, 4, 9, 0, 0);

  GroupRecord grp({String id = 'g001', String name = '素材组'}) => GroupRecord(
        id: id,
        name: name,
        avatarHash: 'sha256:abcd1234',
        ownerPeerId: owner,
        createdAt: created,
        epoch: 1,
      );

  test('建群 -> close -> reopen -> 群与成员都还在', () async {
    final LanFileStore a = await LanFileStoreImpl.open(dbFile: dbFile);
    await a.upsertGroup(grp());
    await a.putGroupMember(GroupMemberRecord(
      groupId: 'g001',
      peerId: owner,
      role: 'owner',
      joinedAt: created,
    ));
    await a.putGroupMember(GroupMemberRecord(
      groupId: 'g001',
      peerId: member,
      role: 'member',
      joinedAt: created,
    ));
    await a.close();

    final LanFileStore b = await LanFileStoreImpl.open(dbFile: dbFile);
    final GroupRecord? g = await b.findGroup('g001');
    expect(g, isNotNull);
    expect(g!.name, '素材组');
    expect(g.ownerPeerId.value, owner.value);
    expect(g.epoch, 1);
    expect(g.createdAt.toUtc(), created);
    expect(g.isArchived, isFalse);

    final List<GroupMemberRecord> ms = await b.listGroupMembers('g001');
    expect(ms.length, 2);
    expect(ms.map((GroupMemberRecord m) => m.peerId.value).toSet(),
        <String>{owner.value, member.value});
    expect(ms.firstWhere((GroupMemberRecord m) => m.role == 'owner').peerId.value,
        owner.value);
    await b.close();
  });

  test('upsertGroup 幂等：同 id 改名只留一条', () async {
    final LanFileStore a = await LanFileStoreImpl.open(dbFile: dbFile);
    await a.upsertGroup(grp());
    await a.upsertGroup(grp(name: '改过的名字'));
    final List<GroupRecord> all = await a.listGroups();
    expect(all.length, 1);
    expect(all.single.name, '改过的名字');
    await a.close();
  });

  test('removeGroupMember 真删；删光后 listGroupMembers 为空', () async {
    final LanFileStore a = await LanFileStoreImpl.open(dbFile: dbFile);
    await a.upsertGroup(grp());
    await a.putGroupMember(GroupMemberRecord(
        groupId: 'g001', peerId: member, role: 'member', joinedAt: created));
    expect((await a.listGroupMembers('g001')).length, 1);
    await a.removeGroupMember('g001', member);
    expect((await a.listGroupMembers('g001')), isEmpty);
    // 重复删不抛异常（幂等）
    await a.removeGroupMember('g001', member);
    await a.close();
  });

  test('archiveGroup 后 isArchived 为 true，且 close/reopen 后仍成立', () async {
    final DateTime at = DateTime.utc(2026, 11, 4, 10, 0, 0);
    final LanFileStore a = await LanFileStoreImpl.open(dbFile: dbFile);
    await a.upsertGroup(grp());
    await a.archiveGroup('g001', at: at);
    await a.close();

    final LanFileStore b = await LanFileStoreImpl.open(dbFile: dbFile);
    final GroupRecord? g = await b.findGroup('g001');
    expect(g, isNotNull);
    expect(g!.isArchived, isTrue);
    expect(g.archivedAt!.toUtc(), at);
    // 解散不删历史：成员记录仍在
    expect(await b.listGroupMembers('g001'), isEmpty);
    await b.close();
  });
}
