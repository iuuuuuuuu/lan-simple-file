// SPDX-License-Identifier: GPL-3.0-only

/// 分享详情面板：展开一条分享，按页浏览它内部的目录与文件。
///
/// 用 [BrowseSource] 而不是直接抓 ShareService：页面只依赖这个窄接口，
/// 测试就能喂任意目录树来验证「下钻 / 空目录 / 已失效 / 下载入口」，
/// 不必真的建库、建目录、起扫描。生产侧由 [ServiceBrowseSource] 接到真实服务。
///
/// 全部取色走 LanFileTokens / LanFileTokensLayers，尺寸走 LanFileMetrics，
/// 不引入第二色相。
library;

import 'package:flutter/material.dart';

import 'app_controls.dart';

import '../../app/theme/tokens.dart';
import '../../core/contracts/contracts.dart';

/// 一页浏览结果。
final class BrowsePage {
  /// 构造一页。
  const BrowsePage({required this.entries, this.nextCursor});

  /// 本页条目。
  final List<TreeEntryView> entries;

  /// 下一页游标；null 表示没有更多。
  final String? nextCursor;

  /// 是否还有下一页。
  bool get hasMore => nextCursor != null;
}

/// 浏览数据源。
abstract interface class BrowseSource {
  /// 列出一页。
  ///
  /// [path] 为 null 时列分享根；[cursor] 为 null 时从第一页开始。
  Future<BrowsePage> browse(
    ShareId id, {
    ItemKey? path,
    String? cursor,
    required int limit,
  });
}

/// 由真实 [ShareService] 支撑的数据源。
final class ServiceBrowseSource implements BrowseSource {
  /// 直接委托契约服务，不做缓存。
  const ServiceBrowseSource(this.service);

  /// 共享服务。
  final ShareService service;

  @override
  Future<BrowsePage> browse(
    ShareId id, {
    ItemKey? path,
    String? cursor,
    required int limit,
  }) async {
    final ({List<TreeEntryView> entries, String? nextCursor}) page =
        await service.browse(id, path: path, cursor: cursor, limit: limit);
    return BrowsePage(entries: page.entries, nextCursor: page.nextCursor);
  }
}

