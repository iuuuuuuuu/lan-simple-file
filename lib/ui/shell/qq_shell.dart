// SPDX-License-Identifier: GPL-3.0-only

/// 悬浮底栏外壳：桌面并排会话列表与主内容区，手机逐页进入。
///
/// 布局契约（也是测试断言的对象）：
/// - 桌面：联系人与群聊共用左侧分组，右侧显示所选会话。
/// - 手机：联系人列表与会话页面前后切换，不提供抽屉。
///
/// 内容由 Key 固定：shell-list / shell-content，底栏为 app-navigation。
/// 服务为 null 时照常渲染选择提示，聊天输入不可用。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../widgets/app_controls.dart';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/assembly.dart';
import '../../app/theme/tokens.dart';
import '../../core/contracts/contracts.dart';
import '../../core/contacts/peer_groups.dart';
import '../../core/messaging/messaging_service_impl.dart';
import '../../core/messaging/chat_search.dart';
import '../pages/groups_page.dart';
import '../pages/settings_page.dart';
import '../pages/shares_page.dart';
import '../pages/transfer_history_page.dart';
import '../widgets/app_toast.dart';
import '../widgets/avatar_badge.dart';
import '../widgets/drop_share_overlay.dart';
import '../widgets/share_row.dart';
import '../widgets/chat_pane.dart';
import '../widgets/chat_search_dialog.dart';
import '../widgets/peer_shares_dialog.dart';
import '../widgets/floating_navigation.dart';
import '../widgets/pick_share_files.dart';
import '../widgets/share_upload_sheet.dart';
import '../widgets/share_picker_dialog.dart';
import '../widgets/edit_name_dialog.dart';
import 'design.dart';
import 'session_list.dart';
import 'session_rail.dart';

/// 三栏布局的断点（取自 tokens）。
const double kThreeColumnBreakpoint = LanFileMetrics.threeColumnMinWidth;

/// 主内容区 Key（测试定位用）。
const ValueKey<String> kShellContentKey = ValueKey<String>('shell-content');

/// 会话来源：把「附近的人 / 群 / 分享」统一投影成 [SessionRowData]。
///
/// 抽成端口而不是在 shell 里直接读服务：widget test 不必起真实局域网，
/// 同时各页面仍能各自保留自己的空态与交互。
abstract interface class ShellSessionSource {
  /// 当前 section 对应的行。
  Future<List<SessionRowData>> rowsFor(ShellSection section);

  /// 列表栏标题。
  String titleFor(ShellSection section);
}

/// 由真实服务栈支撑的会话来源。
final class ServiceShellSessionSource implements ShellSessionSource {
  /// [services] 由组装层注入。
  const ServiceShellSessionSource(this.services);

  /// 已装配的服务栈。
  final AppServices services;

  @override
  String titleFor(ShellSection section) => switch (section) {
    ShellSection.nearby => '附近的人',
    ShellSection.shares => '我的分享',
    ShellSection.groups => '群聊',
    ShellSection.transfers => '传输记录',
    ShellSection.settings => '设置',
  };

