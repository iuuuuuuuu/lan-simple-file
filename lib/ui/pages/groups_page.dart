// SPDX-License-Identifier: GPL-3.0-only

/// 群组：列出会话里 kind=group 的线程，显示群名与未读数。
///
/// 群解散后 archivedAt 非空——此时显示「已解散」而不是把群从列表里删掉：
/// 历史是用户经历过的，删掉等于假装没有过（计划 §6.3 的诚实用语）。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/assembly.dart';
import '../../app/theme/tokens.dart';
import '../../app/widgets/identicon.dart';
import '../../core/contracts/contracts.dart';
import '../widgets/app_toast.dart';
import 'nearby_page.dart' show ServicesNotConnected;

/// 群组数据源。
abstract interface class GroupsSource {
  /// 全部线程（实现方负责只回 group 类型，或由页面过滤）。
  Future<List<ThreadRecord>> listThreads();

  /// groupId → 群记录，用于判定是否已解散。
  Future<GroupRecord?> findGroup(String groupId);
}

/// 由真实服务栈支撑的数据源。
final class ServiceGroupsSource implements GroupsSource {
  /// [store] 提供 thread 与 grp 读能力。
  const ServiceGroupsSource({required this.store});

  /// 存储门面。
  final LanFileStore store;

  @override
  Future<List<ThreadRecord>> listThreads() => store.listThreads();

  @override
  Future<GroupRecord?> findGroup(String groupId) => store.findGroup(groupId);
}

/// 群组页面。
class GroupsPage extends StatefulWidget {
  /// [services] 为 null 时显示「未连接服务」。
  const GroupsPage({
    super.key,
    this.services,
    this.source,
    this.createGroup,
    this.listMembers,
    this.onChanged,
  });

  /// 装配好的服务栈。
  final AppServices? services;

  /// 可注入的数据源。
  final GroupsSource? source;
  final Future<String> Function(String name, List<PeerId> members)? createGroup;
  final Future<List<DeviceRecord>> Function()? listMembers;
  final VoidCallback? onChanged;

  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

/// 一条群会话的展示投影。
final class GroupThreadRow {
  const GroupThreadRow({required this.thread, required this.archived});

  final ThreadRecord thread;
  final bool archived;
}

class _GroupsPageState extends State<GroupsPage> {
  GroupsSource? _source;
  late Future<List<GroupThreadRow>> _future;
  StreamSubscription<List<ThreadRecord>>? _subscription;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _source =
        widget.source ??
        (widget.services == null
            ? null
            : ServiceGroupsSource(store: widget.services!.store));
    _future = _load();
    _subscription = widget.services?.messaging.watchThreads().listen((_) {
      if (mounted) _reload();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    final Future<String> Function(String, List<PeerId>)? create =
        widget.createGroup ?? widget.services?.messaging.createGroup;
    if (create == null || _creating) return;
    setState(() => _creating = true);
    try {
      final List<DeviceRecord> members = widget.listMembers != null
          ? await widget.listMembers!()
          : await widget.services!.store.listDevices();
      if (!mounted) return;
      final ({String name, List<PeerId> members})? request =
          await showCreateGroupDialog(context, members: members);
      if (request == null) return;
      await create(request.name, request.members);
      if (!mounted) return;
      await _reload();
      widget.onChanged?.call();
      if (mounted) AppToast.show(context, '群聊「${request.name}」已创建');
    } on Object catch (error) {
      if (mounted) AppToast.show(context, '创建群聊失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<List<GroupThreadRow>> _load() async {
    final GroupsSource? source = _source;
    if (source == null) return const <GroupThreadRow>[];
    final List<ThreadRecord> threads = await source.listThreads();
    final List<GroupThreadRow> rows = <GroupThreadRow>[];
    for (final ThreadRecord thread in threads) {
      // 契约要求：群会话 threadId = g_ + groupId，kind = 'group'。
      // 两个条件都查，避免把单聊误当群聊（单聊 kind 是 direct）。
      if (thread.kind != 'group') continue;
      final String? groupId = thread.groupId;
      if (groupId == null) continue;
      final GroupRecord? group = await source.findGroup(groupId);
      rows.add(
        GroupThreadRow(thread: thread, archived: group?.isArchived ?? false),
      );
    }
    // 未读多的排前面，其次按最后消息时间。
    rows.sort((GroupThreadRow a, GroupThreadRow b) {
      if (a.thread.unread != b.thread.unread) {
        return b.thread.unread.compareTo(a.thread.unread);
      }
      return b.thread.createdAt.compareTo(a.thread.createdAt);
    });
    return rows;
  }

  Future<void> _reload() async {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    if (_source == null) {
      return const ServicesNotConnected();
    }
    return FutureBuilder<List<GroupThreadRow>>(
      future: _future,
      builder:
          (BuildContext context, AsyncSnapshot<List<GroupThreadRow>> snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    '加载群组失败：${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: tokens.fgDim),
                  ),
                ),
              );
            }
            final List<GroupThreadRow> rows =
                snapshot.data ?? const <GroupThreadRow>[];
            return Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Row(
                    children: <Widget>[
                      Text(
                        '群聊',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: tokens.fg,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '共 ${rows.length} 个',
                        style: TextStyle(fontSize: 12, color: tokens.fgDim),
                      ),
                      const Spacer(),
                      if (widget.createGroup != null || widget.services != null)
                        TextButton.icon(
                          key: const ValueKey<String>('create-group'),
                          onPressed: _creating ? null : _create,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('新建群聊'),
                        ),
                      IconButton(
                        tooltip: '刷新',
                        icon: Icon(
                          Icons.refresh,
                          size: 18,
                          color: tokens.fgDim,
                        ),
                        onPressed: _reload,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: rows.isEmpty
                      ? _EmptyGroups()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                          itemCount: rows.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (BuildContext context, int index) =>
                              GroupRowView(row: rows[index]),
                        ),
                ),
              ],
            );
          },
    );
  }
}

