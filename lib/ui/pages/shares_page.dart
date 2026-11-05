// SPDX-License-Identifier: GPL-3.0-only

/// 我的分享：列出本机创建的分享，支持复制链接 / 停止共享 / 重新启用 / 删除 / 展开浏览。
///
/// 数据来源走注入端口 [MySharesSource]，使 widget test 不必起真实
/// ShareService（它依赖 store、FileRefFactory 与在线探测）。
///
/// 四条操作语义（对应用户实测反馈）：
/// - 停止：enabled=false，索引保留，可「重新启用」；
/// - 重新启用：resume(id)，立刻恢复可用；
/// - 删除：真删库里记录与索引，**绝不碰用户原始文件**，且必须二次确认；
/// - 展开：按页 browse，可下钻子目录，文件给下载入口。
///
/// 链接有两个入口（用户原话：「我说的链接是局域网内可以用的网页链接，可以直接下载的」）：
/// - **复制网页链接**（主要用途）：`http://本机LAN地址:端口/s/分享id`，
///   发给不装本 App 的人，浏览器直接打开就能下载；
/// - 复制 App 链接：lsf:// 深链，只对装了本 App 的设备有意义。
///
/// 网页链接为 null（本机没有局域网地址）时：入口置灰并说明原因，
/// 二维码区域显示「无可用网页链接」——**绝不画一个打不开的地址**。
/// 二维码永远编码网页链接而不是深链：扫码的人多半没装 App。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';

import '../../app/assembly.dart';
import '../../app/theme/tokens.dart';
import '../../core/contracts/contracts.dart';
import '../../core/platform/reveal_in_file_manager.dart';
import '../../core/shares/share_service_impl.dart'
    show ShareDeletable, ShareResumable;
import '../widgets/app_toast.dart';
import '../widgets/qr_panel.dart';
import '../widgets/share_detail_panel.dart';
import '../widgets/share_row.dart';
import '../widgets/share_picker_dialog.dart' show matchesShare;
import '../widgets/edit_name_dialog.dart';
import 'nearby_page.dart' show ServicesNotConnected;

/// 网页链接提供者。
///
/// 存在理由：冻结的 ShareService 契约里没有网页链接方法，
/// 它需要的是「本机局域网地址 + 端口」，属于装配层能力。
/// 用**函数类型**而不是具名接口：这样装配层不必 import lib/ui 的任何类型
/// （否则会把「装配」反向耦合到「界面」，那是错的）。
///
/// 契约（必须遵守）：拿不到本机局域网地址时返回 null，
/// **绝不返回一个打不开的地址**。
typedef WebLinkProvider = Future<Uri?> Function(ShareId id);

/// 没有局域网地址时给用户看的原因。
///
/// 抽成常量而不是内联：Toast 与二维码区域用的是同一句话，
/// 不会出现「上面说一种、下面说另一种」。
const String kNoWebLinkHint = '未检测到局域网地址，无法生成网页链接';

/// 我的分享数据源。
abstract interface class MySharesSource {
  /// 我创建的全部分享。
  Future<List<ShareRecord>> listMine();

  /// 生成 App 深链（lsf://，只对装了本 App 的设备有效）。
  Future<Uri> buildLink(ShareId id);

  /// 生成**浏览器可直接打开**的网页链接（http://我的IP:端口/s/id）。
  ///
  /// 与 [buildLink] 是两种东西，都要给：
  /// - 深链：发给装了 App 的同事，点开能直接唤起；
  /// - 网页链接：发给任何人（手机扫码、粘到浏览器），不用装东西就能下载。
  /// 返回 null 表示本机没有可用的局域网地址（此时只能给深链）。
  Future<Uri?> buildWebLink(ShareId id);

  /// 停止共享。
  Future<void> stop(ShareId id);
  Future<void> rename(ShareId id, String name);

  /// 重新启用已停止的分享。
  Future<void> resume(ShareId id);

  /// 删除分享（只删记录与索引，不碰原文件）。
  Future<void> delete(ShareId id);

  /// 浏览分享内部目录。
  Future<({List<TreeEntryView> entries, String? nextCursor})> browse(
    ShareId id, {
    ItemKey? path,
    String? cursor,
    int limit,
  });
}

/// 由真实 [ShareService] 支撑的数据源。
///
/// resume / delete 在冻结的 [ShareService] 契约上不存在，而是 ShareServiceImpl
/// 的扩展能力。这里用显式 dynamic 派发 + 明确错误处理：
/// 契约不许改、实现文件也不许改类声明，所以不能写 `is ShareResumable`；
/// 但「服务不支持」必须给可读原因而不是崩在 NoSuchMethodError 上。
final class ServiceMySharesSource implements MySharesSource {
  /// 直接委托给契约服务，不做任何额外缓存。
  const ServiceMySharesSource(this.service, {this.webLink});

  /// 共享服务。
  final ShareService service;