  @override
  Future<List<SessionRowData>> rowsFor(ShellSection section) async {
    switch (section) {
      case ShellSection.nearby:
        final threads = await services.store.listThreads();
        final List<PeerView> peers = List<PeerView>.of(
          services.discovery.currentPeers,
        );
        final seen = peers.map((p) => p.peerId).toSet();
        for (final device in await services.store.listDevices()) {
          if (!device.isGuest && !seen.contains(device.peerId)) {
            peers.add(
              PeerView(
                peerId: device.peerId,
                name: device.name,
                avatarHash: device.avatarHash,
                online: device.isSelf,
                shareCount: 0,
                lastSeen: device.lastSeen,
                os: device.os,
              ),
            );
          }
        }
        peers.sort((PeerView a, PeerView b) {
          final bool aSelf = a.peerId == services.identity.peerId;
          final bool bSelf = b.peerId == services.identity.peerId;
          if (aSelf != bSelf) return aSelf ? -1 : 1;
          if (a.online != b.online) return a.online ? -1 : 1;
          return a.name.compareTo(b.name);
        });
        return Future.wait([
          for (final PeerView peer in peers)
            Future<SessionRowData>(() async {
              final thread = threads
                  .where((t) => t.peerId == peer.peerId && t.deletedAt == null)
                  .firstOrNull;
              return SessionRowData(
                id: peer.peerId.value,
                peerId: peer.peerId.value,
                title: peer.name.isEmpty ? peer.peerId.value : peer.name,
                avatarSeed: peer.peerId.value,
                subtitle: thread?.lastMsgPreview?.isNotEmpty == true
                    ? thread!.lastMsgPreview!
                    : peer.online
                    ? '${peer.shareCount} 项共享'
                    : '离线 · ${peer.shareCount} 项共享',
                timeLabel: _timeLabel(
                  thread?.lastMsgHlc == null
                      ? peer.lastSeen
                      : DateTime.fromMillisecondsSinceEpoch(
                          thread!.lastMsgHlc!.millis,
                        ),
                ),
                online: peer.online,
                os: peer.os,
                isSelf: peer.peerId == services.identity.peerId,
                unread: thread?.unread ?? 0,
                avatarBytes: await services.avatarFor(peer),
              );
            }),
        ]);
      case ShellSection.shares:
        final shares = [...await services.shares.listMine()]
          ..sort(compareShareRecords);
        return <SessionRowData>[
          for (final ShareRecord share in shares)
            SessionRowData(
              id: share.id.value,
              title: share.displayName.trim().isEmpty
                  ? shareLocationLabel(share)
                  : share.displayName,
              avatarSeed: share.ownerPeerId.value,
              subtitle: share.mode.name,
              timeLabel: _timeLabel(share.createdAt),
            ),
        ];
      case ShellSection.groups:
        final List<ThreadRecord> threads = await services.store.listThreads();
        final List<SessionRowData> rows = <SessionRowData>[];
        for (final ThreadRecord thread in threads) {
          if (thread.kind != 'group') continue;
          final String groupId = thread.groupId ?? '';
          if (groupId.isEmpty) continue;
          rows.add(
            SessionRowData(
              id: thread.id,
              title: thread.title.isEmpty ? groupId : thread.title,
              avatarSeed: groupId,
              subtitle: thread.lastMsgPreview?.isNotEmpty == true
                  ? thread.lastMsgPreview!
                  : '还没有消息',
              timeLabel: _timeLabel(thread.createdAt),
              unread: thread.unread,
              isGroup: true,
            ),
          );
        }
        return rows;
      case ShellSection.transfers:
        final List<TransferRecord> transfers = await services.store
            .listTransfers();
        return <SessionRowData>[
          for (final TransferRecord t in transfers)
            SessionRowData(
              id: t.id,
              title: t.itemKey.value.split('/').last,
              avatarSeed: t.peerId.value,
              subtitle: '${t.status.name} · ${t.bytesDone}/${t.bytesTotal}',
              timeLabel: _timeLabel(t.createdAt),
            ),
        ];
      case ShellSection.settings:
        return const <SessionRowData>[];
    }
  }
}

/// 时间标签：今天显示时分，更早显示月/日。
String? _timeLabel(DateTime? at) {
  if (at == null) return null;
  final DateTime local = at.toLocal();
  final DateTime now = DateTime.now();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    final String hh = local.hour.toString().padLeft(2, '0');
    final String mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
  return '${local.month}/${local.day}';
}

/// QQ 风格外壳。
class QqShell extends StatefulWidget {
  /// [services] 为 null 时骨架照常渲染，内容区显示未连接。
  const QqShell({
    super.key,
    this.services,
    this.sessionSource,
    this.sections = defaultSections,
    this.enableDragDrop = true,
    this.dropHandler,
    this.initialSection = ShellSection.nearby,
    this.currentUserName,
    this.groupsSource,
    this.messaging,
    this.chatSearchSource,
  });

  /// 默认展示的 section（不含设置；设置由头像/齿轮进入）。
  static const List<ShellSection> defaultSections = <ShellSection>[
    ShellSection.nearby,
    ShellSection.shares,
    ShellSection.transfers,
  ];

  /// 服务栈。
  final AppServices? services;

  /// 可注入的会话来源（测试用）。
  final ShellSessionSource? sessionSource;

  /// 图标栏显示哪些 section。
  final List<ShellSection> sections;

  /// 是否启用拖入建共享（**Android 传 false**）。
  final bool enableDragDrop;

  /// 拖入处理端口。
  final DropShareHandler? dropHandler;

