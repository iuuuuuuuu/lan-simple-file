// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/contracts/contracts.dart';
import '../../core/net/peer_share_catalog.dart';
import 'app_controls.dart';
import 'app_toast.dart';
import 'avatar_badge.dart';
import 'share_detail_panel.dart' show humanSize;

class PeerSharesDialog extends StatefulWidget {
  const PeerSharesDialog({
    super.key,
    required this.peer,
    required this.name,
    required this.loadCatalog,
    required this.browse,
    required this.homeLink,
    required this.shareLink,
    required this.openLink,
    this.avatarBytes,
    this.onFileOpened,
  });

  final PeerId peer;
  final String name;
  final Uint8List? avatarBytes;
  final Future<PeerShareCatalog> Function() loadCatalog;
  final Future<FileEntryPage> Function(ShareId, {ItemKey? path, String? cursor})
  browse;
  final Future<Uri> Function() homeLink;
  final Future<Uri> Function(ShareId) shareLink;
  final Future<void> Function(Uri) openLink;
  final Future<void> Function(ShareId, FileEntry)? onFileOpened;

  @override
  State<PeerSharesDialog> createState() => _PeerSharesDialogState();
}

class _PeerSharesDialogState extends State<PeerSharesDialog> {
  PeerShareCatalog? _catalog;
  PeerShareEntry? _share;
  final _trail = <({ItemKey key, String name})>[];
  final _entries = <FileEntry>[];
  String? _cursor;
  String? _error;
  String _query = '';
  String? _collection;
  bool _loading = true;
  bool _copying = false;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool append = false}) async {
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _error = null;
      if (!append) {
        _entries.clear();
        _cursor = null;
      }
    });
    try {
      if (_share == null) {
        final catalog = await widget.loadCatalog();
        if (!mounted || revision != _revision) return;
        setState(() {
          _catalog = catalog;
          if (_collection != null && !catalog.groups.containsKey(_collection)) {
            _collection = null;
          }
        });
      } else {
        final page = await widget.browse(
          _share!.id!,
          path: _trail.lastOrNull?.key,
          cursor: append ? _cursor : null,
        );
        if (!mounted || revision != _revision) return;
        setState(() {
          _entries.addAll(page.entries);
          _entries.sort(
            (a, b) => a.isDirectory == b.isDirectory
                ? a.itemKey.value.compareTo(b.itemKey.value)
                : a.isDirectory
                ? -1
                : 1,
          );
          _cursor = page.nextCursor;
        });
      }
    } on Object catch (error) {
      if (!mounted || revision != _revision) return;
      setState(
        () => _error = error is LanFileException ? error.message : '读取失败，请稍后重试',
      );
    } finally {
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  void _back() {
    setState(() {
      if (_trail.isNotEmpty) {
        _trail.removeLast();
      } else {
        _share = null;
      }
    });
    _load();
  }

  Future<void> _link({FileEntry? file, bool copy = false}) async {
    setState(() => _copying = true);
    final share = _share;
    try {
      var link = share == null
          ? await widget.homeLink()
          : await widget.shareLink(share.id!);
      if (share == null && _collection != null) {
        link = link.replace(
          queryParameters: {...link.queryParameters, 'group': _collection!},
        );
      }
      if (file != null) {
        link = link.replace(
          pathSegments: [
            's',
            share!.id!.value,
            'f',
            ...file.itemKey.value.split('/'),
          ],
        );
      }
      if (copy) {
        await Clipboard.setData(ClipboardData(text: link.toString()));
        if (mounted) {
          AppToast.show(context, file == null ? '网页链接已复制' : '下载链接已复制');
        }
      } else {
        await widget.openLink(link);
        if (file != null) {
          try {
            await widget.onFileOpened?.call(share!.id!, file);
          } on Object {
            if (mounted) {
              AppToast.show(context, '文件已打开，但保存传输记录失败', isError: true);
            }
          }
        }
      }
    } on Object catch (error) {
      if (mounted) {
        setState(
          () =>
              _error = error is LanFileException ? error.message : '打开链接失败，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  String _accessLabel(String access) => switch (access) {
    'password' => '需要密码',
    'group' => '仅群成员可见',
    'private' => '私密分享',
    _ => '需要访问授权',
  };

  @override
  Widget build(BuildContext context) {
    final shares = (_catalog?.shares ?? const <PeerShareEntry>[])
        .where(
          (s) =>
              s.name.toLowerCase().contains(_query.toLowerCase()) &&
              (_collection == null || s.collectionId == _collection),
        )
        .toList();
    if (_catalog?.ownerOrder != true) {
      shares.sort(
        (a, b) => a.isDirectory == b.isDirectory
            ? a.name.compareTo(b.name)
            : a.isDirectory
            ? -1
            : 1,
      );
    }
    return PopScope(
      canPop: _share == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: AppDialog(
        key: const ValueKey('peer-shares-dialog'),
        maxWidth: 680,
        title: Row(
          children: [
            AvatarBadge(
              peerId: widget.peer.value,
              avatarBytes: widget.avatarBytes,
              size: 36,
              showStatus: false,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${_catalog?.name ?? widget.name}的分享',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            AppIconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        actions: [
          AppButton.icon(
            onPressed: _copying ? null : _link,
            icon: const Icon(Icons.open_in_browser, size: 18),
            label: const Text('在浏览器打开'),
          ),
        ],
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(
              'ID: ${widget.peer.value}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (_share != null)
                  AppIconButton(
                    key: const ValueKey('peer-shares-back'),
                    tooltip: '返回上一级',
                    onPressed: _back,
                    icon: const Icon(Icons.arrow_back),
                  ),
                Expanded(
                  child: Text(
                    _share == null
                        ? '全部分享 (${_catalog?.shares.length ?? 0})'
                        : _trail.lastOrNull?.name ?? _share!.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                AppIconButton(
                  tooltip: '刷新分享',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
                AppIconButton(
                  tooltip: '复制网页链接',
                  onPressed: _copying ? null : () => _link(copy: true),
                  icon: const Icon(Icons.link),
                ),
              ],
            ),
            if (_share == null)
              if (_catalog?.groups.isNotEmpty == true)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _collection == null
                            ? '全部分组'
                            : _catalog!.groups[_collection]!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    AppMenuButton<String>(
                      tooltip: '筛选对方分享分组',
                      icon: const Icon(Icons.filter_list),
                      itemBuilder: (_) => [
                        const AppMenuItem(value: '*', label: '全部分组'),
                        for (final group in _catalog!.groups.entries)
                          AppMenuItem(value: group.key, label: group.value),
                      ],
                      onSelected: (id) =>
                          setState(() => _collection = id == '*' ? null : id),
                    ),
                  ],
                ),
            if (_share == null)
              AppTextField(
                key: const ValueKey('peer-shares-search'),
                label: '搜索分享',
                placeholder: true,
                onChanged: (value) => setState(() => _query = value),
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: MiuixCircularProgressIndicator()),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Text(_error!),
                    AppButton(
                      onPressed: _loading
                          ? null
                          : () => _load(append: _entries.isNotEmpty),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            if (!_loading &&
                _error == null &&
                (_share == null ? shares.isEmpty : _entries.isEmpty))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    _share != null
                        ? '这个目录为空'
                        : _query.isNotEmpty
                        ? '没有匹配的分享'
                        : '暂无公开分享',
                  ),
                ),
              ),
            if (_share == null)
              for (final share in shares)
                AppListTile(
                  leading: Icon(
                    share.isDirectory
                        ? Icons.folder_outlined
                        : Icons.insert_drive_file_outlined,
                  ),
                  title: Text(
                    share.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    share.id == null
                        ? _accessLabel(share.access)
                        : share.isDirectory
                        ? '${_catalog?.groups[share.collectionId] ?? '未分组'} · 文件夹'
                        : '${_catalog?.groups[share.collectionId] ?? '未分组'} · 文件',
                  ),
                  trailing: Icon(
                    share.id == null ? Icons.lock_outline : Icons.chevron_right,
                  ),
                  onTap: share.id == null
                      ? null
                      : () {
                          setState(() {
                            _share = share;
                            _trail.clear();
                          });
                          _load();
                        },
                )
            else
              for (final entry in _entries)
                AppListTile(
                  leading: Icon(
                    entry.isDirectory
                        ? Icons.folder_outlined
                        : Icons.insert_drive_file_outlined,
                  ),
                  title: Text(
                    entry.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    entry.isDirectory ? '文件夹' : humanSize(entry.size),
                  ),
                  trailing: entry.isDirectory
                      ? const Icon(Icons.chevron_right)
                      : AppIconButton(
                          tooltip: '复制下载链接',
                          onPressed: _copying
                              ? null
                              : () => _link(file: entry, copy: true),
                          icon: const Icon(Icons.content_copy),
                        ),
                  onTap: entry.isDirectory
                      ? () {
                          setState(
                            () => _trail.add((
                              key: entry.itemKey,
                              name: entry.name,
                            )),
                          );
                          _load();
                        }
                      : _copying
                      ? null
                      : () => _link(file: entry),
                ),
            if (_cursor != null)
              AppButton(
                onPressed: _loading ? null : () => _load(append: true),
                child: const Text('加载更多'),
              ),
          ],
        ),
      ),
    );
  }
}
