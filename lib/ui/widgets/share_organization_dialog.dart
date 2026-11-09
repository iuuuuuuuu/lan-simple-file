// SPDX-License-Identifier: GPL-3.0-only

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/contracts/contracts.dart';
import '../../core/shares/share_organization.dart';
import 'app_controls.dart';
import 'edit_name_dialog.dart';

class ShareOrganizationDialog extends StatefulWidget {
  const ShareOrganizationDialog({
    super.key,
    required this.initial,
    required this.shares,
    required this.source,
    this.group,
  });

  final ShareOrganization initial;
  final List<ShareRecord> shares;
  final ShareOrganizationSource source;
  final String? group;

  @override
  State<ShareOrganizationDialog> createState() =>
      _ShareOrganizationDialogState();
}

class _ShareOrganizationDialogState extends State<ShareOrganizationDialog> {
  late ShareOrganization _layout = widget.initial;
  late String? _group = widget.group;
  final Set<String> _selected = {};
  int _tab = 0;
  bool _saving = false;
  String? _error;

  String _name(String id) => _layout.names[id] ?? '未分组';

  Future<void> _editGroup([String? id]) async {
    final name = await showAppDialog<String>(
      context: context,
      builder: (_) => EditNameDialog(
        title: id == null ? '新建分享分组' : '重命名分组',
        label: '分组名称',
        initialValue: id == null ? '' : _name(id),
        maxLength: 40,
        fieldKey: const ValueKey('share-group-name'),
      ),
    );
    if (name == null || !mounted) return;
    if (_layout.names.entries.any(
      (entry) =>
          entry.key != id && entry.value.toLowerCase() == name.toLowerCase(),
    )) {
      setState(() => _error = '已存在同名分组');
      return;
    }
    final random = Random.secure();
    final key =
        id ??
        'c_${List.generate(12, (_) => random.nextInt(16).toRadixString(16)).join()}';
    setState(() {
      _layout = _layout.copyWith(names: {..._layout.names, key: name});
      _error = null;
    });
  }

