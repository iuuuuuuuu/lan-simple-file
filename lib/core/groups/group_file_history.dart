// SPDX-License-Identifier: GPL-3.0-only

/// 群文件历史：从群消息里筛出 share / file 两类附件，按人/时间可分组，
/// 并在查询时**回填提供者在线状态**（计划 §6.5）。
///
/// 为什么查询时回填而不是写入时固化：
/// 在线状态时刻在变，如果写进 message 的 attach_json，历史卡片会永久显示
/// 一条过期的「在线」。因此历史查询每次都用注入的 [PeerOnlineProbe] 现算。
///
/// 离线必须给出**可读提示**而不是空白：计划 §6.5 要求
/// 「提供者 X 已离线（最后在线 N 分钟前）」+「上线后提醒我」。
library;

import 'dart:convert';

import '../contracts/contracts.dart';
import 'group_member_sync.dart';

/// 一条群文件历史记录。
final class GroupFileEntry {
  const GroupFileEntry({
    required this.messageId,
    required this.groupId,
    required this.threadId,
    required this.ownerPeerId,
    required this.shareId,
    required this.itemKey,
    required this.name,
    required this.size,
    required this.isDirectory,
    required this.sentAt,
    required this.senderPeerId,
    this.mime,
    this.revoked = false,
    this.ownerOnline = false,
    this.lastSeen,
    this.offlineHint,
  });

  final String messageId;
  final String groupId;
  final String threadId;

  /// 文件本体所在的分享所有者（不一定是消息发送者）。
  final PeerId ownerPeerId;

  final ShareId shareId;
  final ItemKey itemKey;
  final String name;
  final int size;
  final bool isDirectory;

  /// 消息发送时间（UTC）。
  final DateTime sentAt;

  /// 发出这条卡片的人。
  final PeerId senderPeerId;

  final String? mime;

  /// 卡片已被撤回/删除时为 true；UI 应显示「已撤回」而不是可点链接。
  final bool revoked;

  /// 提供者当前是否在线（查询时回填）。
  final bool ownerOnline;

  /// 提供者最后在线时间（可空）。
  final DateTime? lastSeen;

  /// 离线时给用户的可读提示；在线时为 null。
  ///
  /// 契约要求这里的文案不能是空字符串——空字符串等于没提示。
  final String? offlineHint;

  /// 是否可以立即取件。
  bool get canOpen => !revoked && ownerOnline;

  /// 按人分组用的键。
  PeerId get groupByPeer => ownerPeerId;
}

/// 文件历史的分组方式。
enum GroupFileGroupBy {
  /// 按提供者分组。
  peer,

  /// 按自然日分组（YYYY-MM-DD，UTC）。
  day,

  /// 不分组。
  none,
}

/// 提供者在线状态探测端口。
///
/// 抽成接口而不是直接读 store：发现在线/离线是 discovery 模块的职责，
/// 而本模块只关心「问一句」。测试里注入假实现即可覆盖离线分支。
abstract interface class PeerOnlineProbe {
  /// 该 peer 现在是否在线。
  Future<bool> isOnline(PeerId peer);

  /// 该 peer 最后在线时间；未知返回 null。
  Future<DateTime?> lastSeen(PeerId peer);
}

/// 群文件历史的查询与分组。
final class GroupFileHistory {
  /// [store] 提供消息与分享读能力，[probe] 提供在线状态。
  GroupFileHistory({required this.store, required this.probe});

  /// 消息与分享读能力（契约门面，不直接碰 drift）。
  final LanFileStore store;

  /// 提供者在线状态来源。
  final PeerOnlineProbe probe;

