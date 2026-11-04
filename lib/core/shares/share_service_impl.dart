// SPDX-License-Identifier: GPL-3.0-only

/// [ShareService] 的实现：创建、列举、停止、重定位、出链接、浏览。
///
/// 三条贯穿全文件的设计约束：
/// 1. create 绝不阻塞：首扫永远在后台，返回值不含索引结果；
/// 2. browse 先查索引：索引命中就只读 SQLite、不碰磁盘；只有索引里没有
///    这个目录时才回退实时列举，避免「每次点开目录都扫盘」把 SAF 拖死；
/// 3. stop 不删索引：停用只是把 enabled 置 false，重新启用要能立刻可用；
/// 4. delete 只删库里的记录与索引，**绝不碰用户的原始文件**——本产品只记位置。
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../contracts/constants.dart';
import '../contracts/errors.dart';
import '../contracts/file_ref.dart';
import '../contracts/identity.dart';
import '../contracts/services.dart';
import '../contracts/store.dart';
import '../contracts/types.dart';
import '../files/local_ref.dart';
import '../store/database.dart' show AppDatabase;
import '../store/store_impl.dart' show LanFileStoreImpl;
import '../store/tables.dart' show ShareItems, Shares;
import '../files/relative_path_codec.dart';
import 'index_scanner.dart';
import 'link_builder.dart';
import 'share_guard.dart';

/// 提供者在线探测：可用性判定的唯一入口。
///
/// 发现层由 discovery 模块提供；这里只依赖这个窄接口，
/// 测试可以注入确定性实现，从而对四种不可用原因逐一断言，不必真起 UDP。
abstract interface class PeerOnlineProbe {
  /// 该 peer 当前是否在线。
  Future<bool> isOnline(PeerId peerId);

  /// 该 peer 最后一次被看到的时间；从未见过返回 null。
  Future<DateTime?> lastSeen(PeerId peerId);
}

/// 永远在线的探测：单机自用与「本机就是提供者」的场景用它。
final class AlwaysOnlineProbe implements PeerOnlineProbe {
  const AlwaysOnlineProbe();

  @override
  Future<bool> isOnline(PeerId peerId) async => true;

  @override
  Future<DateTime?> lastSeen(PeerId peerId) async => null;
}

/// 只认给定集合的探测：测试与「手动加过的人」最常用。
final class FixedOnlineProbe implements PeerOnlineProbe {
  FixedOnlineProbe({
    required Set<PeerId> online,
    Map<PeerId, DateTime>? lastSeen,
  })  : _online = Set<PeerId>.of(online),
        _lastSeen = <PeerId, DateTime>{...?lastSeen};

  final Set<PeerId> _online;
  final Map<PeerId, DateTime> _lastSeen;

  /// 运行时改在线状态。
  void setOnline(PeerId peerId, {required bool online}) {
    if (online) {
      _online.add(peerId);
    } else {
      _online.remove(peerId);
    }
  }

  /// 运行时改「最后在线」时间；传 null 表示从未见过。
  void setLastSeen(PeerId peerId, DateTime? at) {
    if (at == null) {
      _lastSeen.remove(peerId);
    } else {
      _lastSeen[peerId] = at;
    }
  }

  @override
  Future<bool> isOnline(PeerId peerId) async => _online.contains(peerId);

  @override
  Future<DateTime?> lastSeen(PeerId peerId) async => _lastSeen[peerId];
}

/// 不可用原因：四种都对应一条可读中文提示，绝不返回空串。
enum UnavailableReason { offline, disabled, missing, revoked }

/// 把原因翻成给用户看的一句话。
///
/// 刻意做成顶层函数而不是内联：UI 与测试用的是同一份文案，
/// 不会出现「测试断言了 A 文案，界面显示 B 文案」。
String describeUnavailable(
  UnavailableReason reason, {
  DateTime? lastSeen,
  DateTime Function()? clock,
}) {
  switch (reason) {
    case UnavailableReason.offline:
      if (lastSeen == null) {
        return '提供者已离线（尚未收到过在线公告）';
      }
      final DateTime now = (clock ?? DateTime.now)();
      final Duration ago = now.difference(lastSeen.toUtc());
      return '提供者已离线（最后在线 ${_humanizeAgo(ago)}）';
    case UnavailableReason.disabled:
      return '提供者已停止共享这项内容';
    case UnavailableReason.missing:
      return '源文件已失效（可能在提供者侧被移动或删除）';
    case UnavailableReason.revoked:
      return '该分享已被撤销，链接立即失效';
  }
}