  Future<void> _deleteGroup(String id) async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: const Text('删除这个分组？'),
        content: Text('“${_name(id)}”中的分享会移回未分组，文件和分享链接保留。'),
        actions: [
          AppButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          AppButton.primary(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除分组'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _layout = _layout.removeGroup(id);
      if (_group == id) _group = '';
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.source.save(_layout);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = '保存失败：$error';
          _saving = false;
        });
      }
    }
  }

  void _reorderGroups(int oldIndex, int newIndex) {
    final groups = _layout.groups;
    groups.insert(newIndex, groups.removeAt(oldIndex));
    setState(() => _layout = _layout.copyWith(groupOrder: groups));
  }

  void _reorderShares(List<ShareRecord> visible, int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final targetGroup = _layout.groupOf(visible[newIndex].id.value);
    final ids = visible.map((s) => s.id.value).toList();
    final moved = ids.removeAt(oldIndex);
    ids.insert(newIndex, moved);
    setState(() {
      if (_group == null) _layout = _layout.move([moved], targetGroup);
      _layout = _layout.copyWith(
        order: [...ids, ..._layout.order.where((id) => !ids.contains(id))],
      );
    });
  }

  Widget _handle(int index, String id) => ReorderableDragStartListener(
    key: ValueKey('share-order-handle-$id'),
    index: index,
    child: const AppTooltip(
      message: '拖动排序',
      child: Padding(
        padding: EdgeInsets.all(10),
        child: Icon(LucideIcons.gripHorizontal),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final shares = _layout.arrange(widget.shares, group: _group);
    final groups = _layout.groups;
    return PopScope(
      canPop: !_saving,
      child: AppDialog(
        maxWidth: 660,
        title: const Text('分组与排序'),
        content: SizedBox(
          width: 580,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MiuixTabRow(
                tabs: const ['分享', '分组'],
                selectedTabIndex: _tab,
                onTabSelected: (value) {
                  if (!_saving) setState(() => _tab = value);
                },
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _tab == 1
                          ? '${_layout.names.length} 个分组'
                          : _group == null
                          ? '全部分享'
                          : _name(_group!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_tab == 0) ...[
                    AppMenuButton<String>(
                      tooltip: '选择分享分组',
                      icon: const Icon(LucideIcons.listFilter),
                      enabled: !_saving,
                      itemBuilder: (_) => [
                        const AppMenuItem(value: '*', label: '全部分享'),
                        for (final id in groups)
                          AppMenuItem(value: id, label: _name(id)),
                      ],
                      onSelected: (id) => setState(() {
                        _group = id == '*' ? null : id;
                        _selected.clear();
                      }),
                    ),
                    AppMenuButton<String>(
                      tooltip: '移动所选分享',
                      icon: const Icon(LucideIcons.folderInput),
                      enabled: !_saving && _selected.isNotEmpty,
                      itemBuilder: (_) => [
                        for (final id in groups)
                          AppMenuItem(value: id, label: _name(id)),
                      ],
                      onSelected: (id) => setState(() {
                        _layout = _layout.move(_selected, id);
                        _selected.clear();
                      }),
                    ),
                    AppIconButton(
                      tooltip: '恢复文件夹优先排序',
                      onPressed: _saving
                          ? null
                          : () => setState(
                              () => _layout = _layout.copyWith(order: []),
                            ),
                      icon: const Icon(LucideIcons.arrowDownAZ),
                    ),
                  ],
                  AppIconButton(
                    tooltip: '新建分享分组',
                    onPressed: _saving ? null : _editGroup,
                    icon: const Icon(LucideIcons.folderPlus),
                  ),
                ],
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              SizedBox(
                height: min(320, MediaQuery.sizeOf(context).height * .32),
                child: AbsorbPointer(
                  absorbing: _saving,
                  child: ReorderableListView.builder(
                    key: ValueKey('share-organization-list-$_tab'),
                    buildDefaultDragHandles: false,
                    proxyDecorator: (child, index, animation) =>
                        MiuixCard(insideMargin: EdgeInsets.zero, child: child),
                    itemCount: _tab == 1 ? groups.length : shares.length,
                    onReorderItem: _tab == 1
                        ? _reorderGroups
                        : (oldIndex, newIndex) =>
                              _reorderShares(shares, oldIndex, newIndex),
                    itemBuilder: (context, index) {
                      if (_tab == 1) {
                        final id = groups[index];
                        return Row(
                          key: ValueKey('order-group-$id'),
                          children: [
                            _handle(index, 'group-$id'),
                            Expanded(
                              child: Text(
                                _name(id),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${widget.shares.where((s) => _layout.groupOf(s.id.value) == id).length}',
                            ),
                            AppMenuButton<String>(
                              tooltip: '管理分组 ${_name(id)}',
                              enabled: id.isNotEmpty,
                              onSelected: (action) => action == 'rename'
                                  ? _editGroup(id)
                                  : _deleteGroup(id),
                              itemBuilder: (_) => const [
                                AppMenuItem(value: 'rename', label: '重命名分组'),
                                AppMenuItem(value: 'delete', label: '删除分组'),
                              ],
                            ),
                          ],
                        );
                      }
                      final share = shares[index];
                      final id = share.id.value;
                      return Row(
                        key: ValueKey('order-share-$id'),
                        children: [
                          MiuixCheckbox(
                            key: ValueKey('select-share-$id'),
                            value: _selected.contains(id),
                            onChanged: (value) => setState(() {
                              if (value == true) {
                                _selected.add(id);
                              } else {
                                _selected.remove(id);
                              }
                            }),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            share.kind == 'folder'
                                ? LucideIcons.folder
                                : LucideIcons.file,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    share.displayName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    _name(_layout.groupOf(id)),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          _handle(index, id),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          AppButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          AppButton.primary(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中' : '保存'),
          ),
        ],
      ),
    );
  }
}