  /// 网页链接提供者；为 null 时只提供深链（不伪造地址）。
  final WebLinkProvider? webLink;

  @override
  Future<List<ShareRecord>> listMine() => service.listMine();

  @override
  Future<Uri> buildLink(ShareId id) => service.buildLink(id);

  @override
  Future<Uri?> buildWebLink(ShareId id) async {
    // 网页链接需要「本机局域网地址 + 端口」，那属于装配层而不是 ShareService。
    // 没注入就返回 null：上层据此只展示深链，绝不展示一个打不开的地址。
    final WebLinkProvider? provider = webLink;
    if (provider == null) {
      return null;
    }
    return provider(id);
  }

  @override
  Future<void> stop(ShareId id) => service.stop(id);

  @override
  Future<void> rename(ShareId id, String name) => service.rename(id, name);

  @override
  Future<void> resume(ShareId id) async {
    final ShareService s = service;
    // 显式转换是必要的：ShareResumable 与 ShareService 是并列接口，
    // 前者不是后者的子类型，因此 `is` 检查不会触发类型提升。
    if (s is ShareResumable) {
      await (s as ShareResumable).resume(id);
      return;
    }
    throw const LanFileException(LanFileErrorCode.unsupported, '当前共享服务不支持重新启用');
  }

  @override
  Future<void> delete(ShareId id) async {
    final ShareService s = service;
    if (s is ShareDeletable) {
      await (s as ShareDeletable).delete(id);
      return;
    }
    throw const LanFileException(LanFileErrorCode.unsupported, '当前共享服务不支持删除');
  }

  @override
  Future<({List<TreeEntryView> entries, String? nextCursor})> browse(
    ShareId id, {
    ItemKey? path,
    String? cursor,
    int limit = LanFileConstants.treePageSize,
  }) => service.browse(id, path: path, cursor: cursor, limit: limit);
}

/// 把 [MySharesSource] 自己当浏览数据源用。
///
/// 只在「注入了 source 但没注入 browseSource」时启用（测试与轻量场景）。
/// 生产路径走 [ServiceBrowseSource]，两者都是真调用，不是假数据。
final class _SourceBrowseAdapter implements BrowseSource {
  const _SourceBrowseAdapter(this.source);

  final MySharesSource source;

  @override
  Future<BrowsePage> browse(
    ShareId id, {
    ItemKey? path,
    String? cursor,
    required int limit,
  }) async {
    final ({List<TreeEntryView> entries, String? nextCursor}) page =
        await source.browse(id, path: path, cursor: cursor, limit: limit);
    return BrowsePage(entries: page.entries, nextCursor: page.nextCursor);
  }
}

/// 我的分享页面。
class SharesPage extends StatefulWidget {
  /// [services] 为 null 时显示「未连接服务」。
  const SharesPage({
    super.key,
    this.services,
    this.source,
    this.browseSource,
    this.now,
    this.onDownload,
    this.onReveal,
  });

  /// 装配好的服务栈。
  final AppServices? services;

  /// 可注入的数据源。
  final MySharesSource? source;

  /// 可注入的浏览数据源；为 null 时从 [services] 现建。
  final BrowseSource? browseSource;

  /// 判定「过期」用的时间，测试可注入。
  final DateTime? now;

  /// 文件下载入口；实际下载由调用方接 TransferService。
  final void Function(TreeEntryView entry)? onDownload;

  /// 「打开文件所在位置」；由装配层接系统文件管理器。
  /// 为 null 时文件行不显示定位按钮（不制造点了没反应的入口）。
  final void Function(TreeEntryView entry)? onReveal;

  @override
  State<SharesPage> createState() => _SharesPageState();
}

class _SharesPageState extends State<SharesPage> {
  MySharesSource? _source;
  BrowseSource? _browse;
  late Future<List<ShareRecord>> _future;

  /// 当前展开的分享 id；null 表示全部收起。
  String? _expandedId;
  String _search = '';

  StreamSubscription<void>? _domainChanges;

  @override
  void initState() {
    super.initState();
    _domainChanges = widget.services?.localDomain?.changes.listen((_) {
      if (mounted) unawaited(_reload());
    });
    _source =
        widget.source ??
        (widget.services == null
            ? null
            : ServiceMySharesSource(
                widget.services!.shares,
                // 网页链接需要本机局域网地址与端口：那是装配层能力。
                // 由 AppServices.buildWebLink 提供（装配层负责，UI 不猜地址）。
                webLink: widget.services?.buildWebLink,
              ));
    // 浏览数据源：显式注入优先；否则若 source 自己就能浏览（测试替身常见），
    // 直接用它；最后才从真实服务现建。
    _browse =
        widget.browseSource ??
        (widget.source != null
            ? _SourceBrowseAdapter(widget.source!)
            : (widget.services == null
                  ? null
                  : ServiceBrowseSource(widget.services!.shares)));
    _future = _load();
  }

