// SPDX-License-Identifier: GPL-3.0-only

/// UI 测试夹具：假数据源 + 主题包装。
///
/// 这里的「假」只假在**数据来源**，被测组件本身是真的（真 pump、真 build、
/// 真渲染）。不使用 mock 框架，也不替换 SharedPreferences/网络等系统能力——
/// 本任务的页面不依赖它们。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/theme/app_theme.dart';
import 'package:lan_simple_file/app/theme/tokens.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/ui/pages/groups_page.dart';
import 'package:lan_simple_file/ui/pages/nearby_page.dart';
import 'package:lan_simple_file/ui/pages/shares_page.dart';

/// 合法 peerId：p_ + 恰好 13 位小写字母数字。
PeerId peerOf(String suffix) {
  const String base = '7fk3m9x2a1c'; // 11 位
  return PeerId.parse('p_$base${suffix.padLeft(2, '0').substring(0, 2)}');
}

/// 构造一个 PeerView。
PeerView peerView({
  required String suffix,
  String? name,
  bool online = true,
  int shareCount = 0,
  String? os,
}) => PeerView(
  peerId: peerOf(suffix),
  name: name ?? '设备$suffix',
  avatarHash: '',
  online: online,
  shareCount: shareCount,
  lastSeen: DateTime.utc(2026, 11, 4, 8),
  os: os,
);

/// 构造一条分享记录。
ShareRecord shareRecord({
  required String id,
  String displayName = '共享目录',
  ShareMode mode = ShareMode.lan,
  bool enabled = true,
  bool missing = false,
  DateTime? revokedAt,
  DateTime? expiresAt,
  String kind = 'folder',
  String rootKind = 'localPath',
  String? rootUri,
}) => ShareRecord(
  id: ShareId.parse(id),
  kind: kind,
  rootKind: rootKind,
  rootUri: rootUri ?? 'D:/媒体/$displayName',
  displayName: displayName,
  ownerPeerId: peerOf('00'),
  createdAt: DateTime.utc(2026, 11, 1),
  mode: mode,
  enabled: enabled,
  missing: missing,
  isEphemeral: false,
  revokedAt: revokedAt,
  expiresAt: expiresAt,
);

/// 构造一条群会话线程。
ThreadRecord groupThread({
  required String groupId,
  String? title,
  int unread = 0,
  String? preview,
}) => ThreadRecord(
  id: 'g_$groupId',
  kind: 'group',
  title: title ?? '群$groupId',
  avatarHash: '',
  unread: unread,
  muted: false,
  pinned: false,
  createdAt: DateTime.utc(2026, 11, 2),
  groupId: groupId,
  lastMsgPreview: preview,
);

/// 构造一条单聊线程（用于验证群页面不会误收）。
ThreadRecord directThread({required String id, String title = '单聊'}) =>
    ThreadRecord(
      id: id,
      kind: 'direct',
      title: title,
      avatarHash: '',
      unread: 3,
      muted: false,
      pinned: false,
      createdAt: DateTime.utc(2026, 11, 2),
      peerId: peerOf('09'),
    );

/// 构造一条群记录。
GroupRecord groupRecord({
  required String groupId,
  String name = '群',
  PeerId? owner,
  bool archived = false,
}) => GroupRecord(
  id: groupId,
  name: name,
  avatarHash: '',
  ownerPeerId: owner ?? peerOf('00'),
  createdAt: DateTime.utc(2026, 11, 2),
  epoch: 1,
  archivedAt: archived ? DateTime.utc(2026, 11, 3) : null,
);

/// 可编程的附近的人数据源。
final class FakeNearbySource implements NearbySource {
  /// 返回给页面的 peer 列表。
  List<PeerView> peers = <PeerView>[];

  /// peerId → 其分享列表。
  Map<PeerId, List<SharedRootView>> sharesByPeer =
      <PeerId, List<SharedRootView>>{};

  /// refresh 被调用次数。
  int refreshes = 0;

  @override
  Future<List<PeerView>> listPeers() async => peers;

  @override
  Future<List<SharedRootView>> listSharesOf(PeerId peer) async =>
      sharesByPeer[peer] ?? const <SharedRootView>[];

  @override
  Future<void> refresh() async {
    refreshes++;
  }
}

/// 可编程的「我的分享」数据源。
final class FakeMySharesSource implements MySharesSource {
  /// 返回的分享列表。
  List<ShareRecord> shares = <ShareRecord>[];

  /// buildLink 的返回；为空时用默认链接。
  Uri? link;

  /// 已被停止的分享 id。
  final List<String> stopped = <String>[];