  /// 初始 section。
  final ShellSection initialSection;

  /// 本机登录账户名；设置页的昵称初始值用它（null 时由设置页自己回落）。
  final String? currentUserName;
  final PeerGroupsSource? groupsSource;
  final MessagingService? messaging;
  final ChatSearchSource? chatSearchSource;

  @override
  State<QqShell> createState() => _QqShellState();
}

class _QqShellState extends State<QqShell> {
  final _navigationBackdrop = MiuixLayerBackdrop();
  late ShellSection _section = widget.initialSection == ShellSection.groups
      ? ShellSection.nearby
      : widget.initialSection;
  ShellSessionSource? _source;
  String? _selectedRowId;
  String? _focusedMessageId;
  ChatSearchSource? get _chatSearch =>
      widget.chatSearchSource ??
      (widget.services == null
          ? null
          : StoreChatSearchSource(widget.services!.store));
  Future<List<SessionRowData>>? _rows;
  StreamSubscription<void>? _profileSubscription;
  StreamSubscription<List<PeerView>>? _peerSubscription;
  StreamSubscription<List<ThreadRecord>>? _threadSubscription;
  List<SessionRowData> _rowData = [];
  SessionRowData? _selectedSession;
  PeerGroups _groups = const PeerGroups();
  PeerGroupsSource? _groupsSource;
  bool _savingGroup = false;
  // 提示不再用顶部条：拖入结果统一走 AppToast 浮层（见 onResult）。

  /// 上一条拖入提示是否是失败态（决定提示条配色）。

  @override
  void initState() {
    super.initState();
    _source =
        widget.sessionSource ??
        (widget.services == null
            ? null
            : ServiceShellSessionSource(widget.services!));
    _reloadRows();
    _subscribe();
    _groupsSource =
        widget.groupsSource ??
        (widget.services == null
            ? null
            : StorePeerGroupsSource(widget.services!.store));
    unawaited(_loadGroups());
  }

  Future<void> _loadGroups() async {
    try {
      final groups = await _groupsSource?.load() ?? const PeerGroups();
      if (mounted) setState(() => _groups = groups);
    } on Object catch (error) {
      if (mounted) AppToast.show(context, '读取分组失败：$error', isError: true);
    }
  }

  Future<void> _saveGroups(PeerGroups groups) async {
    if (_groupsSource == null || _savingGroup) return;
    _savingGroup = true;
    try {
      await _groupsSource!.save(groups);
      if (mounted) setState(() => _groups = groups);
    } on Object catch (error) {
      if (mounted) AppToast.show(context, '保存分组失败：$error', isError: true);
    } finally {
      _savingGroup = false;
    }
  }

  Future<void> _editGroup([String? id]) async {
    final name = await showAppDialog<String>(
      context: context,
      builder: (_) => EditNameDialog(
        title: id == null ? '新建分组' : '重命名分组',
        label: '分组名称',
        initialValue: id == null ? '' : _groups.names[id]!,
        fieldKey: const ValueKey('session-group-name-field'),
      ),
    );
    if (name == null || !mounted) return;
    if (['陌生人', '群聊', '本机'].contains(name) ||
        _groups.names.entries.any(
          (entry) => entry.key != id && entry.value == name,
        )) {
      AppToast.show(context, '这个分组名称已存在', isError: true);
      return;
    }
    final key = id ?? 'contacts_${DateTime.now().microsecondsSinceEpoch}';
    await _saveGroups(
      PeerGroups(
        names: {..._groups.names, key: name},
        assignments: _groups.assignments,
      ),
    );
  }