  Future<List<ShareRecord>> _load() async {
    final MySharesSource? source = _source;
    if (source == null) return const <ShareRecord>[];
    return source.listMine();
  }

  Future<void> _reload() async {
    setState(() {
      _future = _load();
    });
  }

  @override
  void dispose() {
    _domainChanges?.cancel();
    super.dispose();
  }

  /// 统一提示出口：浮层 Toast，不再占用页面顶部条。
  void _notify(String message, {bool isError = false}) {
    if (!mounted) return;
    AppToast.show(context, message, isError: isError);
  }

  /// 复制网页链接：浏览器可直接打开并下载，是主要用途。
  Future<void> _copyWebLink(ShareRecord share) async {
    final MySharesSource? source = _source;
    if (source == null) return;
    try {
      final Uri? uri = await source.buildWebLink(share.id);
      if (uri == null) {
        // 不静默：用户点了就必须知道「为什么没复制到」。
        _notify(kNoWebLinkHint, isError: true);
        return;
      }
      await Clipboard.setData(ClipboardData(text: uri.toString()));
      _notify('已复制网页链接：$uri');
    } on Object catch (error) {
      _notify('复制网页链接失败：$error', isError: true);
    }
  }

  /// 复制 App 深链：只对装了本 App 的设备有效。
  Future<void> _copyAppLink(ShareRecord share) async {
    final MySharesSource? source = _source;
    if (source == null) return;
    try {
      final Uri uri = await source.buildLink(share.id);
      await Clipboard.setData(ClipboardData(text: uri.toString()));
      _notify('已复制 App 链接');
    } on Object catch (error) {
      _notify('复制 App 链接失败：$error', isError: true);
    }
  }

  /// 解析当前分享的网页链接。
  ///
  /// 返回 null 表示「本机没有可用的局域网地址」，由卡片侧置灰入口并说明原因。
  /// 查询失败也按 null 处理——宁可不让用户复制一个可能打不开的地址。
  Future<Uri?> _resolveWebLink(ShareRecord share) async {
    final MySharesSource? source = _source;
    if (source == null) return null;
    try {
      return await source.buildWebLink(share.id);
    } on Object {
      return null;
    }
  }

  Future<void> _stop(ShareRecord share) async {
    final MySharesSource? source = _source;
    if (source == null) return;
    try {
      await source.stop(share.id);
      _notify('已停止共享：${share.displayName}');
      await _reload();
    } on Object catch (error) {
      _notify('停止共享失败：$error', isError: true);
    }
  }

  Future<void> _rename(ShareRecord share) async {
    final String? name = await showDialog<String>(
      context: context,
      builder: (_) => EditNameDialog(
        title: '设置分享名称',
        label: '分享名称',
        initialValue: share.displayName,
        maxLength: 128,
        fieldKey: const ValueKey<String>('share-name-field'),
      ),
    );
    if (name == null || !mounted) return;
    try {
      await _source!.rename(share.id, name);
      _notify('分享名称已保存');
      await _reload();
    } on Object catch (error) {
      _notify('分享名称保存失败：$error', isError: true);
    }
  }

  Future<void> _resume(ShareRecord share) async {
    final MySharesSource? source = _source;
    if (source == null) return;
    try {
      await source.resume(share.id);
      _notify('已重新启用：${share.displayName}');
      await _reload();
    } on Object catch (error) {
      _notify('重新启用失败：$error', isError: true);
    }
  }

  /// 删除是终态操作：先弹二次确认，确认后才真删。
  Future<void> _confirmDelete(ShareRecord share) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('删除这条分享？'),
        content: Text(
          '「${share.displayName}」将从列表里移除，链接立即失效。\n'
          '你磁盘上的原始文件不会被删除——本工具只记录文件位置。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _delete(share);
  }

  Future<void> _delete(ShareRecord share) async {
    final MySharesSource? source = _source;
    if (source == null) return;
    try {
      await source.delete(share.id);
      if (!mounted) return;
      setState(() {
        if (_expandedId == share.id.value) _expandedId = null;
      });
      _notify('已删除：${share.displayName}');
      await _reload();
    } on Object catch (error) {
      _notify('删除失败：$error', isError: true);
    }
  }

  /// 默认的「打开文件所在位置」：把分享根 + 条目相对路径拼成绝对路径，
  /// 交给系统文件管理器选中。安卓 SAF 分享没有磁盘路径，给可读提示。
  Future<void> _revealDefault(ShareRecord share, TreeEntryView entry) async {
    final String? absolutePath =
        share.rootKind == 'localPath' && share.kind == 'file'
        ? share.rootUri
        : joinShareItemPath(
            rootKind: share.rootKind,
            rootUri: share.rootUri,
            itemKey: entry.itemKey.value,
          );
    if (absolutePath == null) {
      _notify('这是安卓文档分享，没有本地磁盘路径可定位', isError: true);
      return;
    }
    final String? error = await revealInFileManager(absolutePath);
    if (error != null) {
      _notify(error, isError: true);
    }
  }