  /// 查询某群的文件历史。
  ///
  /// [peer] 只保留某个提供者的记录；[since] / [until] 按消息时间过滤（含边界）。
  /// 结果按时间**倒序**（最新在前），与聊天列表的视觉顺序一致。
  Future<List<GroupFileEntry>> list(
    String groupId, {
    PeerId? peer,
    DateTime? since,
    DateTime? until,
  }) async {
    final String threadId = groupThreadId(groupId);
    final List<MessageRecord> messages =
        await store.listMessages(threadId, limit: -1);

    final List<GroupFileEntry> entries = <GroupFileEntry>[];
    for (final MessageRecord message in messages) {
      if (message.kind != MessageKind.share && message.kind != MessageKind.file) {
        continue;
      }
      final Map<String, Object?>? attach = _decodeAttach(message.attachJson);
      if (attach == null) continue;
      final GroupFileEntry? entry = _entryOf(groupId, threadId, message, attach);
      if (entry == null) continue;
      if (peer != null && entry.ownerPeerId != peer) continue;
      if (since != null && entry.sentAt.isBefore(since.toUtc())) continue;
      if (until != null && entry.sentAt.isAfter(until.toUtc())) continue;
      entries.add(entry);
    }

    entries.sort((GroupFileEntry a, GroupFileEntry b) {
      final int byTime = b.sentAt.compareTo(a.sentAt);
      if (byTime != 0) return byTime;
      return b.messageId.compareTo(a.messageId);
    });

    return _withOnlineState(entries);
  }

  /// 按 [by] 分组；组内顺序与 [list] 一致，组之间按第一项的键升序。
  Future<Map<String, List<GroupFileEntry>>> grouped(
    String groupId, {
    GroupFileGroupBy by = GroupFileGroupBy.day,
    PeerId? peer,
    DateTime? since,
    DateTime? until,
  }) async {
    final List<GroupFileEntry> entries =
        await list(groupId, peer: peer, since: since, until: until);
    final Map<String, List<GroupFileEntry>> out =
        <String, List<GroupFileEntry>>{};
    for (final GroupFileEntry entry in entries) {
      out.putIfAbsent(_groupKeyOf(entry, by), () => <GroupFileEntry>[]).add(entry);
    }
    final List<String> keys = out.keys.toList()..sort();
    return <String, List<GroupFileEntry>>{
      for (final String key in keys) key: List<GroupFileEntry>.unmodifiable(out[key]!),
    };
  }

  /// 批量回填在线状态。
  ///
  /// 同一个提供者只问一次：一个群里几十个文件常来自同一个人，
  /// 逐个问会把发现层的查询放大到 O(条目数)。
  Future<List<GroupFileEntry>> _withOnlineState(
    List<GroupFileEntry> entries,
  ) async {
    if (entries.isEmpty) return const <GroupFileEntry>[];
    final Map<PeerId, ({bool online, DateTime? lastSeen})> cache =
        <PeerId, ({bool online, DateTime? lastSeen})>{};
    for (final GroupFileEntry entry in entries) {
      cache.putIfAbsent(
        entry.ownerPeerId,
        () => (online: false, lastSeen: null),
      );
    }
    for (final PeerId peer in cache.keys.toList()) {
      final bool online = await probe.isOnline(peer);
      final DateTime? lastSeen = online ? null : await probe.lastSeen(peer);
      cache[peer] = (online: online, lastSeen: lastSeen);
    }
    return <GroupFileEntry>[
      for (final GroupFileEntry entry in entries)
        GroupFileEntry(
          messageId: entry.messageId,
          groupId: entry.groupId,
          threadId: entry.threadId,
          ownerPeerId: entry.ownerPeerId,
          shareId: entry.shareId,
          itemKey: entry.itemKey,
          name: entry.name,
          size: entry.size,
          isDirectory: entry.isDirectory,
          sentAt: entry.sentAt,
          senderPeerId: entry.senderPeerId,
          mime: entry.mime,
          revoked: entry.revoked,
          ownerOnline: cache[entry.ownerPeerId]!.online,
          lastSeen: cache[entry.ownerPeerId]!.lastSeen,
          offlineHint: cache[entry.ownerPeerId]!.online
              ? null
              : _offlineHint(entry.ownerPeerId, cache[entry.ownerPeerId]!.lastSeen),
        ),
    ];
  }

