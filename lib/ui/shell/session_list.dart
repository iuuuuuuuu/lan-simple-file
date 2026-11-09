// SPDX-License-Identifier: GPL-3.0-only

/// 中栏会话列表：搜索框 + 可复用行（头像 + 名字 + 摘要 + 时间 + 未读红点）。
///
/// 设计语言（见 shell/design.dart）：
/// - 行高 64 / 内边距 12×8，紧凑不挤；
/// - 三态反馈：普通透明 / hover 用 hoverSoft / 选中用 accentSoft + 主色描边；
/// - 栏底色用 surfaceSunken，与内容区 bg 形成可见明度差。
library;

import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../widgets/app_controls.dart';

import '../../app/theme/tokens.dart';
import '../../core/contacts/peer_groups.dart';
import '../widgets/avatar_badge.dart';
import '../widgets/device_platform_label.dart';
import '../widgets/device_id_label.dart';
import 'design.dart';

/// 中栏宽度（与 tokens 的 sessionListWidth 对齐，供外部断言引用）。
const double kSessionListWidth = LanFileMetrics.sessionListWidth;

/// 列表行圆角。
const double kSessionRowRadius = LanFileMetrics.radiusRow;

/// 一行会话的通用数据投影。
///
/// 与会话来源解耦：附近的人、群、分享都能映射成它，
/// 这样列表只写一次，各页面只提供投影。
final class SessionRowData {
  const SessionRowData({
    required this.id,
    required this.title,
    required this.avatarSeed,
    this.subtitle = '',
    this.timeLabel,
    this.unread = 0,
    this.online,
    this.isGroup = false,
    this.avatarBytes,
    this.isSelf = false,
    this.os,
    this.peerId,
  });

  /// 稳定标识（用于 Key 与选中判定）。
  final String id;

  /// 主标题。
  final String title;

  /// 生成 identicon 的种子（peerId 或 groupId）。
  final String avatarSeed;

  /// 摘要行。
  final String subtitle;

  /// 右上时间文案（已格式化）；null 时不显示。
  final String? timeLabel;

  /// 未读数。
  final int unread;

  /// 在线状态；null 表示不适用（例如群）。
  final bool? online;

  /// 是否群会话（影响状态点显示）。
  final bool isGroup;
  final Uint8List? avatarBytes;
  final bool isSelf;
  final String? os;
  final String? peerId;
}

/// 中栏：搜索 + 列表。
class SessionList extends StatefulWidget {
  /// [rows] 为已投影好的行；搜索在本地做（局域网名单量级很小）。
  const SessionList({
    super.key,
    required this.title,
    required this.rows,
    required this.selectedId,
    required this.onSelect,
    this.hint = '搜索',
    this.emptyTitle = '暂无会话',
    this.emptyBody = '',
    this.actions = const <Widget>[],
    this.groups,
    this.onEditGroup,
    this.onDeleteGroup,
    this.onMoveSession,
  });

  /// 栏标题（例如「附近的人」）。
  final String title;

  /// 全部行。
  final List<SessionRowData> rows;

  /// 当前选中行 id。
  final String? selectedId;

  /// 选中回调。
  final ValueChanged<SessionRowData> onSelect;

  /// 搜索框占位文案。
  final String hint;

  /// 空态标题。
  final String emptyTitle;

  /// 空态说明。
  final String emptyBody;

  /// 标题右侧操作按钮。
  final List<Widget> actions;
  final PeerGroups? groups;
  final ValueChanged<String>? onEditGroup;
  final ValueChanged<String>? onDeleteGroup;
  final void Function(SessionRowData row, String? groupId)? onMoveSession;

  @override
  State<SessionList> createState() => _SessionListState();
}

