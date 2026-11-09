// SPDX-License-Identifier: GPL-3.0-only

/// 附近的人：从发现层拉 PeerView 列表，展示头像/名字/在线状态/分享数。
///
/// 数据来源是注入的 [NearbySource] 而不是直接读 AppServices：
/// 这样 widget test 不需要真起 UDP 发现与 HTTP 服务，也不会把
/// 「渲染正确」与「发现协议正确」混成一条测不动的用例。
/// 生产侧把 [AppServices.tracker] 包成 [TrackerNearbySource] 即可。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../widgets/app_controls.dart';

import '../../app/assembly.dart';
import '../../app/theme/tokens.dart';
import '../../core/contracts/contracts.dart';
import '../../core/discovery/peer_activity_tracker.dart';
import '../../core/contacts/peer_groups.dart';
import '../widgets/app_toast.dart';
import '../widgets/edit_name_dialog.dart';
import '../widgets/peer_card.dart';

/// 附近的人数据源。
abstract interface class NearbySource {
  /// 当前已知的所有 peer（自己排首位，由实现决定）。
  Future<List<PeerView>> listPeers();

  /// 某个 peer 名下的分享（点开某人时用）。
  Future<List<SharedRootView>> listSharesOf(PeerId peer);

  /// 立即刷新一轮发现。
  Future<void> refresh();
}

/// 由发现层活动表支撑的数据源。
final class TrackerNearbySource implements NearbySource {
  /// [shares] 用于点开某人时列其分享；为 null 时该交互显示未连接提示。
  const TrackerNearbySource({
    required this.tracker,
    required this.self,
    this.shares,
  });

  /// 发现层的上下线状态表。
  final PeerActivityTracker tracker;

  /// 本机 peerId；用于把自己排在首位。
  final PeerId self;

  /// 共享服务；点开某人时列其分享。
  final ShareService? shares;

