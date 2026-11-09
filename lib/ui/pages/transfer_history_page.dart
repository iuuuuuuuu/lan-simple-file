// SPDX-License-Identifier: GPL-3.0-only

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/assembly.dart';
import '../../core/contracts/contracts.dart';
import '../../core/platform/reveal_in_file_manager.dart';
import '../../core/transfer/transfer_history.dart';
import '../widgets/app_controls.dart';
import '../widgets/app_toast.dart';
import '../widgets/share_detail_panel.dart' show humanSize;

class TransferHistoryPage extends StatefulWidget {
  const TransferHistoryPage({super.key, this.services, this.source});
  final AppServices? services;
  final TransferHistorySource? source;
  @override
  State<TransferHistoryPage> createState() => _TransferHistoryPageState();
}

class _TransferHistoryPageState extends State<TransferHistoryPage> {
  late final TransferHistorySource? _source =
      widget.source ?? widget.services?.transferHistory;
  late Future<List<TransferHistoryEntry>> _future;
  StreamSubscription<void>? _changes;
  StreamSubscription<TransferProgress>? _transfers;
  Timer? _debounce;
  final Set<String> _selected = {};
  String _query = '';
  int _tab = 0;
  bool _selecting = false, _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _changes = _source?.changes.listen((_) => _scheduleReload());
    _transfers = widget.services?.remoteFiles.watchAll().listen(
      (_) => _scheduleReload(),
      onError: (Object _) {},
    );
  }

  Future<List<TransferHistoryEntry>> _load() async =>
      await _source?.list() ?? [];
  void _scheduleReload() {
    _debounce ??= Timer(const Duration(milliseconds: 200), () {
      _debounce = null;
      if (mounted) _reload();
    });
  }

  void _reload() => setState(() {
    _future = _load();
  });
  @override
  void dispose() {
    _changes?.cancel();
    _transfers?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  String _status(TransferHistoryEntry entry) => switch (entry.status) {
    'external' => '已交给外部应用',
    'partial' => '已发送部分内容',
    'sent' => '已发送',
    'done' => '已完成',
    'failed' => '失败',
    'active' => '进行中',
    'pending' => '等待中',
    'paused' => '已暂停',
    _ => entry.status,
  };

  Future<void> _remove(Set<String> ids) async {
    if (ids.isEmpty || _source == null) return;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: Text('删除 ${ids.length} 条传输记录？'),
        content: const Text('只删除记录，保留文件。正在进行的传输不受影响。'),
        actions: [
          AppButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          AppButton.primary(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除记录'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _source.remove(ids);
      if (mounted) {
        _selected.removeAll(ids);
        _reload();
      }
    } on Object catch (error) {
      if (mounted) AppToast.show(context, '删除失败：$error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _action(TransferHistoryEntry entry, String action) async {
    if (action == 'remove') {
      await _remove({entry.id});
      return;
    }
    try {
      if (action == 'location' || action == 'open') {
        final path = entry.localPath!;
        if (!await File(path).exists()) throw StateError('文件已移动或删除');
        if (action == 'location') {
          final error = await revealInFileManager(path);
          if (error != null) throw StateError(error);
        } else if (!await launchUrl(
          Uri.file(path),
          mode: LaunchMode.externalApplication,
        )) {
          throw StateError('没有可打开此文件的应用');
        }
      } else {
        final services = widget.services!;
        var uri = await services.buildPeerWebLink(
          entry.peer ?? services.identity.peerId,
          entry.share!,
        );
        if (entry.archive) {
          uri = uri.replace(
            pathSegments: ['s', entry.share!.value, 'zip'],
            queryParameters: {
              ...uri.queryParameters,
              if (entry.item != null) 'path': entry.item!.value,
            },
          );
        } else if (entry.item != null) {
          uri = uri.replace(
            pathSegments: [
              's',
              entry.share!.value,
              'f',
              ...entry.item!.value.split('/'),
            ],
          );
        }
        await Clipboard.setData(ClipboardData(text: uri.toString()));
        if (mounted) AppToast.show(context, '文件链接已复制');
      }
    } on Object catch (error) {
      if (mounted) AppToast.show(context, '操作失败：$error', isError: true);
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<TransferHistoryEntry>>(
    future: _future,
    builder: (context, snapshot) {
      final query = _query.trim().toLowerCase();
      final entries = (snapshot.data ?? [])
          .where(
            (entry) =>
                '${entry.name} ${entry.peerLabel} ${entry.peer?.value ?? ''}'
                    .toLowerCase()
                    .contains(query) &&
                (_tab == 0 ||
                    (_tab == 1
                        ? entry.direction == TransferDirection.download
                        : entry.direction == TransferDirection.upload)),
          )
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '传输记录',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                ),
                AppIconButton(
                  tooltip: _selecting ? '结束管理' : '管理记录',
                  selected: _selecting,
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _selecting = !_selecting;
                          _selected.clear();
                        }),
                  icon: Icon(
                    _selecting ? LucideIcons.check : LucideIcons.listChecks,
                  ),
                ),
                AppIconButton(
                  tooltip: '刷新记录',
                  onPressed: _busy ? null : _reload,
                  icon: const Icon(LucideIcons.refreshCw),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: AppTextField(
              key: const ValueKey('transfer-history-search'),
              label: '搜索文件名或来源',
              placeholder: true,
              leading: const Icon(LucideIcons.search),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: MiuixTabRow(
              tabs: const ['全部', '接收', '发送'],
              selectedTabIndex: _tab,
              onTabSelected: (index) => setState(() => _tab = index),
            ),
          ),
          if (_selecting)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  MiuixCheckbox(
                    value:
                        entries.isNotEmpty &&
                        entries.every((e) => _selected.contains(e.id)),
                    onChanged: _busy
                        ? null
                        : (checked) => setState(() {
                            if (checked == true) {
                              _selected.addAll(entries.map((e) => e.id));
                            } else {
                              _selected.removeAll(entries.map((e) => e.id));
                            }
                          }),
                  ),
                  Expanded(child: Text('已选 ${_selected.length} 项')),
                  AppIconButton(
                    tooltip: '删除所选记录',
                    onPressed: _busy || _selected.isEmpty
                        ? null
                        : () => _remove({..._selected}),
                    icon: const Icon(LucideIcons.trash2),
                  ),
                ],
              ),
            ),
          Expanded(
            child: snapshot.hasError
                ? Center(child: Text('读取传输记录失败：${snapshot.error}'))
                : snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData
                ? const Center(child: MiuixCircularProgressIndicator())
                : entries.isEmpty
                ? Center(child: Text(query.isEmpty ? '暂无传输记录' : '没有匹配的记录'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final date = entry.createdAt.toLocal();
                      return AppListTile(
                        key: ValueKey('transfer-history-${entry.id}'),
                        leading: _selecting
                            ? MiuixCheckbox(
                                value: _selected.contains(entry.id),
                                onChanged: _busy
                                    ? null
                                    : (checked) => setState(() {
                                        if (checked == true) {
                                          _selected.add(entry.id);
                                        } else {
                                          _selected.remove(entry.id);
                                        }
                                      }),
                              )
                            : Icon(
                                entry.direction == TransferDirection.upload
                                    ? LucideIcons.arrowUpRight
                                    : LucideIcons.arrowDownLeft,
                              ),
                        title: Text(
                          entry.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${_status(entry)}${entry.bytes == null ? '' : ' · ${humanSize(entry.bytes)}'}\n${entry.peerLabel}\n${date.year}/${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: AppMenuButton<String>(
                          tooltip: '管理文件 ${entry.name}',
                          enabled: !_busy,
                          itemBuilder: (_) => [
                            if (entry.localPath != null)
                              const AppMenuItem(value: 'open', label: '打开文件'),
                            if (entry.localPath != null && Platform.isWindows)
                              const AppMenuItem(
                                value: 'location',
                                label: '打开文件位置',
                              ),
                            if (entry.share != null && widget.services != null)
                              const AppMenuItem(value: 'link', label: '复制文件链接'),
                            const AppMenuItem(value: 'remove', label: '删除记录'),
                          ],
                          onSelected: (action) => _action(entry, action),
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    },
  );
}