/// 把时长说成人话：分钟 / 小时 / 天。
String _humanizeAgo(Duration ago) {
  if (ago.isNegative || ago.inSeconds < 60) {
    // 对方时钟比本机快一点时不要显示负数的「-3 分钟前」。
    return '不到 1 分钟前';
  }
  if (ago.inMinutes < 60) {
    return '${ago.inMinutes} 分钟前';
  }
  if (ago.inHours < 24) {
    return '${ago.inHours} 小时前';
  }
  return '${ago.inDays} 天前';
}

/// 具备「重新启用」能力的分享服务。
///
/// 契约 [ShareService] 冻结时没有 resume，也没有删除；这两件事是在 M7 收尾
/// 根据用户实测反馈补上的。做法与 groups 模块的 GroupLifecycleDelegate 一致：
/// **契约不动，能力在实现侧声明**，调用方按类型判定能力是否存在。
///
/// 为什么不留在 dynamic 派发：那样「实现没提供」只会在运行时以
/// NoSuchMethodError 暴露；类型检查能让编译器与 IDE 当场指出，
/// 且将来有人改实现类声明时会立刻暴露不匹配。
abstract interface class ShareResumable {
  /// 重新启用一条已停止的分享；索引保留，恢复后立刻可浏览。
  Future<void> resume(ShareId id);
}

/// 具备「物理删除」能力的分享服务。
///
/// 与 [ShareService] 的 stop 是两件事：stop 只置 enabled=false（可恢复），
/// delete 把记录与索引真的从库里移除（不可恢复，但**绝不碰用户原文件**）。
abstract interface class ShareDeletable {
  /// 删除分享记录与其全部索引项。
  Future<void> delete(ShareId id);
}