/// 字节数转人话。
String humanSize(int? bytes) {
  if (bytes == null) return '未知大小';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// 展开后的分享详情：面包屑 + 条目列表 + 分页。
class ShareDetailPanel extends StatefulWidget {
  /// [onDownload] 只暴露回调，实际下载由调用方接 TransferService。
  const ShareDetailPanel({
    super.key,
    required this.share,
    required this.source,
    this.onDownload,
    this.onReveal,
    this.pageSize = LanFileConstants.treePageSize,
    this.now,
  });

  /// 要展开的分享。
  final ShareRecord share;

  /// 浏览数据源。
  final BrowseSource source;

  /// 文件下载入口；为 null 时文件行不显示下载按钮。
  final void Function(TreeEntryView entry)? onDownload;

  /// 「打开文件所在位置」入口；为 null 时不显示该按钮。
  ///
  /// 存在的理由：用户要在系统文件管理器里定位原文件，
  /// 这属于平台能力（调用 explorer / open / xdg-open），由装配层注入。
  final void Function(TreeEntryView entry)? onReveal;

  /// 每页条数。
  final int pageSize;

  /// 判定状态用的时间。
  final DateTime? now;

  @override
  State<ShareDetailPanel> createState() => _ShareDetailPanelState();
}

class _ShareDetailPanelState extends State<ShareDetailPanel> {
  /// 当前路径（相对分享根）；空表示根。
  ItemKey? _path;
  final List<ItemKey?> _parents = [];

  /// 已加载的条目。
  final List<TreeEntryView> _entries = <TreeEntryView>[];

  /// 下一页游标。
  String? _cursor;

  /// 是否已至少加载过一页（用于区分「加载中」与「真空」）。
  bool _loaded = false;

  /// 是否正在加载。
  bool _loading = false;

  /// 加载错误文案。
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  /// 加载一页。[reset] 为真时清空并从 [path] 的第一页开始。
  Future<void> _load({required bool reset}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      if (reset) {
        _entries.clear();
        _cursor = null;
        _loaded = false;
        _error = null;
      }
    });
    try {
      final BrowsePage page = await widget.source.browse(
        widget.share.id,
        path: _path,
        cursor: reset ? null : _cursor,
        limit: widget.pageSize,
      );
      if (!mounted) return;
      setState(() {
        _entries.addAll(page.entries);
        _cursor = page.nextCursor;
        _loaded = true;
        _loading = false;
      });
    } on LanFileException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loaded = true;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loaded = true;
        _loading = false;
      });
    }
  }

  /// 下钻到某个子目录。
  Future<void> _enter(ItemKey key) async {
    if (_loading) return;
    setState(() {
      _parents.add(_path);
      _path = key;
    });
    await _load(reset: true);
  }

  /// 返回上一级。
  Future<void> _up() async {
    if (_loading || _parents.isEmpty) return;
    setState(() {
      _path = _parents.removeLast();
    });
    await _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    // 源已失效：给明确文案，而不是空白列表。
    if (widget.share.missing) {
      return _Hint(
        icon: Icons.link_off,
        title: '已失效，无法浏览',
        body:
            '这条分享的源文件在提供者侧被移动或删除了。'
            '请用「重新定位」指向新位置后再试。',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Breadcrumb(
          rootName: widget.share.displayName,
          path: _path,
          onRoot: _path == null || _loading ? null : _up,
        ),
        const AppDivider(height: LanFileMetrics.hairline),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(LanFileMetrics.rowPaddingH),
            child: Text(
              '读取失败：$_error',
              style: TextStyle(fontSize: 12, color: tokens.fgDim),
            ),
          )
        else if (!_loaded)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: MiuixCircularProgressIndicator()),
          )
        else if (_entries.isEmpty)
          _Hint(
            icon: Icons.folder_open_outlined,
            title: '这个文件夹是空的',
            body: _path == null ? '分享根下没有可见的文件或子目录。' : '该目录下没有可见的文件或子目录。',
          )
        else ...<Widget>[
          for (final TreeEntryView entry in _entries)
            _EntryRow(
              entry: entry,
              onTap: entry.isDirectory ? () => _enter(entry.itemKey) : null,
              onDownload: entry.isDirectory ? null : widget.onDownload,
              onReveal: widget.onReveal,
            ),
          if (_cursor != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: AppButton(
                  onPressed: _loading ? null : () => _load(reset: false),
                  child: Text(_loading ? '加载中…' : '加载更多'),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// 面包屑：分享名 > 子目录 > ...；点可回上级。
class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({
    required this.rootName,
    required this.path,
    required this.onRoot,
  });

  final String rootName;
  final ItemKey? path;
  final VoidCallback? onRoot;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    final String? current = path?.value;
    final List<String> segments = current == null || current.isEmpty
        ? const <String>[]
        : current.split('/');
    final String suffix = segments.isEmpty ? '' : ' / ${segments.join(' / ')}';
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LanFileMetrics.rowPaddingH,
        vertical: 6,
      ),
      child: Row(
        children: <Widget>[
          if (segments.isNotEmpty)
            AppIconButton(
              tooltip: '返回上一级',
              icon: Icon(Icons.arrow_upward, size: 16, color: tokens.fgDim),
              onPressed: onRoot,
            ),
          Flexible(
            child: Text(
              '[$rootName]$suffix',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: tokens.fgDim),
            ),
          ),
        ],
      ),
    );
  }
}

/// 一行条目：目录可点进入，文件给下载 + 定位入口。
class _EntryRow extends StatefulWidget {
  const _EntryRow({
    required this.entry,
    required this.onTap,
    required this.onDownload,
    required this.onReveal,
  });

  final TreeEntryView entry;
  final VoidCallback? onTap;
  final void Function(TreeEntryView entry)? onDownload;
  final void Function(TreeEntryView entry)? onReveal;

  @override
  State<_EntryRow> createState() => _EntryRowState();
}

class _EntryRowState extends State<_EntryRow> {
  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    final TreeEntryView e = widget.entry;

    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LanFileMetrics.rowPaddingH,
        vertical: 6,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            e.isDirectory ? Icons.folder_outlined : Icons.description_outlined,
            size: 16,
            color: tokens.fgDim,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              e.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: tokens.fg),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            e.isDirectory ? '目录' : humanSize(e.size),
            style: TextStyle(fontSize: 11.5, color: tokens.fgDim),
          ),
          if (!e.isDirectory && widget.onReveal != null) ...<Widget>[
            const SizedBox(width: 2),
            AppIconButton(
              tooltip: '打开文件所在位置',
              icon: Icon(
                Icons.folder_open_outlined,
                size: 16,
                color: tokens.fgDim,
              ),
              onPressed: () => widget.onReveal!(e),
            ),
          ],
          if (!e.isDirectory && widget.onDownload != null) ...<Widget>[
            const SizedBox(width: 4),
            AppIconButton(
              tooltip: '下载',
              icon: Icon(
                Icons.download_outlined,
                size: 16,
                color: tokens.fgDim,
              ),
              onPressed: () => widget.onDownload!(e),
            ),
          ],
        ],
      ),
    );

    return MiuixPressable(onPressed: widget.onTap, child: row);
  }
}

/// 空态 / 失效 / 错误统一提示块。
class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 28, color: tokens.fgDim),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: tokens.fg,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, height: 1.5, color: tokens.fgDim),
          ),
        ],
      ),
    );
  }
}