  /// 「查看文件」：**弹窗**，不是在卡片下面内嵌一段列表。
  ///
  /// 用户实测反馈「展开文件没有弹窗显示」。内嵌那套有两个问题：
  /// 1. 卡片被撑得很高，列表混在卡片流里，视觉上不像「查看一个文件夹」；
  /// 2. 二维码 + 文件列表挤在卡片内，密度过高。
  /// 弹窗把「这一个分享的细节」单独放一层，卡片保持精简。
  Future<void> _toggleExpand(ShareRecord share) async {
    final BrowseSource? browse = _browse;
    if (browse == null) {
      _notify('无法查看文件：浏览服务未连接', isError: true);
      return;
    }
    setState(() => _expandedId = share.id.value);
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext dialogContext) => _ShareDetailDialog(
          share: share,
          browse: browse,
          resolveWebLink: () => _resolveWebLink(share),
          onDownload: widget.onDownload,
          // 定位能力：优先用外部注入；没注入时用平台默认实现
          // （拼绝对路径 -> 系统文件管理器选中）。
          onReveal:
              widget.onReveal ??
              (TreeEntryView entry) => _revealDefault(share, entry),
          now: widget.now,
        ),
      );
    } finally {
      if (mounted) setState(() => _expandedId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    if (_source == null) {
      return const ServicesNotConnected();
    }
    return FutureBuilder<List<ShareRecord>>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<List<ShareRecord>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '加载分享失败：${snapshot.error}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: tokens.fgDim),
              ),
            ),
          );
        }
        final List<ShareRecord> shares = snapshot.data ?? const <ShareRecord>[];
        final visibleShares = shares
            .where((share) => matchesShare(share, _search))
            .toList();
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: <Widget>[
                  Text(
                    '我的分享',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: tokens.fg,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '共 ${shares.length} 项',
                    style: TextStyle(fontSize: 12, color: tokens.fgDim),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '刷新',
                    icon: Icon(Icons.refresh, size: 18, color: tokens.fgDim),
                    onPressed: _reload,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: TextField(
                key: const ValueKey('my-shares-search'),
                onChanged: (text) => setState(() => _search = text),
                decoration: const InputDecoration(
                  hintText: '搜索分享名称或文件位置',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Expanded(
              child: shares.isEmpty
                  ? _EmptyShares()
                  : visibleShares.isEmpty
                  ? const Center(child: Text('没有匹配的分享'))
                  : LayoutBuilder(
                      builder: (context, constraints) => GridView.builder(
                        key: const ValueKey('my-shares-grid'),
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: ((constraints.maxWidth - 24) / 280)
                              .floor()
                              .clamp(1, 5),
                          mainAxisExtent:
                              112 *
                              (MediaQuery.textScalerOf(context).scale(14) / 14)
                                  .clamp(1.0, double.infinity)
                                  .toDouble(),
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: visibleShares.length,
                        itemBuilder: (BuildContext context, int index) {
                          final ShareRecord share = visibleShares[index];
                          final ShareStatus status = shareStatusOf(
                            share,
                            now: widget.now,
                          );
                          final bool expanded = _expandedId == share.id.value;
                          return _ShareCard(
                            key: ValueKey(
                              '${share.id.value}:${widget.services?.localDomain?.host ?? ''}:${widget.services?.localDomain?.ready ?? true}',
                            ),
                            share: share,
                            status: status,
                            expanded: expanded,
                            canExpand: _browse != null,
                            onToggleExpand: () => _toggleExpand(share),
                            onCopyWebLink: () => _copyWebLink(share),
                            onCopyAppLink: () => _copyAppLink(share),
                            resolveWebLink: () => _resolveWebLink(share),
                            onStop: () => _stop(share),
                            onResume: () => _resume(share),
                            onDelete: () => _confirmDelete(share),
                            onRename: () => _rename(share),
                            now: widget.now,
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// 单条分享卡片：在 [ShareRow] 之上补充「展开 / 重新启用 / 删除」三个入口。
///
/// 为什么复用 ShareRow 而不是另写一张卡：ShareRow 已被其它调用点使用，
/// 它的状态判定与按钮禁用语义（active 才可复制/停止）是既有行为契约，
/// 重画一张卡会让所有基于 find.byType(ShareRow) 的既有断言失效，那是退化。
/// 这里只在它下面追加一行额外操作，既有语义原样保留。
class _ShareCard extends StatefulWidget {
  const _ShareCard({
    super.key,
    required this.share,
    required this.status,
    required this.expanded,
    required this.canExpand,
    required this.onToggleExpand,
    required this.onCopyWebLink,
    required this.onCopyAppLink,
    required this.resolveWebLink,
    required this.onStop,
    required this.onResume,
    required this.onDelete,
    required this.onRename,
    this.now,
  });

  final ShareRecord share;
  final ShareStatus status;
  final bool expanded;
  final bool canExpand;
  final VoidCallback onToggleExpand;

  /// 复制网页链接（浏览器可打开）。
  final VoidCallback onCopyWebLink;

  /// 复制 App 深链。
  final VoidCallback onCopyAppLink;

  /// 解析本分享的网页链接（决定入口是否可点、二维码是否画）。
  final Future<Uri?> Function() resolveWebLink;

  final VoidCallback onStop;
  final VoidCallback onResume;
  final VoidCallback onDelete;
  final VoidCallback onRename;
  final DateTime? now;

  @override
  State<_ShareCard> createState() => _ShareCardState();
}

class _ShareCardState extends State<_ShareCard> {
  final GlobalKey<_ShareActionsMenuState> _menuKey = GlobalKey();

  /// 本分享的网页链接；null 表示「没有可用局域网地址」。
  ///
  /// 三种状态用 _webLinkKnown 区分：未知（还在解析）/ 已知有 / 已知没有。
  Uri? _webLink;
  bool _webLinkKnown = false;
  bool _webLinkLoading = false;

  @override
  void initState() {
    super.initState();
    _loadWebLink();
  }

  @override
  void didUpdateWidget(covariant _ShareCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 分享换了（列表刷新后 id 可能不同），重新解析。
    if (oldWidget.share.id != widget.share.id) {
      _webLinkKnown = false;
      _webLink = null;
      _loadWebLink();
    }
  }

  Future<void> _loadWebLink() async {
    if (_webLinkLoading) return;
    setState(() => _webLinkLoading = true);
    Uri? link;
    try {
      link = await widget.resolveWebLink();
    } on Object {
      // A renamed domain is unavailable briefly while its ownership is probed.
      // The domain change stream rebuilds this card when registration completes.
    }
    if (!mounted) return;
    setState(() {
      _webLink = link;
      _webLinkKnown = true;
      _webLinkLoading = false;
    });
  }

  /// 点「复制网页链接」。
  ///
  /// 解析中不阻塞点击：若已知为 null，直接给原因；若还没解析出来，现查一次。
  Future<void> _onCopyWeb() async {
    if (_webLink == null && !_webLinkKnown) {
      await _loadWebLink();
      if (!mounted) return;
    }
    widget.onCopyWebLink();
  }

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    final ShareRecord share = widget.share;
    final ShareStatus status = widget.status;
    final bool stopped = status == ShareStatus.stopped;
    // 已撤销 / 已失效的行不给「重新启用」：前者是终态，后者要先重新定位。
    final bool canResume = stopped;
    // 网页链接为 null 时入口置灰；解析中先按不可用处理，避免用户点到空结果。
    final bool webAvailable = _webLink != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 动作全部收进右侧一个菜单。
        //
        // 为什么：之前卡片上并排出现「复制网页链接 / 复制 App 链接 / 复制链接 /
        // 停止共享」，底部再一排「展开查看文件 / 重新启用 / 删除」——
        // 七个按钮把一张卡挤满，其中三个还是「复制链接」的同义重复，
        // 用户实测直接说「这些按钮都合到这一个组件里面去，不要在这个外面显示」。
        // 菜单里只保留**互不重复**的语义，App 深链按用户要求去掉。
        Expanded(
          child: GestureDetector(
            onSecondaryTapDown: (details) =>
                _menuKey.currentState?.openContextMenu(details.globalPosition),
            onLongPressStart: (details) =>
                _menuKey.currentState?.openContextMenu(details.globalPosition),
            child: ShareRow(
              share: share,
              compact: true,
              now: widget.now,
              // ShareRow 自带的「复制链接」隐藏：复制只从菜单走，避免两处入口重复。
              onCopyLink: null,
              onStop: null,
              trailing: ShareActionsMenu(
                key: _menuKey,
                webAvailable: webAvailable,
                onCopyWeb: _onCopyWeb,
                canExpand: widget.canExpand,
                expanded: widget.expanded,
                onToggleExpand: widget.onToggleExpand,
                canStop: !canResume,
                onStop: widget.onStop,
                canResume: canResume,
                onResume: widget.onResume,
                onDelete: widget.onDelete,
                onRename: widget.onRename,
              ),
            ),
          ),
        ),
        if (_webLinkKnown && !webAvailable)
          Padding(
            padding: const EdgeInsets.fromLTRB(52, 0, 16, 8),
            child: Text(
              kNoWebLinkHint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: tokens.fgDim),
            ),
          ),
      ],
    );
  }
}

/// 单条分享的动作菜单：**自绘悬浮菜单**，从 ⋯ 图标处弹出。
///
/// 为什么不用 PopupMenuButton：
/// 1. 它自带 tooltip 与长按行为，在桌面端会出现「图标旁边一块灰块」的渲染问题（用户实测截图可见）；
/// 2. 它的样式受 Material 主题默认值影响，与我们的双色 token 体系对不上，
///    看起来就是「Material 弹窗」而不是这个应用的菜单。
///
/// 这里用 OverlayEntry 自绘：定位在图标下方、圆角 radiusCard、surface 底 + cardLine 描边 +
/// shadowColor 阴影，全部走 token。
class ShareActionsMenu extends StatefulWidget {
  const ShareActionsMenu({
    super.key,
    required this.webAvailable,
    required this.onCopyWeb,
    required this.canExpand,
    required this.expanded,
    required this.onToggleExpand,
    required this.canStop,
    required this.onStop,
    required this.canResume,
    required this.onResume,
    required this.onDelete,
    this.onRename,
  });

  final bool webAvailable;
  final VoidCallback onCopyWeb;
  final bool canExpand;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final bool canStop;
  final VoidCallback onStop;
  final bool canResume;
  final VoidCallback onResume;
  final VoidCallback onDelete;
  final VoidCallback? onRename;

  @override
  State<ShareActionsMenu> createState() => _ShareActionsMenuState();
}

class _ShareActionsMenuState extends State<ShareActionsMenu> {
  final GlobalKey _anchorKey = GlobalKey();
  OverlayEntry? _entry;

  /// 悬浮自动展开的计时器：进入图标区域后短暂延时再打开，
  /// 避免鼠标「路过」就弹菜单。离开时取消。
  Timer? _hoverOpenTimer;

  /// 菜单关闭后的一小段缓冲：鼠标从图标移到菜单时中间会经过空隙，
  /// 立刻关会让人根本点不到菜单项。
  Timer? _hoverCloseTimer;
  bool _pointerInMenu = false;

  static const Duration _openDelay = Duration(milliseconds: 180);
  static const Duration _closeDelay = Duration(milliseconds: 260);

  @override
  void dispose() {
    _hoverOpenTimer?.cancel();
    _hoverCloseTimer?.cancel();
    _remove();
    super.dispose();
  }

  /// 鼠标进入：延时自动展开。
  void _scheduleOpen() {
    _hoverCloseTimer?.cancel();
    if (_entry != null) return;
    _hoverOpenTimer?.cancel();
    _hoverOpenTimer = Timer(_openDelay, () {
      if (mounted && _hover) _open();
    });
  }

  /// 鼠标离开：留缓冲再关，且只在指针不在菜单里时关。
  void _scheduleClose() {
    _hoverOpenTimer?.cancel();
    _hoverCloseTimer?.cancel();
    _hoverCloseTimer = Timer(_closeDelay, () {
      if (mounted && !_pointerInMenu && !_hover) {
        _remove();
        setState(() {});
      }
    });
  }

  void _remove() {
    _hoverOpenTimer?.cancel();
    _hoverCloseTimer?.cancel();
    _pointerInMenu = false;
    final OverlayEntry? e = _entry;
    _entry = null;
    if (e != null) {
      e.remove();
      // remove 是异步的：立刻 dispose 会触发 Flutter 断言。
      scheduleMicrotask(e.dispose);
    }
  }

  /// 点击切换（手动开/关），与悬浮自动展开共用同一个 [_open]。
  void _toggle() {
    if (_entry != null) {
      _remove();
      setState(() {});
      return;
    }
    _open();
  }

  void _open([Offset? pointerPosition]) {
    if (_entry != null) return;
    final RenderBox? box =
        _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final Offset topLeft = pointerPosition == null
        ? box.localToGlobal(Offset.zero)
        : pointerPosition - const Offset(0, 34);
    final double anchorW = pointerPosition == null ? box.size.width : 0;
    _entry = OverlayEntry(
      builder: (BuildContext context) => _MenuPopover(
        anchor: topLeft,
        anchorWidth: anchorW,
        onDismiss: () {
          _remove();
          _pointerInMenu = false;
          if (mounted) setState(() {});
        },
        groupId: this,
        onPointerEnter: () {
          _pointerInMenu = true;
          _hoverCloseTimer?.cancel();
        },
        onPointerExit: () {
          _pointerInMenu = false;
          if (!_hover) _scheduleClose();
        },
        items: _buildItems(context),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);
    if (mounted) setState(() {});
  }

  List<ShareMenuItem> _buildItems(BuildContext context) {
    return <ShareMenuItem>[
      if (widget.onRename != null)
        ShareMenuItem(
          icon: Symbols.edit,
          label: '设置分享名称',
          onTap: widget.onRename!,
        ),
      ShareMenuItem(
        icon: Symbols.public,
        label: widget.webAvailable ? '复制网页链接' : '复制网页链接（不可用）',
        enabled: widget.webAvailable,
        onTap: widget.onCopyWeb,
      ),
      if (widget.canExpand)
        ShareMenuItem(
          icon: widget.expanded
              ? Symbols.keyboard_arrow_up
              : Symbols.unfold_more,
          label: widget.expanded ? '收起内容' : '展开查看文件',
          onTap: widget.onToggleExpand,
        ),
      if (widget.canResume)
        ShareMenuItem(
          icon: Symbols.play_circle,
          label: '重新启用',
          onTap: widget.onResume,
        ),
      if (widget.canStop)
        ShareMenuItem(icon: Symbols.block, label: '停止共享', onTap: widget.onStop),
      ShareMenuItem(
        icon: Symbols.delete_outline,
        label: '删除',
        danger: true,
        dividerBefore: true,
        onTap: widget.onDelete,
      ),
    ];
  }

  bool _hover = false;

  void openContextMenu(Offset position) {
    _remove();
    _open(position);
  }

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    final bool active = _entry != null || _hover;
    return TapRegion(
      groupId: this,
      child: Semantics(
        label: '更多操作',
        button: true,
        child: MouseRegion(
          onEnter: (_) {
            if (!_hover) setState(() => _hover = true);
            // 悬浮自动下拉：不用点，鼠标停一下就展开。
            _scheduleOpen();
          },
          onExit: (_) {
            setState(() => _hover = false);
            _scheduleClose();
          },
          child: SizedBox(
            key: const ValueKey<String>('share-actions-menu'),
            width: 26,
            height: 26,
            child: InkWell(
              key: _anchorKey,
              onTap: _toggle,
              borderRadius: BorderRadius.circular(LanFileMetrics.radiusRow),
              // 默认态也带一个浅圆底 + 描边：用户实测反馈「icon 也看不到」，
              // 白卡上一个淡灰小点确实容易消失。给个可点击的形状，
              // hover/打开时再加深底色并转 accent 图标。
              child: Container(
                decoration: BoxDecoration(
                  color: active ? tokens.accentSoft : tokens.surfaceSunken,
                  borderRadius: BorderRadius.circular(LanFileMetrics.radiusRow),
                  border: Border.all(
                    color: active ? tokens.accent : tokens.cardLine,
                    width: LanFileMetrics.hairline,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Symbols.more_horiz,
                  size: 16,
                  color: active ? tokens.accent : tokens.fg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 菜单项的数据形态。
final class ShareMenuItem {
  const ShareMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.danger = false,
    this.dividerBefore = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool danger;
  final bool dividerBefore;
}

/// 悬浮菜单本体：自己处理点击外部关闭。
class _MenuPopover extends StatelessWidget {
  const _MenuPopover({
    required this.anchor,
    required this.anchorWidth,
    required this.onDismiss,
    required this.onPointerEnter,
    required this.onPointerExit,
    required this.items,
    required this.groupId,
  });

  final Offset anchor;
  final double anchorWidth;
  final VoidCallback onDismiss;

  /// 指针进入/离开菜单区域：图标到菜单之间有空隙，靠这两个回调
  /// 配合缓冲计时器，避免鼠标一移动菜单就消失。
  final VoidCallback onPointerEnter;
  final VoidCallback onPointerExit;
  final List<ShareMenuItem> items;
  final Object groupId;

  static const double _width = 188;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    // 贴着图标下方展开，右边缘与图标右边缘对齐（菜单比图标宽，向左伸）。
    final size = MediaQuery.sizeOf(context);
    final menuHeight =
        10.0 +
        items.length * 36 +
        items.where((i) => i.dividerBefore).length * 9;
    final double left = (anchor.dx + anchorWidth - _width)
        .clamp(8, size.width - _width - 8)
        .toDouble();
    final double top = (anchor.dy + 34)
        .clamp(8, (size.height - menuHeight - 8).clamp(8, double.infinity))
        .toDouble();
    return Stack(
      children: <Widget>[
        Positioned(
          left: left < 8 ? 8 : left,
          top: top,
          width: _width,
          child: TapRegion(
            groupId: groupId,
            onTapOutside: (_) => onDismiss(),
            child: MouseRegion(
              onEnter: (_) => onPointerEnter(),
              onExit: (_) => onPointerExit(),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: tokens.surface,
                    borderRadius: BorderRadius.circular(
                      LanFileMetrics.radiusCard,
                    ),
                    border: Border.all(color: tokens.cardLine),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: tokens.shadowColor,
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (final ShareMenuItem item in items) ...<Widget>[
                        if (item.dividerBefore)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            child: Divider(height: 1, color: tokens.line),
                          ),
                        _MenuRow(item: item, onDismiss: onDismiss),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatefulWidget {
  const _MenuRow({required this.item, required this.onDismiss});

  final ShareMenuItem item;
  final VoidCallback onDismiss;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    final ShareMenuItem item = widget.item;
    final Color fg = !item.enabled
        ? tokens.fgDim
        : (item.danger ? tokens.accent : tokens.fg);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: item.enabled
            ? () {
                widget.onDismiss();
                item.onTap();
              }
            : null,
        child: Container(
          height: 36,
          color: _hover && item.enabled ? tokens.hoverSoft : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: <Widget>[
              Icon(item.icon, size: 16, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(fontSize: 13, color: fg),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 空状态：解释为什么空 + 下一步能做什么。
/// 空状态：解释为什么空 + 下一步能做什么。
class _EmptyShares extends StatelessWidget {
  const _EmptyShares();

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Symbols.folder_open, size: 32, color: tokens.fgDim),
              const SizedBox(height: 12),
              Text(
                '还没有分享',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: tokens.fg,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '把文件或文件夹拖到窗口任意位置即可创建分享。'
                '分享只记录文件位置，不复制文件本体。',
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

/// 网页链接二维码左栏：小尺寸 + 一行说明。
///
/// 尺寸策略：弹窗里二维码只占左侧窄栏，边长固定 140，
/// 不再铺满整行——用户明确要求「二维码小一点」。
class _WebLinkQrSection extends StatefulWidget {
  const _WebLinkQrSection({
    required this.resolveWebLink,
    required this.shareName,
  });

  final Future<Uri?> Function() resolveWebLink;
  final String shareName;

  @override
  State<_WebLinkQrSection> createState() => _WebLinkQrSectionState();
}

class _WebLinkQrSectionState extends State<_WebLinkQrSection> {
  Future<Uri?>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.resolveWebLink();
  }

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    return FutureBuilder<Uri?>(
      future: _future,
      builder: (BuildContext context, AsyncSnapshot<Uri?> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final Uri? uri = snap.data;
        if (uri == null) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Symbols.qr_code_2, size: 28, color: tokens.fgDim),
                const SizedBox(height: 8),
                Text(
                  '无可用网页链接',
                  style: TextStyle(fontSize: 12, color: tokens.fgDim),
                ),
                const SizedBox(height: 4),
                Text(
                  '未检测到局域网地址，无法生成二维码。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: tokens.fgDim),
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              // 小二维码：QrPanel 内部还有链接文字，不能用固定高度硬框，
              // 否则会溢出。改为按左栏宽度自适应，边长压到 120。
              QrPanel(
                linkText: uri.toString(),
                layout: QrPanelLayout.compact,
                minSize: 120,
                maxSize: 120,
              ),
              const SizedBox(height: 10),
              Text(
                '扫码用浏览器下载',
                style: TextStyle(fontSize: 12, color: tokens.fg),
              ),
              const SizedBox(height: 4),
              SelectableText(
                uri.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10.5, color: tokens.fgDim),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 「查看文件」弹窗：左二维码 / 右文件列表。
///
/// 布局（用户明确要求）：
/// - 左边一列：小二维码 + 一行说明；
/// - 右边一列：文件列表，**内部自己滚动**（不撑高整个弹窗）；
/// - 两列之间一条竖直分隔线，各自独立，不互相挤压。
///
/// 为什么左右分栏而不是上下堆叠：上下堆叠时二维码和列表共享一个
/// 纵向滚动区，列表一长二维码就被顶出视野；左右分栏后二维码常驻可见。
class _ShareDetailDialog extends StatelessWidget {
  const _ShareDetailDialog({
    required this.share,
    required this.browse,
    required this.resolveWebLink,
    this.onDownload,
    this.onReveal,
    this.now,
  });

  final ShareRecord share;
  final BrowseSource browse;
  final Future<Uri?> Function() resolveWebLink;
  final void Function(TreeEntryView entry)? onDownload;
  final void Function(TreeEntryView entry)? onReveal;
  final DateTime? now;

  /// 左栏宽度：容纳 156px 二维码 + 内边距。
  static const double _leftWidth = 196;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    return Dialog(
      backgroundColor: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LanFileMetrics.radiusPanel),
        side: BorderSide(color: tokens.cardLine),
      ),
      child: SizedBox(
        width: 760,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // 标题栏：文件夹名 + 关闭。
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: <Widget>[
                  Icon(Symbols.folder_open, size: 20, color: tokens.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Tooltip(
                      message: shareLocationLabel(share),
                      child: Text(
                        shareLocationLabel(share),
                        maxLines: 2,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: tokens.fg,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    icon: Icon(Symbols.close, size: 18, color: tokens.fgDim),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: tokens.line),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // 左栏：小二维码，常驻不滚。
                  SizedBox(
                    width: _leftWidth,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: tokens.surfaceSunken),
                      child: Center(
                        child: SingleChildScrollView(
                          child: _WebLinkQrSection(
                            resolveWebLink: resolveWebLink,
                            shareName: share.displayName,
                          ),
                        ),
                      ),
                    ),
                  ),
                  VerticalDivider(width: 1, color: tokens.line),
                  // 右栏：文件列表，**内部独立滚动**。
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: ShareDetailPanel(
                        share: share,
                        source: browse,
                        onDownload: onDownload,
                        onReveal: onReveal,
                        now: now,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