class _SessionListState extends State<SessionList> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  final Set<String> _collapsed = {};

  Future<void> _rowMenu(SessionRowData row, Offset position) async {
    if (widget.groups == null || widget.onMoveSession == null) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showAppMenu<String>(
      context: context,
      position: RelativeRect.fromSize(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        overlay.size,
      ),
      items: [
        AppMenuItem(
          value: '',
          label:
              '移到${row.isGroup
                  ? '群聊'
                  : row.isSelf
                  ? '本机'
                  : '陌生人'}',
        ),
        for (final entry in widget.groups!.names.entries)
          AppMenuItem(value: entry.key, label: '移到 ${entry.value}'),
      ],
    );
    if (choice != null && mounted) {
      widget.onMoveSession!(row, choice.isEmpty ? null : choice);
    }
  }

  Widget _groupedRows(List<SessionRowData> rows, LanFileTokens tokens) {
    final groups = widget.groups!;
    final buckets = <String, List<SessionRowData>>{
      if (rows.any((r) => r.isSelf)) '@self': [],
      '@strangers': [],
      '@groups': [],
      for (final id in groups.names.keys) id: [],
    };
    for (final row in rows) {
      final assigned = groups.groupOfSession(row.id);
      final key = assigned.isNotEmpty
          ? assigned
          : row.isSelf
          ? '@self'
          : row.isGroup
          ? '@groups'
          : '@strangers';
      buckets.putIfAbsent(key, () => []).add(row);
    }
    final names = {
      '@self': '本机',
      '@strangers': '陌生人',
      '@groups': '群聊',
      ...groups.names,
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
      children: [
        for (final entry in buckets.entries)
          if (_query.trim().isEmpty || entry.value.isNotEmpty) ...[
            SizedBox(
              height: 34,
              child: Row(
                children: [
                  Expanded(
                    child: MiuixPressable(
                      key: ValueKey('session-group-${entry.key}'),
                      borderRadius: BorderRadius.circular(6),
                      onPressed: () => setState(() {
                        if (!_collapsed.add(entry.key)) {
                          _collapsed.remove(entry.key);
                        }
                      }),
                      child: Row(
                        children: [
                          Icon(
                            _collapsed.contains(entry.key)
                                ? LucideIcons.chevronRight
                                : LucideIcons.chevronDown,
                            size: 18,
                            color: tokens.fgDim,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${names[entry.key]} (${entry.value.length})',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: tokens.fgDim,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (groups.names.containsKey(entry.key))
                    AppMenuButton<String>(
                      tooltip: '分组操作',
                      iconSize: 16,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      itemBuilder: (_) => const [
                        AppMenuItem(value: 'rename', label: '重命名分组'),
                        AppMenuItem(value: 'delete', label: '删除分组'),
                      ],
                      onSelected: (value) => value == 'rename'
                          ? widget.onEditGroup?.call(entry.key)
                          : widget.onDeleteGroup?.call(entry.key),
                    ),
                ],
              ),
            ),
            if (!_collapsed.contains(entry.key) || _query.trim().isNotEmpty)
              for (final row in entry.value)
                GestureDetector(
                  onSecondaryTapDown: (details) =>
                      _rowMenu(row, details.globalPosition),
                  onLongPressStart: (details) =>
                      _rowMenu(row, details.globalPosition),
                  child: SessionListRow(
                    row: row,
                    selected: row.id == widget.selectedId,
                    onTap: () => widget.onSelect(row),
                  ),
                ),
          ],
        if (_query.trim().isNotEmpty && rows.isEmpty)
          const Padding(padding: EdgeInsets.all(20), child: Text('没有匹配的会话')),
      ],
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// 按名字、设备 ID 和摘要做大小写不敏感的子串匹配。
  List<SessionRowData> get _filtered {
    final String q = _query.trim();
    if (q.isEmpty) return widget.rows;
    final String lower = q.toLowerCase();
    return <SessionRowData>[
      for (final SessionRowData row in widget.rows)
        if (row.title.toLowerCase().contains(lower) ||
            (row.peerId?.toLowerCase().contains(lower) ?? false) ||
            row.subtitle.toLowerCase().contains(lower))
          row,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    final List<SessionRowData> rows = _filtered;

    return Container(
      key: const ValueKey<String>('shell-list'),
      width: MediaQuery.sizeOf(context).width < 600
          ? double.infinity
          : kSessionListWidth,
      color: tokens.surfaceSunken,
      child: Column(
        children: <Widget>[
          // 标题行
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 8, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(widget.title, style: sectionTitleStyle(tokens)),
                ),
                ...widget.actions,
              ],
            ),
          ),
          // 搜索框
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: SizedBox(
              height: 32 + MediaQuery.textScalerOf(context).scale(20),
              child: AppTextField(
                key: const ValueKey<String>('session-search'),
                controller: _search,
                onChanged: (String value) => setState(() => _query = value),
                style: TextStyle(fontSize: 12.5, color: tokens.fg),
                label: widget.hint,
                placeholder: true,
                leading: Icon(
                  LucideIcons.search,
                  size: 15,
                  color: tokens.fgDim,
                ),
                trailing: _query.isEmpty
                    ? null
                    : AppIconButton(
                        tooltip: '清空搜索',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        icon: Icon(
                          LucideIcons.x,
                          size: 14,
                          color: tokens.fgDim,
                        ),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
          // 列表
          Expanded(
            child: widget.groups != null
                ? _groupedRows(rows, tokens)
                : rows.isEmpty
                ? _ListEmpty(
                    title: widget.emptyTitle,
                    body: widget.emptyBody,
                    searching: _query.trim().isNotEmpty,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    itemCount: rows.length,
                    itemBuilder: (BuildContext context, int index) {
                      final SessionRowData row = rows[index];
                      return SessionListRow(
                        row: row,
                        selected: row.id == widget.selectedId,
                        onTap: () => widget.onSelect(row),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// 一行会话：普通 / hover / 选中 / 按下 四态反馈。
class SessionListRow extends StatefulWidget {
  /// [row] 为投影数据；[selected] 决定底色档位。
  const SessionListRow({
    super.key,
    required this.row,
    required this.selected,
    required this.onTap,
  });

  /// 行数据。
  final SessionRowData row;

  /// 是否选中。
  final bool selected;

  /// 点击回调。
  final VoidCallback onTap;

  @override
  State<SessionListRow> createState() => _SessionListRowState();
}

class _SessionListRowState extends State<SessionListRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    final SessionRowData row = widget.row;
    final RowState state = resolveRowState(
      hovered: _hovered,
      selected: widget.selected,
      pressed: false,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: DecoratedBox(
          decoration: rowDecoration(tokens, state),
          child: Material(
            // Keep selection beneath Miuix hover and keyboard focus feedback.
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(kSessionRowRadius),
            child: MiuixPressable(
              key: ValueKey<String>('session-row-${row.id}'),
              onPressed: widget.onTap,
              borderRadius: BorderRadius.circular(kSessionRowRadius),
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: LanFileMetrics.sessionRowHeight,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: LanFileMetrics.rowPaddingH,
                  vertical: LanFileMetrics.rowPaddingV,
                ),
                child: Row(
                  children: <Widget>[
                    AvatarBadge(
                      peerId: row.avatarSeed,
                      avatarBytes: row.avatarBytes,
                      size: LanFileMetrics.avatarList,
                      showStatus: !row.isGroup && row.online != null,
                      online: row.online ?? true,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: AppTooltip(
                                  message: row.title,
                                  child: Text(
                                    row.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: nameStyle(
                                      tokens,
                                      selected: state == RowState.selected,
                                    ),
                                  ),
                                ),
                              ),
                              if (row.os?.isNotEmpty == true) ...[
                                const SizedBox(width: 6),
                                DevicePlatformLabel(os: row.os!),
                              ],
                              if (row.timeLabel != null) ...<Widget>[
                                const SizedBox(width: 6),
                                Text(row.timeLabel!, style: timeStyle(tokens)),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          if (row.peerId != null)
                            DeviceIdLabel(id: row.peerId!),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  row.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: subtitleStyle(tokens),
                                ),
                              ),
                              if (row.unread > 0) ...<Widget>[
                                const SizedBox(width: 6),
                                UnreadPill(count: row.unread, compact: true),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 列表空态；搜索无结果时文案不同，避免误报「没有数据」。
class _ListEmpty extends StatelessWidget {
  const _ListEmpty({
    required this.title,
    required this.body,
    required this.searching,
  });

  final String title;
  final String body;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              searching ? LucideIcons.searchX : LucideIcons.inbox,
              size: 28,
              color: tokens.fgDim,
            ),
            const SizedBox(height: 8),
            Text(
              searching ? '没有匹配的会话' : title,
              textAlign: TextAlign.center,
              style: emptyTitleStyle(tokens),
            ),
            if (!searching && body.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                body,
                textAlign: TextAlign.center,
                style: emptyBodyStyle(tokens),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 供测试断言：把行的当前态推导暴露出去（避免测试重复实现优先级）。
RowState rowStateOf({
  required bool hovered,
  required bool selected,
  required bool pressed,
}) => resolveRowState(hovered: hovered, selected: selected, pressed: pressed);

/// 鼠标设备类型常量，测试里创建 hover 手势用。
const PointerDeviceKind kMousePointer = PointerDeviceKind.mouse;
