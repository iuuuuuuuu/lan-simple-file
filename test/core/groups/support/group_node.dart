// SPDX-License-Identifier: GPL-3.0-only

/// 群组测试的共享夹具：真实临时 sqlite、真实 HLC、可注入的在线状态与广播收集器。
///
/// 全部真实依赖，没有 mock 存储：验收点就是「两实例各自落盘后能互相看到」，
/// 用内存假存储会把这条性质整个跳过。
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/groups/group_file_history.dart';
import 'package:lan_simple_file/core/groups/group_member_sync.dart';
import 'package:lan_simple_file/core/groups/group_service_impl.dart';
import 'package:lan_simple_file/core/messaging/hlc_clock.dart';
import 'package:lan_simple_file/core/store/store_impl.dart';

/// 合法 peerId：p_ + 恰好 13 位小写字母数字。
///
/// 契约正则是 ^p_[a-z0-9]{13}$；base 11 位 + 2 位后缀 = 13。
PeerId peerOf(String suffix) {
  const String base = '7fk3m9x2a1c'; // 11 位
  final String body = base + suffix.padLeft(2, '0').substring(0, 2);
  assert(body.length == 13, 'peerId body 必须是 13 位，实际 ${body.length}');
  return PeerId.parse('p_$body');
}

/// 一台测试节点的全部运行时部件。
final class GroupNode {
  GroupNode._({
    required this.store,
    required this.service,
    required this.clock,
    required this.self,
    required this.broadcaster,
    required this.probe,
    required this.dbFile,
    required this.tempDir,
  });

  final LanFileStoreImpl store;
  final GroupService service;
  final HlcClock clock;
  final PeerId self;
  final RecordingBroadcaster broadcaster;
  final FakeProbe probe;
  final File dbFile;
  final Directory tempDir;

  /// 关库并清临时目录。
  Future<void> dispose() async {
    await store.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }

  /// 从事件列表里筛出发给本机的事件（模拟点对点投递）。
  List<GroupEvent> eventsForMe() => broadcaster.events
      .where((GroupEvent e) =>
          e.effectiveSubject == self || e.actor == self)
      .toList(growable: false);
}

/// 关掉 drift 的「多次实例化 AppDatabase」告警。
///
/// 本测试的每个节点各自持有**不同库文件**，这正是 drift 警告里说的
/// 「same QueryExecutor 才会竞争」之外的合法场景；测试里一次开好几个库是设计意图。
/// 不关掉会让每次跑测都刷几十行 stacktrace，掩盖真正的失败。
void suppressMultipleDatabaseWarning() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
}

/// 起一个真实节点：真实临时 sqlite 文件 + 真实 HLC 时钟。
///
/// [reuseDir] 非空时复用已有目录（用于 close 后 reopen 同一库文件的落盘验证），
/// 此时不新建临时目录，dispose 仍会清理它。
Future<GroupNode> startNode(
  String peerSuffix, {
  WallClock? now,
  Directory? reuseDir,
}) async {
  suppressMultipleDatabaseWarning();
  final Directory dir = reuseDir ??
      await Directory.systemTemp.createTemp('lsf_group_${peerSuffix}_');
  final File dbFile = File('${dir.path}${Platform.pathSeparator}db.sqlite');
  final LanFileStoreImpl store = await LanFileStoreImpl.open(dbFile: dbFile);
  final PeerId self = peerOf(peerSuffix);
  final HlcClock clock = HlcClock(origin: self.value, now: now);
  final RecordingBroadcaster broadcaster = RecordingBroadcaster();
  final FakeProbe probe = FakeProbe();
  final GroupService service = GroupService(
    store: store,
    self: self,
    broadcaster: broadcaster,
  );
  return GroupNode._(
    store: store,
    service: service,
    clock: clock,
    self: self,
    broadcaster: broadcaster,
    probe: probe,
    dbFile: dbFile,
    tempDir: dir,
  );
}

/// 把 [from] 广播出的事件按投递规则应用到 [to]。
///
/// 真实场景里这些事件经 WS 送给群内每个成员；测试里显式转发，
/// 保留「事件形状不变、去重与授权在接收侧」的真实语义。
Future<List<GroupEvent>> deliver(
  GroupNode from,
  GroupNode to, {
  bool onlyToMe = true,
}) async {
  final List<GroupEvent> events =
      onlyToMe ? from.eventsForMe() : from.broadcaster.events;
  final List<GroupEvent> applied = <GroupEvent>[];
  for (final GroupEvent event in events) {
    if (await to.service.applyRemoteEvent(event)) applied.add(event);
  }
  return applied;
}

/// 记录所有广播出去的事件（并按线上形状往返一次，确保编解码不丢字段）。
final class RecordingBroadcaster implements GroupBroadcaster {
  final List<GroupEvent> events = <GroupEvent>[];

  @override
  Future<void> broadcast(GroupEvent event) async {
    // 走一遍真实序列化：线上要过的关，测试里也过。
    events.add(GroupEvent.fromJson(event.toJson()));
  }

  /// 清空（模拟新的一轮广播）。
  void clear() => events.clear();
}

/// 可编程的在线状态探测。
final class FakeProbe implements PeerOnlineProbe {
  final Map<PeerId, bool> _online = <PeerId, bool>{};
  final Map<PeerId, DateTime?> _lastSeen = <PeerId, DateTime?>{};

  /// 设定某人在线/离线。
  void set(PeerId peer, {required bool isOnline, DateTime? seenAt}) {
    _online[peer] = isOnline;
    _lastSeen[peer] = seenAt;
  }

  @override
  Future<bool> isOnline(PeerId peer) async => _online[peer] ?? false;

  @override
  Future<DateTime?> lastSeen(PeerId peer) async => _lastSeen[peer];
}

/// 构造一条群消息。
MessageRecord groupMessage({
  required String id,
  required String groupId,
  required PeerId sender,
  required Hlc hlc,
  required DateTime ts,
  String body = '',
  MessageKind kind = MessageKind.text,
  String attachJson = '',
}) =>
    MessageRecord(
      id: id,
      threadId: 'g_$groupId',
      senderPeerId: sender,
      kind: kind,
      hlc: hlc,
      ts: ts,
      body: body,
      attachJson: attachJson,
      sig: '',
    );