/// 分享服务实现。
final class ShareServiceImpl
    implements ShareService, ShareResumable, ShareDeletable {
  ShareServiceImpl({
    required this.store,
    required this.identity,
    required this.codec,
    required this.localFactory,
    this.safFactory,
    PeerOnlineProbe? probe,
    ShareGuard guard = const ShareGuard(),
    IndexScanner? scanner,
    this.linkBuilder = const LinkBuilder(),
    DateTime Function()? clock,
    String Function()? idGenerator,
    String Function()? tokenIdGenerator,
  })  : _probe = probe ?? const AlwaysOnlineProbe(),
        _guard = guard,
        _clock = clock ?? DateTime.now,
        _idGenerator = idGenerator ?? _defaultShareId,
        _tokenIdGenerator = tokenIdGenerator ?? _defaultTokenId,
        _scanner = scanner ?? IndexScanner(store: store, guard: guard);

  /// 持久化门面。
  final LanFileStore store;

  /// 本机身份；分享 ownerPeerId 与链接签发者都取自它。
  final DeviceIdentity identity;

  /// 能力凭证编解码。
  final CapabilityCodec codec;

  /// 桌面端文件工厂。
  final FileRefFactory localFactory;

  /// 安卓端文件工厂；桌面构建时为 null。
  final FileRefFactory? safFactory;

  /// 链接构造器。
  final LinkBuilder linkBuilder;

  final PeerOnlineProbe _probe;
  final ShareGuard _guard;
  final IndexScanner _scanner;
  final DateTime Function() _clock;
  final String Function() _idGenerator;
  final String Function() _tokenIdGenerator;

  /// 后台首扫的进行中句柄，按 shareId 索引；测试可以据此等待扫描完成。
  final Map<String, Future<ScanResult>> _scans = <String, Future<ScanResult>>{};

  /// 扫描阶段捕获的错误（不抛给调用方，但保留下来）。
  final Map<String, Object> _scanErrors = <String, Object>{};

  /// 等某个分享的首次索引扫描结束；没有在扫返回 null。
  Future<ScanResult?> awaitIndex(ShareId id) async {
    final Future<ScanResult>? running = _scans[id.value];
    if (running == null) return null;
    return running;
  }

  // --------------------------------------------------------------- create

  @override
  Future<ShareRecord> create(CreateShareRequest request) async {
    final String rootUri = _guard.normalizeRoot(
      kind: request.rootKind,
      rootUri: request.rootUri,
    );
    if (request.displayName.trim().isEmpty) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        '分享名称不能为空',
      );
    }
    final FileRefFactory factory = _factoryFor(request.rootKind);

    // 先确认根真的打得开：打不开就没必要落一条永远 missing 的记录。
    final FileRef root = await _openRootRef(
      factory: factory,
      kind: request.rootKind,
      rootUri: rootUri,
    );

    final DateTime now = _clock().toUtc();
    // kind 以实际形态为准：用户选了单文件就当 file share，不靠他手填。
    final String kind = request.kind == 'file' || !root.isDirectory
        ? 'file'
        : 'folder';
    final ShareRecord record = _recordFrom(
      id: ShareId.parse(_idGenerator()),
      kind: kind,
      rootKind: request.rootKind,
      rootUri: rootUri,
      displayName: request.displayName.trim(),
      createdAt: now,
      mode: request.mode,
      enabled: true,
      missing: false,
      isEphemeral: request.mode == ShareMode.offer ||
          request.mode == ShareMode.session,
      expiresAt: request.expiresAt?.toUtc(),
      passwordHash: request.password,
      groupId: request.groupId,
      maxSpeedKbps: request.maxSpeedKbps,
      revokedAt: null,
      sessionId: null,
    );
    await store.upsertShare(record);

    // 后台首扫：不 await，调用方立刻拿回记录。
    _startScan(record, root);
    return record;
  }

  void _startScan(ShareRecord record, FileRef root) {
    // 单文件分享没有子项可扫：直接算完成，不去 list 一个文件。
    if (!root.isDirectory) {
      _scans[record.id.value] = Future<ScanResult>.value(
        const ScanResult(
          directoriesVisited: 0,
          itemsIndexed: 0,
          truncated: false,
          failures: 0,
        ),
      );
      return;
    }
    final Future<ScanResult> future = _scanner.scan(
      shareId: record.id,
      root: root,
    );
    _scans[record.id.value] = future;
    // 扫描失败不能变成未捕获错误，也不能吞掉：记 missing，让 UI 如实显示已失效。
    // 但 markShareMissing 自己也可能失败（例如库已关闭），所以这一层不能再抛，
    // 否则会把一个后台错误变成进程级未捕获异常。
    future.then(
      (ScanResult _) {},
      onError: (Object error, StackTrace stack) async {
        _scanErrors[record.id.value] = error;
        try {
          await store.markShareMissing(record.id, missing: true);
        } on Object {
          // 库已关或记录已删：后台任务无从补救，保留 _scanErrors 供排查。
        }
      },
    );
  }

  /// 等所有在跑的首次扫描结束；测试清理与优雅关闭用。
  Future<void> drainIndex() async {
    while (_scans.isNotEmpty) {
      await Future.wait<void>(
        _scans.values.map(
          (Future<ScanResult> f) => f.then<void>(
            (ScanResult _) {},
            onError: (Object error, StackTrace stack) {},
          ),
        ),
      );
      break;
    }
  }

  /// 扫描过程中捕获到的错误，按 shareId 索引；仅供诊断与测试断言。
  Map<String, Object> get scanErrors =>
      Map<String, Object>.unmodifiable(_scanErrors);

  // ------------------------------------------------------------ list / stop

  @override
  Future<List<ShareRecord>> listMine() =>
      store.listShares(owner: identity.peerId);

  @override
  Future<void> stop(ShareId id) async {
    final ShareRecord record = await _requireShare(id);
    // 停用只改 enabled：索引一律保留，重新启用才能立刻可浏览。
    await store.upsertShare(_withFlags(record, enabled: false));
  }

  @override
  Future<void> rename(ShareId id, String name) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.runes.length > 128 ||
        trimmed.codeUnits.any((c) => c < 32 || c == 127)) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument, '分享名称需要 1 至 128 个字符，不能包含控制字符',
      );
    }
    final ShareRecord record = await _requireShare(id);
    await store.upsertShare(record.copyWith(displayName: trimmed));
  }

  /// 重新启用：索引还在，可立刻浏览。
  @override
  Future<void> resume(ShareId id) async {
    final ShareRecord record = await _requireShare(id);
    if (record.isRevoked) {
      throw LanFileException(
        LanFileErrorCode.revoked,
        '分享已撤销，不能重新启用：${id.value}',
      );
    }
    await store.upsertShare(_withFlags(record, enabled: true));
  }

  /// 撤销分享：置 revokedAt 并停止提供。
  Future<void> revoke(ShareId id) async {
    await _requireShare(id);
    await store.revokeShare(id, at: _clock().toUtc());
  }

  /// 从库里真正删除一条分享及其全部索引项。
  ///
  /// **不删除磁盘上的原始文件**：本产品只记录文件位置，从不复制也不拥有用户的文件。
  /// 删除的是「这条分享记录」与它的 share_item 索引——用户的原文件一个字节都不动。
  ///
  /// 语义选择：**幂等**。id 不存在时静默返回而不是抛 notFound。理由是删除是不可逆操作，
  /// UI 上「删除一个已经不在的条目」的正确表现是「它现在确实没了」而不是弹一个错误，
  /// 让用户对着一个已经不存在的条目反复看到失败提示是没有意义的。
  ///
  /// 为什么不用 store.revokeShare：撤销只是置 revokedAt，记录还在（findShare 仍查得到），
  /// 与「删除」是两件事。契约里没有删除方法，因此这里走 [LanFileStoreImpl.database]——
  /// 那是 store 实现自带的、给管理页用的库句柄（契约注释里写明了用途）。
  /// 若将来契约补了 deleteShare，这里应改为调用契约方法。
  @override
  Future<void> delete(ShareId id) async {
    final ShareRecord? record = await store.findShare(id);
    if (record == null) {
      // 幂等：已经没了就是成功。
      return;
    }
    // 先等后台扫尾，避免扫描线程在行删完之后又写回索引。
    final Future<ScanResult>? scanning = _scans.remove(record.id.value);
    if (scanning != null) {
      try {
        await scanning;
      } on Object {
        // 扫描失败不影响删除：索引本来就要一起删掉。
      }
    }
    final LanFileStoreImpl? dbStore =
        store is LanFileStoreImpl ? store as LanFileStoreImpl : null;
    if (dbStore == null) {
      // 非 drift 实现（测试替身等）拿不到库句柄：退化为「撤销 + 停用」，
      // 并明确抛 unsupported，绝不假装删掉了。
      await store.revokeShare(id, at: _clock().toUtc());
      throw const LanFileException(
        LanFileErrorCode.unsupported,
        '当前存储实现没有提供物理删除能力，已退化为撤销；'
        '分享记录仍然存在，只是链接失效',
      );
    }
    final AppDatabase database = dbStore.database;
    // 外键是 cascade，删 share 会自动带走 share_item；但仍然显式删一次索引，
    // 这样即使某个连接上 foreign_keys 没打开（例如外部工具建的库），也不会留孤儿行。
    await database.transaction(() async {
      await (database.delete(database.shareItems)..where(
            (ShareItems t) => t.shareId.equals(id.value),
          ))
          .go();
      await (database.delete(database.shares)..where(
            (Shares t) => t.id.equals(id.value),
          ))
          .go();
    });
    _scans.remove(record.id.value);
  }

  @override
  Future<void> relocate(ShareId id, String newRootUri) async {
    final ShareRecord record = await _requireShare(id);
    final ShareRootKind kind = _parseRootKind(record.rootKind);
    // 换根之后一定重新过一遍准入闸门，越界直接 invalidArgument。
    final String rootUri = _guard.normalizeRoot(
      kind: kind,
      rootUri: newRootUri,
    );
    final FileRefFactory factory = _factoryFor(kind);
    final FileRef root = await factory.openRoot(rootUri);
    if (!await root.exists()) {
      throw LanFileException(
        LanFileErrorCode.notFound,
        '新分享根不存在或无法访问：$rootUri',
      );
    }
    final ShareRecord updated = _recordFrom(
      id: record.id,
      kind: record.kind,
      rootKind: kind,
      rootUri: rootUri,
      displayName: record.displayName,
      createdAt: record.createdAt,
      mode: record.mode,
      enabled: record.enabled,
      missing: false,
      isEphemeral: record.isEphemeral,
      expiresAt: record.expiresAt,
      passwordHash: record.passwordHash,
      groupId: record.groupId,
      maxSpeedKbps: record.maxSpeedKbps,
      revokedAt: record.revokedAt,
      sessionId: record.sessionId,
    );
    await store.upsertShare(updated);
    _startScan(updated, root);
  }

  // ------------------------------------------------------------- buildLink

  @override
  Future<Uri> buildLink(ShareId id, {CapabilityGrant? grant}) async {
    final ShareRecord record = await _requireShare(id);
    if (record.isRevoked) {
      throw LanFileException(
        LanFileErrorCode.revoked,
        '分享已撤销，不能生成链接：${id.value}',
      );
    }
    if (grant == null) {
      // 没给授权事实时按分享模式决定要不要带凭证：
      // lan 模式给裸链接，其余模式签发 subject 为星的只读凭证。
      if (record.mode == ShareMode.lan) {
        return linkBuilder.build(shareId: id);
      }
      return linkBuilder.buildSigned(
        shareId: id,
        codec: codec,
        issuer: identity.peerId,
        now: _clock().toUtc(),
        tokenId: _tokenIdGenerator(),
      );
    }
    if (grant.shareId != id) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '授权事实的 shareId 与目标分享不一致：'
        '${grant.shareId.value} != ${id.value}',
      );
    }
    final String token = await codec.issue(grant);
    return linkBuilder.build(shareId: id, token: token);
  }

  /// 供测试与后续撤销逻辑使用：取回链接里的分享 id 与凭证。
  ({ShareId shareId, String? token}) parseLink(Uri link) => (
        shareId: linkBuilder.parseShareId(link),
        token: linkBuilder.parseToken(link),
      );

  // ------------------------------------------------------- listPeerShares

  @override
  Future<List<SharedRootView>> listPeerShares(PeerId peer) async {
    final List<ShareRecord> shares = await store.listShares(owner: peer);
    final bool online = await _probe.isOnline(peer);
    final DateTime? lastSeen = await _probe.lastSeen(peer);
    final DateTime now = _clock().toUtc();
    final List<SharedRootView> views = <SharedRootView>[];
    for (final ShareRecord share in shares) {
      final UnavailableReason? reason = unavailableReasonOf(share, online);
      views.add(
        SharedRootView(
          share: share,
          available: reason == null,
          offlineHint: reason == null
              ? null
              : describeUnavailable(
                  reason,
                  lastSeen: lastSeen,
                  clock: () => now,
                ),
        ),
      );
    }
    return views;
  }

  /// 判定顺序与 UI 的心智一致：先看分享本身的状态，再看人还在不在。
  ///
  /// 公开成静态方法，UI 与测试都能拿到同一份判定，不必各写一遍。
  static UnavailableReason? unavailableReasonOf(
    ShareRecord share,
    bool online,
  ) {
    if (share.isRevoked) return UnavailableReason.revoked;
    if (share.missing) return UnavailableReason.missing;
    if (!share.enabled) return UnavailableReason.disabled;
    if (!online) return UnavailableReason.offline;
    return null;
  }

  // ---------------------------------------------------------------- browse

  @override
  Future<({List<TreeEntryView> entries, String? nextCursor})> browse(
    ShareId id, {
    ItemKey? path,
    String? cursor,
    int limit = LanFileConstants.treePageSize,
  }) async {
    if (limit <= 0) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '分页大小必须为正数，实际为 $limit',
      );
    }
    final ShareRecord record = await _requireShare(id);
    if (record.isRevoked) {
      throw LanFileException(
        LanFileErrorCode.revoked,
        '分享已撤销：${id.value}',
      );
    }
    final ShareRootKind rootKind = _parseRootKind(record.rootKind);
    final String rootKey = _rootKeyOf(rootKind, record.rootUri);
    final ItemKey target = path ?? ItemKey.parse(rootKey);

    // 单文件分享没有子项：直接给出这一个条目，索引与实时列举都不适用。
    if (record.kind == 'file') {
      if (target.value != rootKey) {
        throw LanFileException(
          LanFileErrorCode.notFound,
          '单文件分享没有子目录：${target.value}',
        );
      }
      final FileRef single = await _openRootRef(
        factory: _factoryFor(rootKind),
        kind: rootKind,
        rootUri: record.rootUri,
      );
      return (
        entries: <TreeEntryView>[
          TreeEntryView(
            itemKey: ItemKey.parse(rootKey),
            name: single.displayName,
            isDirectory: false,
            size: await single.length(),
            modifiedAt: await single.lastModified(),
          ),
        ],
        nextCursor: null,
      );
    }
    _guard.normalizeItemKey(
      kind: rootKind,
      rootUri: record.rootUri,
      itemKey: target,
    );

    // 1) 先查索引：命中就完全不碰磁盘。
    final ({List<TreeEntryView> entries, String? nextCursor})? fromIndex =
        await _browseFromIndex(
      shareId: id,
      directory: target,
      rootKey: rootKey,
      cursor: cursor,
      limit: limit,
    );
    if (fromIndex != null) {
      return fromIndex;
    }

    // 2) 索引里没有这个目录：回退实时列举。
    return _browseLive(
      record: record,
      rootKind: rootKind,
      target: target,
      cursor: cursor,
      limit: limit,
    );
  }

  /// 从索引取一页；索引里没有这个目录时返回 null，由调用方回退实时列举。
  ///
  /// 前缀一律按 rune 数算：store.listItems 的 prefix 过滤是
  /// substr(1, prefix.runes.length) 精确比对，用 String.length（UTF-16 码元）
  /// 会让中文目录名的前缀长度多数或少数，直接错位到别的子树。
  Future<({List<TreeEntryView> entries, String? nextCursor})?>
      _browseFromIndex({
    required ShareId shareId,
    required ItemKey directory,
    required String rootKey,
    required String? cursor,
    required int limit,
  }) async {
    final bool isRoot = directory.value == rootKey;
    final String prefix = isRoot ? '' : '${directory.value}/';
    final List<ShareItemRecord> rows = await store.listItems(
      shareId,
      prefix: prefix.isEmpty ? null : prefix,
    );

    if (rows.isEmpty) {
      // 子项为空有两种可能：目录确实空，或这个目录根本没进索引。
      // 只有后者才该回退实时列举；根没进索引时同样回退。
      if (isRoot) return null;
      final bool indexed = await _indexedDirectoryExists(shareId, directory);
      return indexed
          ? (entries: const <TreeEntryView>[], nextCursor: null)
          : null;
    }

    final int prefixRunes = prefix.runes.length;
    final List<ShareItemRecord> children = <ShareItemRecord>[];
    for (final ShareItemRecord row in rows) {
      final String key = row.itemKey.value;
      if (key.runes.length <= prefixRunes) continue;
      final String remainder = String.fromCharCodes(
        key.runes.skip(prefixRunes),
      );
      if (remainder.isEmpty) continue;
      // 只要直接子项：孙子辈的键里还带分隔符，跳过。
      if (remainder.contains('/')) continue;
      children.add(row);
    }

    int begin = 0;
    if (cursor != null && cursor.isNotEmpty) {
      while (begin < children.length &&
          children[begin].itemKey.value.compareTo(cursor) <= 0) {
        begin++;
      }
    }
    final int end = begin + limit < children.length
        ? begin + limit
        : children.length;
    final List<TreeEntryView> entries = <TreeEntryView>[
      for (int i = begin; i < end; i++) _toView(children[i]),
    ];
    final String? nextCursor = end < children.length && end > begin
        ? children[end - 1].itemKey.value
        : null;
    return (entries: entries, nextCursor: nextCursor);
  }

  /// 索引里是否存在这个目录本身（而不是它的子项）。
  ///
  /// 目录自己的那一行由扫描父目录时写入，因此查得到；根没有对应的行。
  Future<bool> _indexedDirectoryExists(
    ShareId shareId,
    ItemKey directory,
  ) async {
    final List<ShareItemRecord> rows = await store.listItems(
      shareId,
      prefix: directory.value,
    );
    for (final ShareItemRecord row in rows) {
      if (row.itemKey.value == directory.value) {
        return row.isDir;
      }
    }
    return false;
  }

  /// 实时列举：索引缺失时的兜底路径。
  Future<({List<TreeEntryView> entries, String? nextCursor})> _browseLive({
    required ShareRecord record,
    required ShareRootKind rootKind,
    required ItemKey target,
    required String? cursor,
    required int limit,
  }) async {
    final FileRefFactory factory = _factoryFor(rootKind);
    final FileRef ref;
    try {
      ref = await factory.resolve(record.rootUri, target);
    } on LanFileException catch (e) {
      if (e.code == LanFileErrorCode.notFound) {
        // 源没了：把 missing 置上，让列表页立刻能显示已失效。
        await store.markShareMissing(record.id, missing: true);
      }
      rethrow;
    }
    if (!await ref.exists()) {
      await store.markShareMissing(record.id, missing: true);
      throw LanFileException(
        LanFileErrorCode.notFound,
        '分享内容已不存在：${target.value}',
      );
    }
    if (!ref.isDirectory) {
      // 单文件分享：browse 直接给出这一个条目。
      return (
        entries: <TreeEntryView>[
          TreeEntryView(
            itemKey: ref.itemKey,
            name: ref.displayName,
            isDirectory: false,
            size: await ref.length(),
            modifiedAt: await ref.lastModified(),
          ),
        ],
        nextCursor: null,
      );
    }
    final FileEntryPage page = await ref.list(cursor: cursor, limit: limit);
    final List<TreeEntryView> entries = <TreeEntryView>[
      for (final FileEntry entry in page.entries)
        TreeEntryView(
          itemKey: entry.itemKey,
          name: entry.name,
          isDirectory: entry.isDirectory,
          size: entry.size,
          modifiedAt: entry.modifiedAt,
          mime: entry.mime,
        ),
    ];
    return (entries: entries, nextCursor: page.nextCursor);
  }

  TreeEntryView _toView(ShareItemRecord row) => TreeEntryView(
        itemKey: row.itemKey,
        name: _displayNameOf(row.itemKey.value),
        isDirectory: row.isDir,
        size: row.isDir ? null : row.size,
        modifiedAt: row.mtime,
        mime: row.mime,
      );

  // --------------------------------------------------------------- helpers

  Future<ShareRecord> _requireShare(ShareId id) async {
    final ShareRecord? record = await store.findShare(id);
    if (record == null) {
      throw LanFileException(
        LanFileErrorCode.notFound,
        '分享不存在：${id.value}',
      );
    }
    return record;
  }

  /// 只翻转 flags，其余字段原样保留：避免「改一个布尔值顺手抹掉别的列」。
  ShareRecord _withFlags(ShareRecord r, {required bool enabled}) =>
      _recordFrom(
        id: r.id,
        kind: r.kind,
        rootKind: _parseRootKind(r.rootKind),
        rootUri: r.rootUri,
        displayName: r.displayName,
        createdAt: r.createdAt,
        mode: r.mode,
        enabled: enabled,
        missing: r.missing,
        isEphemeral: r.isEphemeral,
        expiresAt: r.expiresAt,
        passwordHash: r.passwordHash,
        groupId: r.groupId,
        maxSpeedKbps: r.maxSpeedKbps,
        revokedAt: r.revokedAt,
        sessionId: r.sessionId,
      );

  ShareRecord _recordFrom({
    required ShareId id,
    required String kind,
    required ShareRootKind rootKind,
    required String rootUri,
    required String displayName,
    required DateTime createdAt,
    required ShareMode mode,
    required bool enabled,
    required bool missing,
    required bool isEphemeral,
    required DateTime? expiresAt,
    required String? passwordHash,
    required String? groupId,
    required int? maxSpeedKbps,
    required DateTime? revokedAt,
    required String? sessionId,
  }) =>
      ShareRecord(
        id: id,
        kind: kind,
        rootKind: rootKind.name,
        rootUri: rootUri,
        displayName: displayName,
        ownerPeerId: identity.peerId,
        createdAt: createdAt,
        mode: mode,
        enabled: enabled,
        missing: missing,
        isEphemeral: isEphemeral,
        expiresAt: expiresAt,
        passwordHash: passwordHash,
        groupId: groupId,
        maxSpeedKbps: maxSpeedKbps,
        revokedAt: revokedAt,
        sessionId: sessionId,
      );

  /// 打开分享根，兼容「根是单个文件」的桌面分享。
  ///
  /// LocalRefFactory.openRoot 明确只接受目录（它自己就是这么设计的），
  /// 但契约允许 kind=file 的单文件分享，所以这里对桌面路径做一次分流：
  /// 目录走 openRoot，文件走 resolve('.') 的等价物——直接按绝对路径构造。
  Future<FileRef> _openRootRef({
    required FileRefFactory factory,
    required ShareRootKind kind,
    required String rootUri,
  }) async {
    if (kind == ShareRootKind.localPath) {
      final FileSystemEntityType type = FileSystemEntity.typeSync(
        toIoPath(rootUri),
        followLinks: true,
      );
      if (type == FileSystemEntityType.notFound) {
        throw LanFileException(
          LanFileErrorCode.notFound,
          '分享根不存在或无法访问：$rootUri',
        );
      }
      if (type == FileSystemEntityType.file) {
        // 单文件分享：以父目录为 root，itemKey 就是文件名。
        final String parent = p.dirname(rootUri);
        final String name = p.basename(rootUri);
        return LocalRef(rootPath: parent, relativePath: name);
      }
    }
    final FileRef root = await factory.openRoot(rootUri);
    if (!await root.exists()) {
      throw LanFileException(
        LanFileErrorCode.notFound,
        '分享根不存在或无法访问：$rootUri',
      );
    }
    return root;
  }
  FileRefFactory _factoryFor(ShareRootKind kind) {
    switch (kind) {
      case ShareRootKind.localPath:
        return localFactory;
      case ShareRootKind.safTree:
        final FileRefFactory? saf = safFactory;
        if (saf == null) {
          throw const LanFileException(
            LanFileErrorCode.unsupported,
            '本平台未注册 SAF 工厂，无法打开 safTree 分享根',
          );
        }
        return saf;
      case ShareRootKind.mediaStore:
        throw const LanFileException(
          LanFileErrorCode.unsupported,
          'MediaStore 分享根尚未实现',
        );
    }
  }

  /// rootKind 在库里以字符串存，这里做一次严格解析。
  ShareRootKind _parseRootKind(String raw) {
    for (final ShareRootKind kind in ShareRootKind.values) {
      if (kind.name == raw) return kind;
    }
    throw LanFileException(
      LanFileErrorCode.invalidArgument,
      '未知的 rootKind：$raw',
    );
  }

  /// 分享根的 itemKey：桌面是点号，SAF 是根 documentId。
  String _rootKeyOf(ShareRootKind kind, String rootUri) {
    switch (kind) {
      case ShareRootKind.localPath:
        return rootItemKey;
      case ShareRootKind.safTree:
        return safRootDocumentId(rootUri);
      case ShareRootKind.mediaStore:
        throw const LanFileException(
          LanFileErrorCode.unsupported,
          'MediaStore 分享根尚未实现',
        );
    }
  }

  /// itemKey 的最后一段就是展示名。
  String _displayNameOf(String itemKey) {
    final int cut = itemKey.lastIndexOf('/');
    return cut < 0 ? itemKey : itemKey.substring(cut + 1);
  }

  static String _defaultShareId() => 'S${_uniqueSuffix()}';

  static String _defaultTokenId() => 'j_${_uniqueSuffix()}';
}

/// 从 SAF 树 URI 解出根 documentId，例如
/// content://.../tree/primary%3ADCIM 解出 primary:DCIM。
///
/// Uri.pathSegments 已经做过一次百分号解码，因此这里拿到的就是待用形式。
String safRootDocumentId(String rootUri) {
  final Uri uri = Uri.parse(rootUri);
  final List<String> segments = uri.pathSegments;
  if (segments.isEmpty || segments.last == 'tree') {
    throw LanFileException(
      LanFileErrorCode.invalidArgument,
      'SAF 树 URI 缺少 documentId：$rootUri',
    );
  }
  return segments.last;
}

/// 时间戳 + 随机数：36 进制拼接，只用到字母数字，满足 ShareId 正则。
String _uniqueSuffix() {
  final String stamp =
      DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36);
  return '$stamp${Random().nextInt(1 << 31).toRadixString(36)}';
}