  @override
  Future<List<PeerView>> listPeers() async {
    final List<PeerView> peers = <PeerView>[
      for (final TrackedPeer p in tracker.peers) p.toPeerView(),
    ];
    // 自己排首位：契约 DiscoveryService.watchPeers 要求，且用户最常看自己。
    peers.sort((PeerView a, PeerView b) {
      final bool aSelf = a.peerId == self;
      final bool bSelf = b.peerId == self;
      if (aSelf != bSelf) return aSelf ? -1 : 1;
      if (a.online != b.online) return a.online ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return peers;
  }

  @override
  Future<List<SharedRootView>> listSharesOf(PeerId peer) async {
    final ShareService? service = shares;
    if (service == null) return const <SharedRootView>[];
    return service.listPeerShares(peer);
  }

  @override
  Future<void> refresh() async {
    // 主动 sweep 一次，让超时的 peer 立刻变离线而不是等下一轮公告。
    tracker.sweep();
  }
}

/// 附近的人页面。
class NearbyPage extends StatefulWidget {
  /// [services] 为 null 时显示「未连接服务」，不崩。
  const NearbyPage({
    super.key,
    this.services,
    this.source,
    this.groupsSource,
    this.peerUpdates,
    this.onGroupsChanged,
  });

  /// 装配好的服务栈；为 null 表示纯 UI 模式。
  final AppServices? services;

  /// 可注入的数据源；为 null 时从 [services] 现建。
  final NearbySource? source;
  final PeerGroupsSource? groupsSource;
  final Stream<List<PeerView>>? peerUpdates;
  final VoidCallback? onGroupsChanged;

  @override
  State<NearbyPage> createState() => _NearbyPageState();
}

class _NearbyPageState extends State<NearbyPage> {
  NearbySource? _source;
  PeerGroupsSource? _groupsSource;
  PeerGroups _groups = const PeerGroups();
  List<PeerView> _peers = const <PeerView>[];
  String _query = '';
  final Map<String, Uint8List?> _avatars = <String, Uint8List?>{};
  final Set<String> _collapsed = <String>{};
  StreamSubscription<List<PeerView>>? _subscription;
  StreamSubscription<void>? _profileSubscription;
  bool _loading = true;
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _source = widget.source ?? _sourceFromServices();
    _groupsSource =
        widget.groupsSource ??
        (widget.services == null
            ? null
            : StorePeerGroupsSource(widget.services!.store));
    _subscription =
        (widget.peerUpdates ?? widget.services?.discovery.watchPeers())?.listen(
          _acceptPeers,
          onError: (Object error) {
            if (mounted && _peers.isEmpty) {
              setState(() {
                _error = error;
                _loading = false;
              });
            }
          },
        );
    _profileSubscription = widget.services?.profileChanges.listen((_) {
      unawaited(widget.services!.discovery.refresh());
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _profileSubscription?.cancel();
    super.dispose();
  }

  NearbySource? _sourceFromServices() {
    final AppServices? services = widget.services;
    if (services == null) return null;
    return TrackerNearbySource(
      tracker: services.tracker,
      self: services.identity.peerId,
      shares: services.shares,
    );
  }

  Future<void> _load() async {
    try {
      final PeerGroups groups =
          await _groupsSource?.load() ?? const PeerGroups();
      if (!mounted) return;
      setState(() => _groups = groups);
      if (_subscription == null) {
        _acceptPeers(await _source?.listPeers() ?? const <PeerView>[]);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  void _acceptPeers(List<PeerView> peers) {
    if (!mounted) return;
    setState(() {
      _peers = peers;
      _loading = false;
      _error = null;
    });
    final AppServices? services = widget.services;
    if (services == null) return;
    for (final PeerView peer in peers) {
      final String key = '${peer.peerId.value}:${peer.avatarHash}';
      if (_avatars.containsKey(key)) continue;
      _avatars[key] = null;
      unawaited(
        services.avatarFor(peer).then((Uint8List? bytes) {
          if (mounted) setState(() => _avatars[key] = bytes);
        }),
      );
    }
  }

  Future<void> _saveGroups(PeerGroups groups) async {
    if (_saving || _groupsSource == null) return;
    setState(() => _saving = true);
    try {
      await _groupsSource!.save(groups);
      if (!mounted) return;
      setState(() => _groups = groups);
      widget.onGroupsChanged?.call();
    } on Object catch (error) {
      if (mounted) AppToast.show(context, '分组保存失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editGroup([String? id]) async {
    final String? name = await showAppDialog<String>(
      context: context,
      builder: (_) => EditNameDialog(
        title: id == null ? '新建分组' : '重命名分组',
        label: '分组名称',
        initialValue: id == null ? '' : _groups.names[id]!,
        fieldKey: const ValueKey<String>('peer-group-name-field'),
      ),
    );
    if (name == null || !mounted) return;
    if (name == '陌生人' ||
        _groups.names.entries.any(
          (entry) => entry.key != id && entry.value == name,
        )) {
      AppToast.show(context, '这个分组名称已存在', isError: true);
      return;
    }
    final String key =
        id ?? 'contacts_${DateTime.now().microsecondsSinceEpoch}';
    await _saveGroups(
      PeerGroups(
        names: <String, String>{..._groups.names, key: name},
        assignments: _groups.assignments,
      ),
    );
  }

  Future<void> _deleteGroup(String id) async {
    final bool? confirmed = await showAppDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AppDialog(
        title: const Text('删除分组？'),
        content: Text('「${_groups.names[id]}」中的联系人会移回陌生人。'),
        actions: <Widget>[
          AppButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          AppButton.primary(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _saveGroups(
      PeerGroups(
        names: <String, String>{..._groups.names}..remove(id),
        assignments: <String, String>{
          for (final entry in _groups.assignments.entries)
            if (entry.value != id) entry.key: entry.value,
        },
      ),
    );
  }

  Widget _peerCard(PeerView peer, {bool self = false}) => PeerCard(
    key: ValueKey<String>('nearby-peer-${peer.peerId.value}'),
    peer: peer,
    avatarBytes: _avatars['${peer.peerId.value}:${peer.avatarHash}'],
    onTap: () => _openPeer(peer),
    trailing: self || _groupsSource == null
        ? null
        : AppMenuButton<String>(
            tooltip: '移动到分组',
            enabled: !_saving,
            onSelected: (String group) => _saveGroups(
              PeerGroups(
                names: _groups.names,
                assignments: <String, String>{
                  ..._groups.assignments,
                  peer.peerId.value: group,
                },
              ),
            ),
            itemBuilder: (_) => <AppMenuItem<String>>[
              const AppMenuItem<String>(value: '', label: '陌生人'),
              for (final entry in _groups.names.entries)
                AppMenuItem<String>(value: entry.key, label: entry.value),
            ],
          ),
  );

  Widget _groupSection(String id, String name, List<PeerView> peers) {
    final bool collapsed = _collapsed.contains(id) && _query.trim().isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppListTile(
          key: ValueKey<String>('peer-group-$id'),
          dense: true,
          leading: Icon(
            collapsed ? LucideIcons.chevronRight : LucideIcons.chevronDown,
          ),
          title: Text('$name (${peers.length})'),
          onTap: () => setState(() {
            if (!_collapsed.add(id)) _collapsed.remove(id);
          }),
          trailing: id.isEmpty
              ? null
              : AppMenuButton<String>(
                  tooltip: '管理分组',
                  enabled: !_saving,
                  onSelected: (String value) =>
                      value == 'rename' ? _editGroup(id) : _deleteGroup(id),
                  itemBuilder: (_) => const <AppMenuItem<String>>[
                    AppMenuItem<String>(value: 'rename', label: '重命名'),
                    AppMenuItem<String>(value: 'delete', label: '删除分组'),
                  ],
                ),
        ),
        if (!collapsed)
          for (final PeerView peer in peers) ...<Widget>[
            _peerCard(peer),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    if (_source == null) {
      return const ServicesNotConnected();
    }
    if (_loading) return const Center(child: MiuixCircularProgressIndicator());
    if (_error != null) {
      return _Message(
        icon: LucideIcons.circleAlert,
        title: '加载附近的人失败',
        body: '$_error',
        color: tokens.fgDim,
      );
    }
    final PeerId? self = widget.services?.identity.peerId;
    final query = _query.trim().toLowerCase();
    final List<PeerView> peers = _peers
        .where(
          (peer) =>
              peer.name.toLowerCase().contains(query) ||
              peer.peerId.value.toLowerCase().contains(query),
        )
        .toList();
    return Column(
      children: <Widget>[
        _ListHeader(
          title: '附近的人',
          trailing: '共 ${peers.length} 台设备',
          onAddGroup: _groupsSource == null || _saving
              ? null
              : () => _editGroup(),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: AppTextField(
            key: const ValueKey('nearby-search'),
            onChanged: (value) => setState(() => _query = value),
            label: '搜索名字或设备 ID',
            placeholder: true,
            leading: Icon(LucideIcons.search),
          ),
        ),
        Expanded(
          child: peers.isEmpty && query.isNotEmpty
              ? const Center(child: Text('没有匹配的设备'))
              : peers.isEmpty && _groups.names.isEmpty
              ? const _EmptyNearby()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  children: <Widget>[
                    for (final PeerView peer in peers)
                      if (peer.peerId == self) _peerCard(peer, self: true),
                    _groupSection('', '陌生人', <PeerView>[
                      for (final PeerView peer in peers)
                        if (peer.peerId != self &&
                            _groups.groupOf(peer.peerId).isEmpty)
                          peer,
                    ]),
                    for (final entry in _groups.names.entries)
                      _groupSection(entry.key, entry.value, <PeerView>[
                        for (final PeerView peer in peers)
                          if (peer.peerId != self &&
                              _groups.groupOf(peer.peerId) == entry.key)
                            peer,
                      ]),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _openPeer(PeerView peer) async {
    final NearbySource? source = _source;
    if (source == null) return;
    final List<SharedRootView> shares = await source.listSharesOf(peer.peerId);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PeerSharesSheet(peer: peer, shares: shares),
      ),
    );
  }
}

/// 空状态的诊断文案：说明为什么空、以及能做什么。
///
/// 要求「可读诊断文案」而不是空白：局域网工具最常见的问题是
/// 防火墙/AP 隔离，用户看到一个空列表会以为是软件坏了。
class _EmptyNearby extends StatelessWidget {
  const _EmptyNearby();

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(LucideIcons.wifiOff, size: 40, color: tokens.fgDim),
              const SizedBox(height: 16),
              Text(
                '附近还没有人',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: tokens.fg,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '本机已在线等待，但还没有收到其他设备的公告。\n'
                '可能原因：对方没有打开软件、双方不在同一网段，\n'
                '或系统防火墙拦截了 UDP 47777 广播。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: tokens.fgDim,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '正在后台自动扫描，发现后会出现在陌生人分组。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: tokens.fgDim),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 某人的分享列表（点开卡片后的页面）。
class _PeerSharesSheet extends StatelessWidget {
  const _PeerSharesSheet({required this.peer, required this.shares});

  final PeerView peer;
  final List<SharedRootView> shares;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    return AppScaffold(
      backgroundColor: tokens.bg,
      appBar: MiuixSmallTopAppBar(
        title: peer.name.isEmpty ? peer.peerId.value : peer.name,
        navigationIcon: AppIconButton(
          tooltip: '返回',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(LucideIcons.arrowLeft),
        ),
      ),
      body: shares.isEmpty
          ? Center(
              child: Text(
                '该设备没有对外共享的内容',
                style: TextStyle(fontSize: 13, color: tokens.fgDim),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: shares.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (BuildContext context, int index) {
                final SharedRootView view = shares[index];
                return MiuixCard(
                  child: AppListTile(
                    leading: Icon(
                      view.share.kind == 'file'
                          ? LucideIcons.file
                          : LucideIcons.folder,
                      color: view.available ? tokens.accent : tokens.fgDim,
                    ),
                    title: Text(
                      view.share.displayName,
                      style: TextStyle(color: tokens.fg, fontSize: 14),
                    ),
                    subtitle: Text(
                      view.available ? '可浏览' : (view.offlineHint ?? '当前不可用'),
                      style: TextStyle(color: tokens.fgDim, fontSize: 12),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// 列表页眉：标题 + 计数 + 刷新按钮。
class _ListHeader extends StatelessWidget {
  const _ListHeader({
    required this.title,
    required this.trailing,
    this.onAddGroup,
  });

  final String title;
  final String trailing;
  final VoidCallback? onAddGroup;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: tokens.fg,
            ),
          ),
          const SizedBox(width: 8),
          Text(trailing, style: TextStyle(fontSize: 12, color: tokens.fgDim)),
          const Spacer(),
          if (onAddGroup != null)
            AppIconButton(
              tooltip: '新建分组',
              icon: Icon(LucideIcons.userPlus, size: 18, color: tokens.fgDim),
              onPressed: onAddGroup,
            ),
        ],
      ),
    );
  }
}

/// 通用提示块。
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 36, color: color),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(fontSize: 14, color: tokens.fg)),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: tokens.fgDim),
            ),
          ],
        ),
      ),
    );
  }
}

/// 服务未连接时的统一提示。
///
/// 抽成公开组件：三个页面共用，文案一致，测试也能直接断言。
class ServicesNotConnected extends StatelessWidget {
  /// 可选的自定义说明。
  const ServicesNotConnected({super.key, this.detail});

  /// 补充说明（例如「服务正在启动」）。
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(LucideIcons.cloudOff, size: 40, color: tokens.fgDim),
              const SizedBox(height: 16),
              Text(
                '未连接服务',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: tokens.fg,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                detail ?? '本机服务尚未启动或已停止，此页面暂时没有数据。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: tokens.fgDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