  String _groupKeyOf(GroupFileEntry entry, GroupFileGroupBy by) {
    switch (by) {
      case GroupFileGroupBy.peer:
        return entry.ownerPeerId.value;
      case GroupFileGroupBy.day:
        final DateTime utc = entry.sentAt.toUtc();
        final String month = utc.month.toString().padLeft(2, '0');
        final String day = utc.day.toString().padLeft(2, '0');
        return '${utc.year}-$month-$day';
      case GroupFileGroupBy.none:
        return '';
    }
  }
}

/// 离线提示文案（计划 §6.5 的可读要求，不允许空字符串）。
String _offlineHint(PeerId peer, DateTime? lastSeen) {
  if (lastSeen == null) {
    return '提供者 ${peer.value} 已离线（最后在线时间未知）';
  }
  final Duration ago = DateTime.now().toUtc().difference(lastSeen.toUtc());
  if (ago.isNegative || ago.inMinutes < 1) {
    return '提供者 ${peer.value} 刚刚离线';
  }
  if (ago.inMinutes < 60) {
    return '提供者 ${peer.value} 已离线（最后在线 ${ago.inMinutes} 分钟前）';
  }
  if (ago.inHours < 24) {
    return '提供者 ${peer.value} 已离线（最后在线 ${ago.inHours} 小时前）';
  }
  return '提供者 ${peer.value} 已离线（最后在线 ${ago.inDays} 天前）';
}

/// 解析 attach_json；空串或非法 JSON 返回 null（该条视为无附件，跳过）。
Map<String, Object?>? _decodeAttach(String raw) {
  if (raw.isEmpty) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) return null;
  return decoded;
}

GroupFileEntry? _entryOf(
  String groupId,
  String threadId,
  MessageRecord message,
  Map<String, Object?> attach,
) {
  final Object? shareRaw = attach['shareId'];
  final Object? itemRaw = attach['itemKey'];
  final Object? ownerRaw = attach['ownerPeerId'];
  if (shareRaw is! String || itemRaw is! String || ownerRaw is! String) {
    return null;
  }
  final ShareId? shareId = ShareId.tryParse(shareRaw);
  final PeerId? owner = PeerId.tryParse(ownerRaw);
  if (shareId == null || owner == null) return null;
  final ItemKey itemKey;
  try {
    itemKey = ItemKey.parse(itemRaw);
  } on FormatException {
    return null;
  }
  return GroupFileEntry(
    messageId: message.id,
    groupId: groupId,
    threadId: threadId,
    ownerPeerId: owner,
    shareId: shareId,
    itemKey: itemKey,
    name: (attach['name'] as String?) ?? _baseName(itemKey.value),
    size: (attach['size'] as int?) ?? 0,
    isDirectory: (attach['isDir'] as bool?) ?? false,
    sentAt: message.ts.toUtc(),
    senderPeerId: message.senderPeerId,
    mime: attach['mime'] as String?,
    revoked: message.isRevoked,
  );
}

String _baseName(String itemKey) {
  final int slash = itemKey.lastIndexOf('/');
  return slash >= 0 && slash < itemKey.length - 1
      ? itemKey.substring(slash + 1)
      : itemKey;
}

/// 把 attach_json 编码成契约约定的形状，供 sendFile 使用。
String encodeGroupAttach({
  required ShareId shareId,
  required PeerId ownerPeerId,
  required ItemKey itemKey,
  required String name,
  required int size,
  bool isDir = false,
  String? mime,
}) =>
    jsonEncode(<String, Object?>{
      'shareId': shareId.value,
      'ownerPeerId': ownerPeerId.value,
      'itemKey': itemKey.value,
      'name': name,
      'size': size,
      'isDir': isDir,
      'mime': ?mime,
    });