  Future<void> _deleteGroup(String id) async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: const Text('删除分组？'),
        content: Text('「${_groups.names[id]}」中的联系人和群聊会回到默认分组。'),
        actions: [
          AppButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          AppButton.primary(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _saveGroups(
      PeerGroups(
        names: {..._groups.names}..remove(id),
        assignments: {
          for (final entry in _groups.assignments.entries)
            if (entry.value != id) entry.key: entry.value,
        },
      ),
    );
  }

  Future<void> _createGroup() async {
    final services = widget.services;
    if (services == null) return;
    final members = await services.store.listDevices();
    if (!mounted) return;
    final request = await showCreateGroupDialog(context, members: members);
    if (request == null || !mounted) return;
    try {
      final groupId = await services.messaging.createGroup(
        request.name,
        request.members,
      );
      _reloadSilently();
      if (mounted) {
        setState(() {
          _selectedRowId = 'g_$groupId';
          _selectedSession = SessionRowData(
            id: 'g_$groupId',
            title: request.name,
            avatarSeed: groupId,
            isGroup: true,
          );
        });
      }
    } on Object catch (error) {
      if (mounted) AppToast.show(context, '创建群聊失败：$error', isError: true);
    }
  }

  Future<List<SessionRowData>> _readRows(ShellSection section) async {
    final source = _source;
    if (source == null) return [];
    final result = await source.rowsFor(section);
    if (section != ShellSection.nearby) return result;
    return [...result, ...await source.rowsFor(ShellSection.groups)];
  }

  void _subscribe() {
    _profileSubscription?.cancel();
    _peerSubscription?.cancel();
    _threadSubscription?.cancel();
    final AppServices? services = widget.services;
    _profileSubscription = services?.profileChanges.listen((_) {
      if (mounted) {
        setState(() {
          _reloadRows();
        });
      }
    });
    _peerSubscription = services?.discovery.watchPeers().listen((_) {
      if (mounted && _section == ShellSection.nearby) {
        _reloadSilently();
      }
    });
    _threadSubscription = (widget.messaging ?? services?.messaging)
        ?.watchThreads()
        .listen((threads) {
          if (!mounted) return;
          final total = threads
              .where((thread) => thread.deletedAt == null)
              .fold<int>(
                0,
                (sum, thread) => sum + (thread.unread > 0 ? thread.unread : 0),
              );
          setState(() => _chatUnread = total);
          if (_section == ShellSection.nearby) _reloadSilently();
        });
  }

  int _chatUnread = 0;
  int _rowGeneration = 0;
  void _reloadSilently() {
    final ShellSessionSource? source = _source;
    if (source == null) return;
    final int generation = ++_rowGeneration;
    final ShellSection section = _section;
    unawaited(
      _readRows(section)
          .then((List<SessionRowData> rows) {
            if (mounted &&
                _section == section &&
                generation == _rowGeneration) {
              setState(() {
                _rowData = rows;
                _rows = Future<List<SessionRowData>>.value(rows);
              });
            }
          })
          .catchError((Object _) {}),
    );
  }

  @override
  void dispose() {
    _navigationBackdrop.dispose();
    _profileSubscription?.cancel();
    _peerSubscription?.cancel();
    _threadSubscription?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(QqShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sessionSource != oldWidget.sessionSource ||
        widget.services != oldWidget.services ||
        widget.messaging != oldWidget.messaging) {
      _source =
          widget.sessionSource ??
          (widget.services == null
              ? null
              : ServiceShellSessionSource(widget.services!));
      _reloadRows();
      _subscribe();
    }
  }

  void _reloadRows() {
    final ShellSessionSource? source = _source;
    if (source == null) {
      _rows = Future<List<SessionRowData>>.value(const <SessionRowData>[]);
      return;
    }
    final generation = ++_rowGeneration;
    _rows = _readRows(_section).then((rows) {
      if (mounted && generation == _rowGeneration) {
        setState(() => _rowData = rows);
      }
      return rows;
    });
  }

  void _selectSection(ShellSection section) {
    setState(() {
      _section = section;
      _selectedRowId = null;
      _selectedSession = null;
      _reloadRows();
    });
  }

  void _openSettings() {
    setState(() {
      _section = ShellSection.settings;
      _selectedRowId = null;
      _selectedSession = null;
      _reloadRows();
    });
  }

  bool _uploading = false;
  bool _choosingUpload = false;
  int _sharesRevision = 0;
  Future<void> _uploadFiles() async {
    if (_uploading || _choosingUpload || widget.services == null) return;
    setState(() => _choosingUpload = true);
    try {
      final kind = await showShareUploadSheet(context);
      if (kind == null || !mounted) return;
      setState(() => _uploading = true);
      debugPrint('share-picker selection: ${kind.name}');
      final shares = switch (kind) {
        ShareUploadKind.folder => await pickShareFolder(widget.services!),
        ShareUploadKind.file => await pickShareFiles(widget.services!),
        ShareUploadKind.photo => await pickShareFiles(
          widget.services!,
          photos: true,
        ),
      };
      if (!mounted || shares.isEmpty) return;
      setState(() => _sharesRevision++);
      if (_selectedSession != null && _sectionWantsList(_section)) {
        final row = _selectedSession!;
        final self = widget.services!.identity.peerId;
        final thread = row.isGroup
            ? row.id
            : directThreadId(self, PeerId.parse(row.id));
        for (final share in shares) {
          await widget.services!.messaging.sendFile(thread, share.id);
        }
      } else {
        _selectSection(ShellSection.shares);
      }
      if (mounted) {
        AppToast.show(context, '已加入分享 ${shares.length} 项');
      }
    } on Object catch (error) {
      if (mounted) {
        AppToast.show(context, '分享失败：$error', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _choosingUpload = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens =
        Theme.of(context).extension<LanFileTokens>() ??
        LanFilePalette.of(Theme.of(context).brightness);
    final double width = MediaQuery.sizeOf(context).width;
    final mobile = width < 600;
    final inConversation =
        _sectionWantsList(_section) && _selectedRowId != null;
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final navigationVisible = (!mobile || !inConversation) && !keyboardVisible;
    final navigationClearance = navigationVisible
        ? FloatingNavigation.clearance(context)
        : keyboardVisible
        ? 0.0
        : MediaQuery.viewPaddingOf(context).bottom;

    // 聊天入口保留联系人与群聊分组；分享、传输和设置铺满内容区。
    // 手机先展示列表，选择会话后进入聊天，顶部提供返回列表的按钮。
    final bool needsList = _sectionWantsList(_section);
    final bool threeColumn =
        needsList && (width >= 600 || _selectedRowId == null);
    final bool showChat = !needsList || width >= 600 || _selectedRowId != null;

    final Widget list = _buildList();

    final Widget content = Padding(
      padding: EdgeInsets.only(
        bottom: inConversation ? navigationClearance : 0,
      ),
      child: _buildContent(),
    );

    // 桌面列表与聊天并排，手机按当前选择显示其中一栏。
    final Widget body = mobile
        ? SizedBox.expand(
            child: showChat
                ? Container(
                    key: kShellContentKey,
                    color: tokens.bg,
                    child: content,
                  )
                : list,
          )
        : Row(
            children: <Widget>[
              if (threeColumn) ...<Widget>[
                showChat ? list : Expanded(child: list),
                AppVerticalDivider(width: 1, color: tokens.line),
              ],
              if (showChat)
                Expanded(
                  child: Container(
                    key: kShellContentKey,
                    // 最"近"的一层：内容区底色。
                    color: surfaceOf(tokens, SurfaceTier.content),
                    child: content,
                  ),
                ),
            ],
          );

    final Widget dropped = DropShareOverlay(
      enableDragDrop:
          widget.enableDragDrop && !(needsList && _selectedRowId != null),
      handler:
          widget.dropHandler ??
          (widget.services == null
              ? null
              : ServiceDropShareHandler(create: widget.services!.sharePath)),
      onResult: (int created, int total) {
        if (!mounted) return;
        // 失败时必须带上**第一条具体原因**：只报「N 个失败」，用户无法判断
        // 是权限、越界还是文件已不存在，也就无从重试。
        final String base = created == total
            ? '已创建 $created 个共享'
            : '已创建 $created 个共享，${total - created} 个失败';
        final List<DropShareFailure> failures =
            ServiceDropShareHandler.lastFailures;
        final String detail = failures.isEmpty
            ? ''
            : '：${failures.first.shortName} — ${failures.first.message}';
        // 浮层提示：不顶走布局，也不在顶部条常驻。
        AppToast.show(context, base + detail, isError: created != total);
        setState(() {
          if (created > 0) _sharesRevision++;
          _reloadRows();
        });
      },
      child: body,
    );

    final shell = PopScope(
      canPop: !mobile || !inConversation,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          setState(() {
            _selectedRowId = null;
            _selectedSession = null;
          });
        }
      },
      child: AppScaffold(
        backgroundColor: tokens.bg,
        extendBody: true,
        bottomNavigationBar: navigationVisible
            ? FloatingNavigation(
                backdrop: _navigationBackdrop,
                selected: _section,
                onSelect: _selectSection,
                unread: _chatUnread,
              )
            : null,
        body: FloatingNavigationInsets(
          bottom: navigationClearance,
          child: MiuixLayerBackdropCapture(
            backdrop: _navigationBackdrop,
            // The blurred background needs no high-DPI full-window snapshot.
            pixelRatio: 1,
            child: Column(
              children: <Widget>[
                if (!mobile)
                  _TopBar(
                    title: _section.label,
                    trailing: AppIconButton(
                      key: const ValueKey('shell-self-avatar'),
                      tooltip: '本机设置',
                      onPressed: _openSettings,
                      padding: const EdgeInsets.all(4),
                      icon: AvatarBadge(
                        peerId:
                            widget.services?.identity.peerId.value ??
                            'p_localdevice00',
                        avatarBytes: widget.services?.avatars?.selfBytes,
                        size: 28,
                      ),
                    ),
                    onBack: needsList && width < 600 && _selectedRowId != null
                        ? () => setState(() {
                            _selectedRowId = null;
                            _selectedSession = null;
                          })
                        : null,
                  ),
                if (!mobile) AppDivider(height: 1, color: tokens.line),
                Expanded(child: dropped),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mobile && !Platform.isAndroid) {
      return AbsorbPointer(
        absorbing: _uploading || _choosingUpload,
        child: shell,
      );
    }
    final background = needsList && !inConversation
        ? tokens.surfaceSunken
        : tokens.bg;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: tokens.isDark
            ? Brightness.light
            : Brightness.dark,
        systemStatusBarContrastEnforced: false,
      ),
      child: ColoredBox(
        key: const ValueKey('mobile-system-background'),
        color: background,
        child: SafeArea(
          bottom: false,
          child: AbsorbPointer(
            absorbing: _uploading || _choosingUpload,
            child: shell,
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    final Future<List<SessionRowData>>? rows = _rows;
    if (rows == null) {
      return SessionList(
        title: _section.label,
        rows: const <SessionRowData>[],
        selectedId: _selectedRowId,
        onSelect: (SessionRowData row) {},
        emptyTitle: '未连接服务',
        emptyBody: '本机服务尚未启动，列表暂时没有数据。',
      );
    }
    return FutureBuilder<List<SessionRowData>>(
      future: rows,
      builder:
          (BuildContext context, AsyncSnapshot<List<SessionRowData>> snapshot) {
            final List<SessionRowData> data =
                snapshot.data ?? const <SessionRowData>[];
            return SessionList(
              hint: _section == ShellSection.nearby ? '搜索名字或设备 ID' : '搜索',
              title: _source?.titleFor(_section) ?? _section.label,
              rows: data,
              selectedId: _selectedRowId,
              onSelect: _selectSession,
              groups: _section == ShellSection.nearby ? _groups : null,
              onEditGroup: (id) => _editGroup(id),
              onDeleteGroup: _deleteGroup,
              onMoveSession: _groupsSource == null
                  ? null
                  : (row, id) => _saveGroups(
                      PeerGroups(
                        names: _groups.names,
                        assignments: {..._groups.assignments}
                          ..remove(row.id)
                          ..addAll({row.id: ?id}),
                      ),
                    ),
              actions: [
                if (_section == ShellSection.nearby && _chatSearch != null)
                  AppIconButton(
                    key: const ValueKey('chat-history-search-button'),
                    tooltip: '搜索聊天记录和文件',
                    icon: const Icon(LucideIcons.search),
                    onPressed: _searchMessages,
                  ),
                if (_section == ShellSection.nearby &&
                    (_groupsSource != null || widget.services != null))
                  AppMenuButton<String>(
                    key: const ValueKey('session-add'),
                    tooltip: '添加',
                    icon: const Icon(LucideIcons.plus, size: 18),
                    itemBuilder: (_) => [
                      if (_groupsSource != null)
                        const AppMenuItem(value: 'grouping', label: '新建分组'),
                      if (widget.services != null)
                        const AppMenuItem(value: 'chat', label: '新建群聊'),
                    ],
                    onSelected: (value) =>
                        value == 'chat' ? _createGroup() : _editGroup(),
                  ),
              ],
              // 列表与聊天区的空态分别说明当前可执行的操作。
              emptyTitle: _shortEmptyFor(_section),
              emptyBody: '',
            );
          },
    );
  }

  void _selectSession(SessionRowData row) {
    setState(() {
      _focusedMessageId = null;
      _selectedRowId = row.id;
      _selectedSession = row;
    });
    final peer = row.isGroup ? null : PeerId.tryParse(row.id);
    if (peer != null) {
      unawaited(
        widget.services?.chatConnections
                ?.connect(peer)
                .catchError((Object _) {}) ??
            Future<void>.value(),
      );
    }
  }

  Future<void> _searchMessages({String? threadId}) async {
    final source = _chatSearch;
    if (source == null) return;
    final hit = await showAppDialog<ChatSearchHit>(
      context: context,
      builder: (_) => ChatSearchDialog(source: source, threadId: threadId),
    );
    if (hit == null || !mounted) return;
    final thread = hit.thread;
    final id = thread.kind == 'group' ? thread.id : thread.peerId?.value;
    if (id == null) return;
    final row =
        _rowData.where((row) => row.id == id).firstOrNull ??
        SessionRowData(
          id: id,
          title: thread.title,
          avatarSeed: thread.peerId?.value ?? thread.groupId ?? id,
          subtitle: '',
          isGroup: thread.kind == 'group',
          peerId: thread.peerId?.value,
        );
    _selectSession(row);
    setState(() {
      _section = ShellSection.nearby;
      _focusedMessageId = hit.message.id;
    });
  }

  Future<ShareId?> _pickShare() async {
    final shares = await widget.services!.shares.listMine();
    if (!mounted) return null;
    return showAppDialog<ShareId>(
      context: context,
      builder: (context) => SharePickerDialog(
        shares: shares
            .where((s) => s.enabled && !s.isRevoked && !s.missing)
            .toList(),
      ),
    );
  }

  Future<void> _showPeerShares(PeerId peer) async {
    final services = widget.services;
    if (services == null) return;
    final client = services.peerShareClient(peer);
    final row =
        _rowData.where((row) => row.id == peer.value).firstOrNull ??
        (_selectedSession?.id == peer.value ? _selectedSession : null);
    final name = peer == services.identity.peerId
        ? services.profile.name
        : row?.title ?? peer.value;
    final avatar = peer == services.identity.peerId
        ? services.avatars?.selfBytes
        : row?.avatarBytes;
    try {
      await showAppDialog<void>(
        context: context,
        builder: (_) => PeerSharesDialog(
          peer: peer,
          name: name,
          avatarBytes: avatar,
          loadCatalog: client.catalog,
          browse: client.browse,
          homeLink: () => services.buildPeerWebHomeLink(peer),
          shareLink: (share) => services.buildPeerWebLink(peer, share),
          onFileOpened: (share, file) async {
            await services.transferHistory?.record(
              name: file.name,
              direction: TransferDirection.download,
              status: 'external',
              peer: peer,
              peerLabel: name,
              share: share,
              item: file.itemKey,
              bytes: file.size,
            );
          },
          openLink: (uri) async {
            if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
              throw const LanFileException(
                LanFileErrorCode.io,
                '无法打开浏览器，请复制链接后打开',
              );
            }
          },
        ),
      );
    } finally {
      client.close();
    }
  }

  Widget _buildContent() {
    switch (_section) {
      case ShellSection.nearby:
      case ShellSection.groups:
        final row =
            _rowData.where((r) => r.id == _selectedRowId).firstOrNull ??
            _selectedSession;
        if (row == null) {
          return const _PlaceholderContent(
            icon: LucideIcons.messageCircle,
            title: '选择联系人或群聊',
            body: '从左侧分组列表选择，开始聊天。',
          );
        }
        final self =
            widget.services?.identity.peerId ?? PeerId.parse('p_localdevice00');
        final peer = PeerId.tryParse(row.id);
        if (!row.isGroup && peer == null) {
          return const _PlaceholderContent(
            icon: LucideIcons.messageCircle,
            title: '聊天服务未启动',
            body: '这条会话没有有效的设备标识。',
          );
        }
        final threadId = row.isGroup ? row.id : directThreadId(self, peer!);
        return ChatPane(
          onBack: MediaQuery.sizeOf(context).width < 600
              ? () => setState(() {
                  _selectedRowId = null;
                  _selectedSession = null;
                })
              : null,
          onUpload: widget.services == null ? null : _uploadFiles,
          key: ValueKey('chat-$threadId'),
          threadId: threadId,
          focusMessageId: _focusedMessageId,
          onClearFocus: () => setState(() => _focusedMessageId = null),
          onSearch: _chatSearch == null
              ? null
              : () => _searchMessages(threadId: threadId),
          title: row.title,
          self: self,
          avatarSeed: row.avatarSeed,
          peer: row.isGroup ? null : peer,
          onShowShares: widget.services == null ? null : _showPeerShares,
          avatarBytes: row.avatarBytes,
          selfAvatarBytes: widget.services?.avatars?.selfBytes,
          senderAvatars: {for (final r in _rowData) r.id: r.avatarBytes},
          messaging: widget.messaging ?? widget.services?.messaging,
          subtitle: row.isGroup
              ? '群聊'
              : peer == self
              ? '本机消息'
              : row.online == true
              ? '在线'
              : '离线 · 消息将在连接后送达',
          senderNames: {for (final r in _rowData) r.id: r.title},
          onRead: widget.services == null
              ? null
              : () => widget.services!.messaging.markRead(threadId),
          sharePicker: widget.services == null ? null : _pickShare,
          enableDragDrop: widget.enableDragDrop,
          shareCreator: widget.services == null
              ? null
              : (path) async => (await widget.services!.sharePath(path)).id,
          shareLinkResolver: widget.services?.buildPeerWebLink,
        );
      case ShellSection.shares:
        return SharesPage(
          services: widget.services,
          refreshRevision: _sharesRevision,
          onCreateShare: widget.services == null ? null : _uploadFiles,
          creating: _uploading,
        );
      case ShellSection.transfers:
        return TransferHistoryPage(services: widget.services);
      case ShellSection.settings:
        // services 为 null 时也渲染真实设置页：页内自己会显示「未连接服务」，
        // 但「关于」等静态内容照常可见——换成占位会让用户在未连服务时
        // 连版本与许可证都看不到，那是信息缺失而不是降级。
        final AppServices? s = widget.services;
        return SettingsPage(
          services: s,
          currentUserName: widget.currentUserName,
          revokeAllLinks: s == null ? null : () => s.revocation.revokeAll(),
          // 改名走 renameSelf：一次写 store + profile + peers 表，
          // 否则别的节点 ping 到的还是旧名字。
          renameSelf: s?.renameSelf,
        );
    }
  }

  /// 中栏空态：一句话，短到不占视线。
  /// 该 section 是否真的需要一栏「列表」来做选择。
  ///
  /// 判据是**有没有「先选一个、再看它」的两级结构**，而不是屏幕宽度。
  /// 没有两级结构的 section 再宽也不该有中栏。
  static bool _sectionWantsList(ShellSection section) => switch (section) {
    ShellSection.nearby => true,
    ShellSection.groups => true,
    ShellSection.shares => false,
    ShellSection.transfers => false,
    ShellSection.settings => false,
  };

  static String _shortEmptyFor(ShellSection section) => switch (section) {
    ShellSection.nearby => '暂无',
    ShellSection.shares => '暂无',
    ShellSection.groups => '暂无',
    ShellSection.transfers => '暂无',
    ShellSection.settings => '',
  };
}

/// 顶部条：显示当前页面标题，手机聊天页提供返回列表的入口。
///
/// 提示一律走 AppToast 浮层（见 widgets/app_toast.dart）：
/// 用户明确否掉了「上面显示个内个啥」的常驻顶部条，
/// 因此这里**不再承载任何提示文本或关闭按钮**。
class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, this.onBack, this.trailing});

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    return Container(
      key: const ValueKey<String>('shell-top-bar'),
      height: 44,
      color: surfaceOf(tokens, SurfaceTier.list),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: <Widget>[
          if (onBack != null)
            AppIconButton(
              tooltip: '返回联系人',
              icon: Icon(LucideIcons.arrowLeft, size: 20, color: tokens.fgDim),
              onPressed: onBack,
            ),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: tokens.fg,
            ),
          ),
          if (trailing != null) ...[const Spacer(), trailing!],
        ],
      ),
    );
  }
}

/// 尚未接入真实内容的 section 的占位。
class _PlaceholderContent extends StatelessWidget {
  const _PlaceholderContent({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

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
              Icon(icon, size: 40, color: tokens.fgDim),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: tokens.fg,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
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
