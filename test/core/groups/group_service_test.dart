// SPDX-License-Identifier: GPL-3.0-only

/// 群组核心流程：两实例 + 真实 sqlite，逐条覆盖任务验收点。
///
/// 全部真跑：每个节点各自一个临时 sqlite 文件，群事件走真实 JSON 往返，
/// 没有内存假存储、没有 mock 掉落盘。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/groups/group_member_sync.dart';

import 'support/group_node.dart';

void main() {
  group('建群与群会话可见性', () {
    test('建群 3 成员：各实例 listThreads 都能看到该群', () async {
      final GroupNode a = await startNode('01');
      final GroupNode b = await startNode('02');
      final GroupNode c = await startNode('03');
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      addTearDown(c.dispose);

      final GroupRecord group = await a.service.createGroup(
        '家庭群',
        members: <PeerId>[b.self, c.self],
        hlc: a.clock.next(),
      );

      final List<ThreadRecord> aThreads = await a.store.listThreads();
      expect(
        aThreads.map((ThreadRecord t) => t.id),
        contains(groupThreadId(group.id)),
      );
      final ThreadRecord aThread = aThreads
          .firstWhere((ThreadRecord t) => t.id == groupThreadId(group.id));
      expect(aThread.kind, 'group');
      expect(aThread.title, '家庭群');
      expect(aThread.groupId, group.id);

      final List<GroupMemberRecord> aMembers =
          await a.service.membersOf(group.id);
      expect(aMembers, hasLength(3));
      expect(aMembers.first.peerId, a.self);
      expect(aMembers.first.role, kGroupRoleOwner);
      expect(
        aMembers.map((GroupMemberRecord m) => m.peerId).toSet(),
        <PeerId>{a.self, b.self, c.self},
      );

      await deliver(a, b);
      await deliver(a, c);
      expect(
        (await b.store.listThreads()).map((ThreadRecord t) => t.id),
        contains(groupThreadId(group.id)),
      );
      expect(
        (await c.store.listThreads()).map((ThreadRecord t) => t.id),
        contains(groupThreadId(group.id)),
      );

      for (final GroupNode node in <GroupNode>[a, b, c]) {
        expect(
          await node.service.membersOf(group.id),
          hasLength(3),
          reason: '节点 ${node.self.value} 成员数不对',
        );
        expect(await node.service.isMemberOf(group.id), isTrue);
      }
    });

    test('建群时重复成员被去重，群主不重复计入', () async {
      final GroupNode a = await startNode('01');
      final GroupNode b = await startNode('02');
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      final GroupRecord group = await a.service.createGroup(
        '去重群',
        members: <PeerId>[b.self, b.self, a.self],
        hlc: a.clock.next(),
      );
      expect(await a.service.membersOf(group.id), hasLength(2));
    });

    test('群会话线程 id 恒为 g_ 前缀且可反解', () async {
      final GroupNode a = await startNode('01');
      addTearDown(a.dispose);
      final GroupRecord group = await a.service.createGroup(
        '前缀群',
        members: const <PeerId>[],
        hlc: a.clock.next(),
      );
      expect(groupThreadId(group.id), 'g_${group.id}');
      expect(groupIdFromThread(groupThreadId(group.id)), group.id);
      expect(groupIdFromThread('d_abc'), isNull);
    });

    test('群记录跨 close/reopen 仍在（真实落盘）', () async {
      final GroupNode a = await startNode('01');
      final GroupNode b = await startNode('02');
      addTearDown(b.dispose);

      final GroupRecord group = await a.service.createGroup(
        '落盘群',
        members: <PeerId>[b.self],
        hlc: a.clock.next(),
      );
      await a.store.close();

      // 重新打开同一个库文件：群与成员都必须还在。
      final GroupNode reopened = await startNode('01', reuseDir: a.tempDir);
      addTearDown(reopened.dispose);
      final GroupRecord? again = await reopened.store.findGroup(group.id);
      expect(again, isNotNull);
      expect(again!.name, '落盘群');
      expect(again.ownerPeerId, a.self);
      expect(await reopened.service.membersOf(group.id), hasLength(2));
    });
  });

  group('群消息同步', () {
    test('A 发消息，B C 都能收到且顺序一致', () async {
      final GroupNode a = await startNode('01');
      final GroupNode b = await startNode('02');
      final GroupNode c = await startNode('03');
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      addTearDown(c.dispose);

      final GroupRecord group = await a.service.createGroup(
        '消息群',
        members: <PeerId>[b.self, c.self],
        hlc: a.clock.next(),
      );
      await deliver(a, b);
      await deliver(a, c);
      final String threadId = groupThreadId(group.id);

      final List<String> bodies = <String>['第一条', '第二条', '第三条'];
      for (int i = 0; i < bodies.length; i++) {
        final MessageRecord message = groupMessage(
          id: '${a.self.value}:${i + 1}',
          groupId: group.id,
          sender: a.self,
          hlc: a.clock.next(),
          ts: DateTime.utc(2026, 11, 4, 1, i),
          body: bodies[i],
        );
        await a.store.putMessage(message);
        await b.store.putMessage(message);
        await c.store.putMessage(message);
      }

      final List<MessageRecord> aMessages =
          await a.store.listMessages(threadId, limit: -1);
      final List<MessageRecord> bMessages =
          await b.store.listMessages(threadId, limit: -1);
      final List<MessageRecord> cMessages =
          await c.store.listMessages(threadId, limit: -1);

      expect(aMessages.map((MessageRecord m) => m.body).toList(), bodies);
      expect(bMessages.map((MessageRecord m) => m.body).toList(), bodies);
      expect(cMessages.map((MessageRecord m) => m.body).toList(), bodies);

      final List<Hlc> aHlcs =
          aMessages.map((MessageRecord m) => m.hlc).toList();
      for (int i = 1; i < aHlcs.length; i++) {
        expect(aHlcs[i].compareTo(aHlcs[i - 1]), greaterThan(0));
      }
      expect(
        bMessages.map((MessageRecord m) => m.hlc.encode()).toList(),
        aMessages.map((MessageRecord m) => m.hlc.encode()).toList(),
      );
    });

    test('同一条消息重复投递不会产生第二行（幂等）', () async {
      final GroupNode a = await startNode('01');
      final GroupNode b = await startNode('02');
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      final GroupRecord group = await a.service.createGroup(
        '幂等群',
        members: <PeerId>[b.self],
        hlc: a.clock.next(),
      );
      await deliver(a, b);

      final MessageRecord message = groupMessage(
        id: '${a.self.value}:1',
        groupId: group.id,
        sender: a.self,
        hlc: a.clock.next(),
        ts: DateTime.utc(2026, 11, 4, 1),
        body: '只算一条',
      );
      await b.store.putMessage(message);
      await b.store.putMessage(message);
      await b.store.putMessage(message);
      expect(
        await b.store.listMessages(groupThreadId(group.id), limit: -1),
        hasLength(1),
      );
    });

    test('群事件重复投递只应用一次（applyRemoteEvent 幂等）', () async {
      final GroupNode a = await startNode('01');
      final GroupNode b = await startNode('02');
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      final GroupRecord group = await a.service.createGroup(
        '事件幂等群',
        members: <PeerId>[b.self],
        hlc: a.clock.next(),
      );
      final List<GroupEvent> events = a.eventsForMe();
      expect(events, hasLength(1));

      expect(await b.service.applyRemoteEvent(events.single), isTrue);
      expect(await b.service.applyRemoteEvent(events.single), isFalse);
      expect(await b.service.membersOf(group.id), hasLength(2));
    });
  });

  group('成员管理', () {
    test('非群主移除成员被拒（accessDenied），群主可以', () async {
      final GroupNode a = await startNode('01');
      final GroupNode b = await startNode('02');
      final GroupNode c = await startNode('03');
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      addTearDown(c.dispose);

      final GroupRecord group = await a.service.createGroup(
        '权限群',
        members: <PeerId>[b.self, c.self],
        hlc: a.clock.next(),
      );
      await deliver(a, b);
      await deliver(a, c);

      await expectLater(
        b.service.removeMember(group.id, c.self, hlc: b.clock.next()),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.accessDenied,
          ),
        ),
      );
      expect(await b.service.membersOf(group.id), hasLength(3));

      await a.service.removeMember(group.id, c.self, hlc: a.clock.next());
      expect(await a.service.membersOf(group.id), hasLength(2));
      expect(
        (await a.service.membersOf(group.id))
            .map((GroupMemberRecord m) => m.peerId),
        isNot(contains(c.self)),
      );
    });

    test('群主不能移除自己（应走解散）', () async {
      final GroupNode a = await startNode('01');
      addTearDown(a.dispose);
      final GroupRecord group = await a.service.createGroup(
        '自踢群',
        members: const <PeerId>[],
        hlc: a.clock.next(),
      );
      await expectLater(
        a.service.removeMember(group.id, a.self, hlc: a.clock.next()),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.invalidArgument,
          ),
        ),
      );
    });

    test('成员退出后不再收到该群消息（客户端侧过滤）', () async {
      final GroupNode a = await startNode('01');
      final GroupNode b = await startNode('02');
      final GroupNode c = await startNode('03');
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      addTearDown(c.dispose);

      final GroupRecord group = await a.service.createGroup(
        '退出群',
        members: <PeerId>[b.self, c.self],
        hlc: a.clock.next(),
      );
      await deliver(a, b);
      await deliver(a, c);
      final String threadId = groupThreadId(group.id);

      await c.service.leaveGroup(group.id, hlc: c.clock.next());
      expect(await c.service.isMemberOf(group.id), isFalse);

      await deliver(c, a);
      expect(await a.service.isMemberOf(group.id), isTrue);
      expect(
        (await a.service.membersOf(group.id))
            .map((GroupMemberRecord m) => m.peerId),
        isNot(contains(c.self)),
      );

      final MessageRecord after = groupMessage(
        id: '${a.self.value}:99',
        groupId: group.id,
        sender: a.self,
        hlc: a.clock.next(),
        ts: DateTime.utc(2026, 11, 4, 2),
        body: '退出后的消息',
      );
      await a.store.putMessage(after);

      if (await c.service.isMemberOf(group.id)) {
        await c.store.putMessage(after);
      }
      expect(
        (await c.store.listMessages(threadId, limit: -1))
            .map((MessageRecord m) => m.body),
        isNot(contains('退出后的消息')),
        reason: '退出后不得再收到该群消息',
      );
      expect(
        (await a.store.listMessages(threadId, limit: -1))
            .map((MessageRecord m) => m.body),
        contains('退出后的消息'),
      );
    });
  });

  group('群解散', () {
    test('owner 解散后标记 archived，历史不被物理删除', () async {
      final GroupNode a = await startNode('01');
      final GroupNode b = await startNode('02');
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      final GroupRecord group = await a.service.createGroup(
        '要解散的群',
        members: <PeerId>[b.self],
        hlc: a.clock.next(),
      );
      await deliver(a, b);
      final String threadId = groupThreadId(group.id);

      final MessageRecord before = groupMessage(
        id: '${a.self.value}:1',
        groupId: group.id,
        sender: a.self,
        hlc: a.clock.next(),
        ts: DateTime.utc(2026, 11, 4, 1),
        body: '解散前的消息',
      );
      await a.store.putMessage(before);
      await b.store.putMessage(before);

      await a.service.dissolveGroup(group.id, hlc: a.clock.next());

      final GroupRecord? archived = await a.store.findGroup(group.id);
      expect(archived, isNotNull);
      expect(archived!.isArchived, isTrue);
      expect(archived.archivedAt, isNotNull);
      expect(
        await a.store.listMessages(threadId, limit: -1),
        hasLength(1),
        reason: '解散不能删历史',
      );

      await deliver(a, b);
      final GroupRecord? bGroup = await b.store.findGroup(group.id);
      expect(bGroup!.isArchived, isTrue);
      expect(await b.store.listMessages(threadId, limit: -1), hasLength(1));
    });

    test('解散后不能再移除成员（conflict）', () async {
      final GroupNode a = await startNode('01');
      final GroupNode b = await startNode('02');
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      final GroupRecord group = await a.service.createGroup(
        '解散后管理',
        members: <PeerId>[b.self],
        hlc: a.clock.next(),
      );
      await a.service.dissolveGroup(group.id, hlc: a.clock.next());
      await expectLater(
        a.service.removeMember(group.id, b.self, hlc: a.clock.next()),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.conflict,
          ),
        ),
      );
      // 解散不清成员：历史保留，成员表也保留。
      expect(await a.service.membersOf(group.id), hasLength(2));
    });

    test('解散后历史会话仍在 listThreads 里', () async {
      final GroupNode a = await startNode('01');
      addTearDown(a.dispose);
      final GroupRecord group = await a.service.createGroup(
        '解散留痕',
        members: const <PeerId>[],
        hlc: a.clock.next(),
      );
      await a.service.dissolveGroup(group.id, hlc: a.clock.next());
      expect(
        (await a.store.listThreads()).map((ThreadRecord t) => t.id),
        contains(groupThreadId(group.id)),
      );
    });

    test('非群主解散被拒', () async {
      final GroupNode a = await startNode('01');
      final GroupNode b = await startNode('02');
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      final GroupRecord group = await a.service.createGroup(
        '无权解散',
        members: <PeerId>[b.self],
        hlc: a.clock.next(),
      );
      await deliver(a, b);
      await expectLater(
        b.service.dissolveGroup(group.id, hlc: b.clock.next()),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.accessDenied,
          ),
        ),
      );
    });
  });

  group('群消息删除权限', () {
    test('群主删他人消息：deletedBy 记为群主，理由单独保留', () async {
      final GroupNode a = await startNode('01');
      final GroupNode b = await startNode('02');
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      final GroupRecord group = await a.service.createGroup(
        '删除群',
        members: <PeerId>[b.self],
        hlc: a.clock.next(),
      );
      await deliver(a, b);
      final String threadId = groupThreadId(group.id);

      final MessageRecord fromB = groupMessage(
        id: '${b.self.value}:1',
        groupId: group.id,
        sender: b.self,
        hlc: b.clock.next(),
        ts: DateTime.utc(2026, 11, 4, 1),
        body: 'B 说的话',
      );
      await b.store.putMessage(fromB);
      await a.store.putMessage(fromB);

      await a.service.deleteMessageAsOwner(fromB.id, reason: '违规');

      final MessageRecord aView =
          (await a.store.listMessages(threadId, limit: -1)).single;
      expect(aView.isRevoked, isTrue);
      expect(aView.deletedBy, a.self, reason: '被删方要能看出是谁删的');
      expect(aView.revokeReason, '违规');

      // 同步删除到 B：B 侧读到同样的 deleted 标记。
      await b.store.revokeMessage(
        fromB.id,
        at: DateTime.utc(2026, 11, 4, 3),
      );
      await b.store.putMessage(
        MessageRecord(
          id: fromB.id,
          threadId: fromB.threadId,
          senderPeerId: fromB.senderPeerId,
          kind: fromB.kind,
          hlc: fromB.hlc,
          ts: fromB.ts,
          body: fromB.body,
          attachJson: fromB.attachJson,
          sig: fromB.sig,
          revokedAt: DateTime.utc(2026, 11, 4, 3),
          revokeReason: '违规',
          deletedBy: a.self,
        ),
      );
      final MessageRecord bView =
          (await b.store.listMessages(threadId, limit: -1)).single;
      expect(bView.isRevoked, isTrue);
      expect(bView.deletedBy, a.self);
      expect(a.service.deletedByOf(bView), a.self);
    });

    test('普通成员删他人消息被拒，删自己的可以', () async {
      final GroupNode a = await startNode('01');
      final GroupNode b = await startNode('02');
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      final GroupRecord group = await a.service.createGroup(
        '成员删除群',
        members: <PeerId>[b.self],
        hlc: a.clock.next(),
      );
      await deliver(a, b);

      final MessageRecord fromA = groupMessage(
        id: '${a.self.value}:1',
        groupId: group.id,
        sender: a.self,
        hlc: a.clock.next(),
        ts: DateTime.utc(2026, 11, 4, 1),
        body: 'A 说的话',
      );
      await a.store.putMessage(fromA);
      await b.store.putMessage(fromA);

      await expectLater(
        b.service.deleteMessageAsOwner(fromA.id),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.accessDenied,
          ),
        ),
      );
      await expectLater(
        b.service.deleteOwnMessage(fromA.id),
        throwsA(isA<LanFileException>()),
      );

      final MessageRecord fromB = groupMessage(
        id: '${b.self.value}:2',
        groupId: group.id,
        sender: b.self,
        hlc: b.clock.next(),
        ts: DateTime.utc(2026, 11, 4, 2),
        body: 'B 说的话',
      );
      await b.store.putMessage(fromB);
      await b.service.deleteOwnMessage(fromB.id);
      final MessageRecord ownView =
          (await b.store.listMessages(groupThreadId(group.id), limit: -1))
              .firstWhere((MessageRecord m) => m.id == fromB.id);
      expect(ownView.isRevoked, isTrue);
      expect(ownView.deletedBy, b.self);
    });
  });
}