  /// 停止时抛出的错误（用于验证失败路径真的显示出来）。
  Object? stopError;

  @override
  Future<List<ShareRecord>> listMine() async => shares;

  @override
  Future<void> rename(ShareId id, String name) async {
    shares = <ShareRecord>[
      for (final ShareRecord share in shares)
        share.id == id ? share.copyWith(displayName: name) : share,
    ];
  }

  @override
  Future<Uri> buildLink(ShareId id) async =>
      link ?? Uri.parse('lanfile://s/${id.value}?k=token');

  /// buildWebLink 的返回；为 null 时表示「本机没有可用局域网地址」。
  Uri? webLink;

  @override
  Future<Uri?> buildWebLink(ShareId id) async => webLink;

  @override
  Future<void> stop(ShareId id) async {
    final Object? error = stopError;
    if (error != null) throw error;
    stopped.add(id.value);
    shares = <ShareRecord>[
      for (final ShareRecord s in shares)
        if (s.id == id)
          ShareRecord(
            id: s.id,
            kind: s.kind,
            rootKind: s.rootKind,
            rootUri: s.rootUri,
            displayName: s.displayName,
            ownerPeerId: s.ownerPeerId,
            createdAt: s.createdAt,
            mode: s.mode,
            enabled: false, // 停止共享 = enabled:false
            missing: s.missing,
            isEphemeral: s.isEphemeral,
          )
        else
          s,
    ];
  }

  /// 已被重新启用的分享 id。
  final List<String> resumed = <String>[];

  /// 已被删除的分享 id。
  final List<String> deleted = <String>[];

  /// resume 时抛出的错误（验证失败路径）。
  Object? resumeError;

  /// delete 时抛出的错误（验证失败路径）。
  Object? deleteError;

  /// browse 的返回；按 (分享 id, 路径) 查，找不到就给空页。
  Map<String, List<TreeEntryView>> entriesByPath =
      <String, List<TreeEntryView>>{};

  /// browse 被调用时收到的路径（按顺序记录，供断言下钻）。
  final List<String?> browsedPaths = <String?>[];

  @override
  Future<void> resume(ShareId id) async {
    final Object? error = resumeError;
    if (error != null) throw error;
    resumed.add(id.value);
    shares = <ShareRecord>[
      for (final ShareRecord s in shares)
        if (s.id == id)
          ShareRecord(
            id: s.id,
            kind: s.kind,
            rootKind: s.rootKind,
            rootUri: s.rootUri,
            displayName: s.displayName,
            ownerPeerId: s.ownerPeerId,
            createdAt: s.createdAt,
            mode: s.mode,
            enabled: true,
            missing: s.missing,
            isEphemeral: s.isEphemeral,
          )
        else
          s,
    ];
  }

  @override
  Future<void> delete(ShareId id) async {
    final Object? error = deleteError;
    if (error != null) throw error;
    deleted.add(id.value);
    shares = <ShareRecord>[
      for (final ShareRecord s in shares)
        if (s.id != id) s,
    ];
    entriesByPath.remove(id.value);
  }

  @override
  Future<({List<TreeEntryView> entries, String? nextCursor})> browse(
    ShareId id, {
    ItemKey? path,
    String? cursor,
    int limit = LanFileConstants.treePageSize,
  }) async {
    browsedPaths.add(path?.value);
    final List<TreeEntryView> all =
        entriesByPath[path?.value ?? ''] ?? const <TreeEntryView>[];
    final int start = cursor == null ? 0 : int.parse(cursor);
    final int end = (start + limit).clamp(0, all.length);
    return (
      entries: all.sublist(start, end),
      nextCursor: end < all.length ? '$end' : null,
    );
  }
}

/// 可编程的群组数据源。
final class FakeGroupsSource implements GroupsSource {
  /// 全部线程。
  List<ThreadRecord> threads = <ThreadRecord>[];

  /// groupId → 群记录。
  Map<String, GroupRecord> groups = <String, GroupRecord>{};

  @override
  Future<List<ThreadRecord>> listThreads() async => threads;

  @override
  Future<GroupRecord?> findGroup(String groupId) async => groups[groupId];
}

/// 用指定 token 包装被测组件（不引入 ProviderScope，页面不依赖 riverpod）。
Widget wrapWithTheme(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: AppTheme.of(LanFilePalette.of(brightness)),
    home: Scaffold(body: child),
  );
}

/// 从 BuildContext 取 token，供测试断言真实取到的色值。
LanFileTokens tokensAt(WidgetTester tester) {
  final BuildContext context = tester.element(find.byType(Scaffold).first);
  return Theme.of(context).extension<LanFileTokens>()!;
}
