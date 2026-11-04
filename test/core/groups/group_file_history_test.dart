// SPDX-License-Identifier: GPL-3.0-only

/// 群文件历史：筛选、分组、以及**查询时回填提供者在线状态**。
///
/// 全部真跑：真实临时 sqlite 落消息，在线状态用可编程探针（不是 mock 存储）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/groups/group_file_history.dart';

import 'support/group_node.dart';

/// 造一条共享卡片消息。
MessageRecord shareCard({
  required String id,
  required String groupId,
  required PeerId sender,
  required PeerId owner,
  required Hlc hlc,
  required DateTime ts,
  required String shareId,
  required String itemKey,
  required String name,
  int size = 1024,
}) =>
    groupMessage(
      id: id,
      groupId: groupId,
      sender: sender,
      hlc: hlc,
      ts: ts,
      kind: MessageKind.share,
      attachJson: encodeGroupAttach(
        shareId: ShareId.parse(shareId),
        ownerPeerId: owner,
        itemKey: ItemKey.parse(itemKey),
        name: name,
        size: size,
      ),
    );

void main() {
  group('群文件历史筛选', () {
    test('只筛出 share/file 两类，text 不进历史', () async {
      final GroupNode a = await startNode('01');
      addTearDown(a.dispose);

      final GroupRecord group = await a.service.createGroup(
        '历史群',
        members: const <PeerId>[],
        hlc: a.clock.next(),
      );
      final String groupId = group.id;

      await a.store.putMessage(shareCard(
        id: 'm1',
        groupId: groupId,
        sender: a.self,
        owner: a.self,
        hlc: a.clock.next(),
        ts: DateTime.utc(2026, 11, 4, 1),
        shareId: 'sh01',
        itemKey: 'docs/a.pdf',
        name: 'a.pdf',
      ));
      await a.store.putMessage(groupMessage(
        id: 'm2',
        groupId: groupId,
        sender: a.self,
        hlc: a.clock.next(),
        ts: DateTime.utc(2026, 11, 4, 2),
        body: '纯文本不该进历史',
      ));
      await a.store.putMessage(shareCard(
        id: 'm3',
        groupId: groupId,
        sender: a.self,
        owner: a.self,
        hlc: a.clock.next(),
        ts: DateTime.utc(2026, 11, 4, 3),
        shareId: 'sh02',
        itemKey: 'pic/b.jpg',
        name: 'b.jpg',
      ));

      final FakeProbe probe = FakeProbe()..set(a.self, isOnline: true);
      final GroupFileHistory history =
          GroupFileHistory(store: a.store, probe: probe);
      final List<GroupFileEntry> entries = await history.list(groupId);

      expect(entries, hasLength(2));
      expect(entries.map((GroupFileEntry e) => e.name), <String>['b.jpg', 'a.pdf']);
      for (final GroupFileEntry entry in entries) {
        expect(entry.shareId, isNotNull);
        expect(entry.itemKey.value, isNotEmpty);
        expect(entry.ownerPeerId, a.self);
      }
    });

    test('按提供者过滤', () async {
      final GroupNode a = await startNode('01');
      final GroupNode b = await startNode('02');
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      final GroupRecord group = await a.service.createGroup(
        '按人筛',
        members: <PeerId>[b.self],
        hlc: a.clock.next(),
      );
      await a.store.putMessage(shareCard(
        id: 'm1',
        groupId: group.id,
        sender: a.self,
        owner: a.self,
        hlc: a.clock.next(),
        ts: DateTime.utc(2026, 11, 4, 1),
        shareId: 'sh01',
        itemKey: 'a.txt',
        name: 'a.txt',
      ));
      await a.store.putMessage(shareCard(
        id: 'm2',
        groupId: group.id,
        sender: b.self,
        owner: b.self,
        hlc: b.clock.next(),
        ts: DateTime.utc(2026, 11, 4, 2),
        shareId: 'sh02',
        itemKey: 'b.txt',
        name: 'b.txt',
      ));

      final FakeProbe probe = FakeProbe()
        ..set(a.self, isOnline: true)
        ..set(b.self, isOnline: true);
      final GroupFileHistory history =
          GroupFileHistory(store: a.store, probe: probe);

      final List<GroupFileEntry> onlyB =
          await history.list(group.id, peer: b.self);
      expect(onlyB, hasLength(1));
      expect(onlyB.single.ownerPeerId, b.self);
      expect(onlyB.single.name, 'b.txt');
    });

    test('按时间窗口过滤（含边界）', () async {
      final GroupNode a = await startNode('01');
      addTearDown(a.dispose);
      final GroupRecord group = await a.service.createGroup(
        '按时间筛',
        members: const <PeerId>[],
        hlc: a.clock.next(),
      );
      for (int d = 1; d <= 3; d++) {
        await a.store.putMessage(shareCard(
          id: 'm$d',
          groupId: group.id,
          sender: a.self,
          owner: a.self,
          hlc: a.clock.next(),
          ts: DateTime.utc(2026, 11, d, 0),
          shareId: 'sh0$d',
          itemKey: 'f$d.txt',
          name: 'f$d.txt',
        ));
      }
      final FakeProbe probe = FakeProbe()..set(a.self, isOnline: true);
      final GroupFileHistory history =
          GroupFileHistory(store: a.store, probe: probe);

      final List<GroupFileEntry> window = await history.list(
        group.id,
        since: DateTime.utc(2026, 11, 2),
        until: DateTime.utc(2026, 11, 3),
      );
      expect(window.map((GroupFileEntry e) => e.name),
          <String>['f3.txt', 'f2.txt']);
    });

    test('按提供者与按日分组', () async {
      final GroupNode a = await startNode('01');
      final GroupNode b = await startNode('02');
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      final GroupRecord group = await a.service.createGroup(
        '分组群',
        members: <PeerId>[b.self],
        hlc: a.clock.next(),
      );
      await a.store.putMessage(shareCard(
        id: 'm1', groupId: group.id, sender: a.self, owner: a.self,
        hlc: a.clock.next(), ts: DateTime.utc(2026, 11, 4, 10),
        shareId: 'sh01', itemKey: 'a.txt', name: 'a.txt',
      ));
      await a.store.putMessage(shareCard(
        id: 'm2', groupId: group.id, sender: b.self, owner: b.self,
        hlc: b.clock.next(), ts: DateTime.utc(2026, 11, 4, 11),
        shareId: 'sh02', itemKey: 'b.txt', name: 'b.txt',
      ));
      await a.store.putMessage(shareCard(
        id: 'm3', groupId: group.id, sender: a.self, owner: a.self,
        hlc: a.clock.next(), ts: DateTime.utc(2026, 11, 5, 9),
        shareId: 'sh03', itemKey: 'c.txt', name: 'c.txt',
      ));

      final FakeProbe probe = FakeProbe()
        ..set(a.self, isOnline: true)
        ..set(b.self, isOnline: true);
      final GroupFileHistory history =
          GroupFileHistory(store: a.store, probe: probe);

      final Map<String, List<GroupFileEntry>> byPeer =
          await history.grouped(group.id, by: GroupFileGroupBy.peer);
      expect(byPeer.keys.toSet(), <String>{a.self.value, b.self.value});
      expect(byPeer[a.self.value], hasLength(2));
      expect(byPeer[b.self.value], hasLength(1));

      final Map<String, List<GroupFileEntry>> byDay =
          await history.grouped(group.id, by: GroupFileGroupBy.day);
      expect(byDay.keys.toSet(), <String>{'2026-11-04', '2026-11-05'});
      expect(byDay['2026-11-04'], hasLength(2));
      expect(byDay['2026-11-05'], hasLength(1));
    });
  });

  group('提供者在线状态回填', () {
    test('提供者离线时返回可读提示（非空字符串）', () async {
      final GroupNode a = await startNode('01');
      final GroupNode b = await startNode('02');
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      final GroupRecord group = await a.service.createGroup(
        '离线群',
        members: <PeerId>[b.self],
        hlc: a.clock.next(),
      );
      await a.store.putMessage(shareCard(
        id: 'm1',
        groupId: group.id,
        sender: a.self,
        owner: a.self,
        hlc: a.clock.next(),
        ts: DateTime.utc(2026, 11, 4, 1),
        shareId: 'sh01',
        itemKey: 'a.txt',
        name: 'a.txt',
      ));

      // A 离线：最后在线 30 分钟前。
      final FakeProbe probe = FakeProbe()
        ..set(
          a.self,
          isOnline: false,
          seenAt: DateTime.now().toUtc().subtract(const Duration(minutes: 30)),
        );
      final GroupFileHistory history =
          GroupFileHistory(store: a.store, probe: probe);

      final List<GroupFileEntry> entries = await history.list(group.id);
      final GroupFileEntry entry = entries.single;
      expect(entry.ownerOnline, isFalse);
      expect(entry.canOpen, isFalse);
      expect(entry.offlineHint, isNotNull);
      expect(entry.offlineHint, isNotEmpty);
      expect(entry.offlineHint, contains('已离线'));
      expect(entry.offlineHint, contains('30 分钟前'));
    });

    test('提供者在线时 hint 为 null 且可打开', () async {
      final GroupNode a = await startNode('01');
      addTearDown(a.dispose);
      final GroupRecord group = await a.service.createGroup(
        '在线群',
        members: const <PeerId>[],
        hlc: a.clock.next(),
      );
      await a.store.putMessage(shareCard(
        id: 'm1', groupId: group.id, sender: a.self, owner: a.self,
        hlc: a.clock.next(), ts: DateTime.utc(2026, 11, 4, 1),
        shareId: 'sh01', itemKey: 'a.txt', name: 'a.txt',
      ));
      final FakeProbe probe = FakeProbe()..set(a.self, isOnline: true);
      final GroupFileHistory history =
          GroupFileHistory(store: a.store, probe: probe);

      final GroupFileEntry entry = (await history.list(group.id)).single;
      expect(entry.ownerOnline, isTrue);
      expect(entry.canOpen, isTrue);
      expect(entry.offlineHint, isNull);
    });

    test('在线状态是查询时现算，不是写入时固化', () async {
      final GroupNode a = await startNode('01');
      addTearDown(a.dispose);
      final GroupRecord group = await a.service.createGroup(
        '现算群',
        members: const <PeerId>[],
        hlc: a.clock.next(),
      );
      await a.store.putMessage(shareCard(
        id: 'm1', groupId: group.id, sender: a.self, owner: a.self,
        hlc: a.clock.next(), ts: DateTime.utc(2026, 11, 4, 1),
        shareId: 'sh01', itemKey: 'a.txt', name: 'a.txt',
      ));
      final FakeProbe probe = FakeProbe()..set(a.self, isOnline: true);
      final GroupFileHistory history =
          GroupFileHistory(store: a.store, probe: probe);

      expect((await history.list(group.id)).single.ownerOnline, isTrue);
      // 同一个库、同一条消息，只把探针改成离线，历史必须立刻反映。
      probe.set(a.self,
          isOnline: false,
          seenAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)));
      final GroupFileEntry later = (await history.list(group.id)).single;
      expect(later.ownerOnline, isFalse);
      expect(later.offlineHint, isNotNull);
    });

    test('同一提供者只探测一次（批量回填不放大查询）', () async {
      final GroupNode a = await startNode('01');
      addTearDown(a.dispose);
      final GroupRecord group = await a.service.createGroup(
        '批量群',
        members: const <PeerId>[],
        hlc: a.clock.next(),
      );
      for (int i = 1; i <= 5; i++) {
        await a.store.putMessage(shareCard(
          id: 'm$i', groupId: group.id, sender: a.self, owner: a.self,
          hlc: a.clock.next(), ts: DateTime.utc(2026, 11, 4, i),
          shareId: 'sh0$i', itemKey: 'f$i.txt', name: 'f$i.txt',
        ));
      }
      final CountingProbe probe = CountingProbe()
        ..set(a.self, isOnline: true);
      final GroupFileHistory history =
          GroupFileHistory(store: a.store, probe: probe);

      final List<GroupFileEntry> entries = await history.list(group.id);
      expect(entries, hasLength(5));
      expect(probe.calls, 1, reason: '5 条同一提供者只该问一次');
    });

    test('已撤回的卡片不可打开，但仍出现在历史里', () async {
      final GroupNode a = await startNode('01');
      addTearDown(a.dispose);
      final GroupRecord group = await a.service.createGroup(
        '撤回群',
        members: const <PeerId>[],
        hlc: a.clock.next(),
      );
      await a.store.putMessage(shareCard(
        id: 'm1', groupId: group.id, sender: a.self, owner: a.self,
        hlc: a.clock.next(), ts: DateTime.utc(2026, 11, 4, 1),
        shareId: 'sh01', itemKey: 'a.txt', name: 'a.txt',
      ));
      await a.store.revokeMessage(
        'm1',
        at: DateTime.utc(2026, 11, 4, 2),
        reason: '发错了',
      );
      final FakeProbe probe = FakeProbe()..set(a.self, isOnline: true);
      final GroupFileHistory history =
          GroupFileHistory(store: a.store, probe: probe);

      final GroupFileEntry entry = (await history.list(group.id)).single;
      expect(entry.revoked, isTrue);
      expect(entry.canOpen, isFalse);
    });

    test('attach_json 坏掉时不崩、跳过该条', () async {
      final GroupNode a = await startNode('01');
      addTearDown(a.dispose);
      final GroupRecord group = await a.service.createGroup(
        '坏数据群',
        members: const <PeerId>[],
        hlc: a.clock.next(),
      );
      await a.store.putMessage(groupMessage(
        id: 'bad',
        groupId: group.id,
        sender: a.self,
        hlc: a.clock.next(),
        ts: DateTime.utc(2026, 11, 4, 1),
        kind: MessageKind.share,
        attachJson: '{"not":"a card"}',
      ));
      await a.store.putMessage(groupMessage(
        id: 'broken',
        groupId: group.id,
        sender: a.self,
        hlc: a.clock.next(),
        ts: DateTime.utc(2026, 11, 4, 2),
        kind: MessageKind.file,
        attachJson: 'not-json-at-all',
      ));
      final FakeProbe probe = FakeProbe()..set(a.self, isOnline: true);
      final GroupFileHistory history =
          GroupFileHistory(store: a.store, probe: probe);
      expect(await history.list(group.id), isEmpty);
    });
  });

  group('线程隔离', () {
    test('不同群的历史互不串味', () async {
      final GroupNode a = await startNode('01');
      addTearDown(a.dispose);
      final GroupRecord g1 = await a.service.createGroup(
        '群一', members: const <PeerId>[], hlc: a.clock.next(),
      );
      final GroupRecord g2 = await a.service.createGroup(
        '群二', members: const <PeerId>[], hlc: a.clock.next(),
      );
      expect(g1.id, isNot(g2.id));

      await a.store.putMessage(shareCard(
        id: 'm1', groupId: g1.id, sender: a.self, owner: a.self,
        hlc: a.clock.next(), ts: DateTime.utc(2026, 11, 4, 1),
        shareId: 'sh01', itemKey: 'one.txt', name: 'one.txt',
      ));
      await a.store.putMessage(shareCard(
        id: 'm2', groupId: g2.id, sender: a.self, owner: a.self,
        hlc: a.clock.next(), ts: DateTime.utc(2026, 11, 4, 2),
        shareId: 'sh02', itemKey: 'two.txt', name: 'two.txt',
      ));

      final FakeProbe probe = FakeProbe()..set(a.self, isOnline: true);
      final GroupFileHistory history =
          GroupFileHistory(store: a.store, probe: probe);
      expect((await history.list(g1.id)).map((GroupFileEntry e) => e.name),
          <String>['one.txt']);
      expect((await history.list(g2.id)).map((GroupFileEntry e) => e.name),
          <String>['two.txt']);
    });
  });
}

/// 记录探测次数的探针，用于断言批量回填没有放大查询。
final class CountingProbe implements PeerOnlineProbe {
  final Map<PeerId, bool> _online = <PeerId, bool>{};

  /// 被问过多少次。
  int calls = 0;

  void set(PeerId peer, {required bool isOnline}) {
    _online[peer] = isOnline;
  }

  @override
  Future<bool> isOnline(PeerId peer) async {
    calls++;
    return _online[peer] ?? false;
  }

  @override
  Future<DateTime?> lastSeen(PeerId peer) async => null;
}