Future<({String name, List<PeerId> members})?> showCreateGroupDialog(
  BuildContext context, {
  required List<DeviceRecord> members,
}) => showDialog<({String name, List<PeerId> members})>(
  context: context,
  builder: (_) => _CreateGroupDialog(
    members: [
      for (final device in members)
        if (!device.isSelf && !device.isGuest) device,
    ],
  ),
);

class _CreateGroupDialog extends StatefulWidget {
  const _CreateGroupDialog({required this.members});
  final List<DeviceRecord> members;
  @override
  State<_CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<_CreateGroupDialog> {
  final TextEditingController _name = TextEditingController();
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final Set<PeerId> _selected = <PeerId>{};
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _create() {
    if (_form.currentState!.validate()) {
      Navigator.of(context)
          .pop((name: _name.text.trim(), members: _selected.toList()));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('新建群聊'),
    content: SizedBox(
      width: 400,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextFormField(
              key: const ValueKey<String>('group-name-field'),
              controller: _name,
              autofocus: true,
              maxLength: 64,
              decoration: const InputDecoration(labelText: '群聊名称'),
              validator: (String? raw) {
                final String value = raw?.trim() ?? '';
                if (value.isEmpty) return '请输入群聊名称';
                if (value.runes.length > 64) return '最多 64 个字符';
                if (value.codeUnits.any((int c) => c < 32 || c == 127)) {
                  return '名称不能包含控制字符';
                }
                return null;
              },
              onFieldSubmitted: (_) => _create(),
            ),
            const SizedBox(height: 12),
            const Text('选择成员'),
            const SizedBox(height: 8),
            if (widget.members.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('暂未发现其他人，可以先创建群聊。'),
              )
            else
              SizedBox(
                height: widget.members.length < 5
                    ? widget.members.length * 56.0
                    : 280,
                child: ListView(
                  children: <Widget>[
                    for (final DeviceRecord member in widget.members)
                      CheckboxListTile(
                        key: ValueKey<String>(
                          'group-member-${member.peerId.value}',
                        ),
                        value: _selected.contains(member.peerId),
                        title: Text(
                          member.name.isEmpty
                              ? member.peerId.value
                              : member.name,
                        ),
                        subtitle: Text(member.online ? '在线' : '离线'),
                        onChanged: (bool? checked) => setState(() {
                          if (checked == true) {
                            _selected.add(member.peerId);
                          } else {
                            _selected.remove(member.peerId);
                          }
                        }),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _create, child: const Text('创建')),
    ],
  );
}

/// 一条群会话。
class GroupRowView extends StatelessWidget {
  /// 展示一条群会话。
  const GroupRowView({super.key, required this.row});

  /// 展示数据。
  final GroupThreadRow row;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    final ThreadRecord thread = row.thread;
    final String title = thread.title.isEmpty
        ? thread.groupId ?? '未命名群'
        : thread.title;
    // 已解散的群降透明度（不换色相），并显式标注状态。
    return Opacity(
      opacity: row.archived ? 0.55 : 1.0,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: <Widget>[
              Identicon(peerId: thread.groupId ?? thread.id, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: tokens.fg,
                            ),
                          ),
                        ),
                        if (row.archived) ...<Widget>[
                          const SizedBox(width: 8),
                          Text(
                            '已解散',
                            style: TextStyle(fontSize: 11, color: tokens.fgDim),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      thread.lastMsgPreview == null ||
                              thread.lastMsgPreview!.isEmpty
                          ? '还没有消息'
                          : thread.lastMsgPreview!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: tokens.fgDim),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              UnreadBadge(count: thread.unread),
            ],
          ),
        ),
      ),
    );
  }
}

/// 未读数徽标；0 时完全不占位。
class UnreadBadge extends StatelessWidget {
  /// 未读条数。
  const UnreadBadge({super.key, required this.count});

  /// 未读数量。
  final int count;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.accent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: tokens.onAccent,
        ),
      ),
    );
  }
}

/// 空状态。
class _EmptyGroups extends StatelessWidget {
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
              Icon(Icons.groups_outlined, size: 40, color: tokens.fgDim),
              const SizedBox(height: 16),
              Text(
                '还没有群组',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: tokens.fg,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '群聊用来和固定的几个人共享文件与消息。\n'
                '建群后，群文件历史会按人与时间自动归档。',
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
