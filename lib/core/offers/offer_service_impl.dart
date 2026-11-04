// SPDX-License-Identifier: GPL-3.0-only

/// OfferService 实现：双向传输的「先征询、后传输」。
///
/// 产品硬约束与落点（逐条对应任务要求）：
///
/// 1. **propose 只带元数据**：文件内容一个字节都不读。对端离线时抛
///    providerOffline，**不排队**——排队会让发送方以为已送达。
/// 2. **接受前零字节**：accept 之前不存在任何临时 share，也就不存在可读入口。
///    测试里用「查库为空」来断言，而不是靠注释承诺。
/// 3. **accept 生成 mode=offer 的临时 share**：isEphemeral=true、
///    expiresAt=now+offerShareTtl、凭证 sub 精确到接收方。
/// 4. **reject 带理由**：理由存进 filesJson 的 envelope（契约无独立列），
///    发起方通过 findOffer 读回时能看到。
/// 5. **decision ttl 到期自动过期**：任何读取路径都先经 [_settleExpiry]，
///    把超期的 pending 落成 expired 并落库；时间源可注入，测试不 sleep。
/// 6. **完成后撤销**：revokeOffer 立刻让临时 share 不可读（revokedAt 置位）。
/// 7. **watchIncoming 只吐本机 pending**：按 toPeer 过滤 + 每次广播前先结算过期。
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../contracts/contracts.dart';
import '../files/relative_path_codec.dart';
import 'offer_codec.dart';
import 'temp_share_factory.dart';

/// 把 offer 投递到对端的能力。
///
/// 为什么做成窄接口而不是内置 HTTP 客户端：
/// - 传输拓扑（端口顺延、网关跳转、中继）属于发现/网络层，
///   塞进 offer 服务会把两层耦死；
/// - 测试可以注入一个真实在跑的投递器（同进程另一端），
///   既不是 mock 掉网络，也不需要真局域网；
/// - 组装层（assembly.dart）由 Lead 统一接线，本模块不擅自定义全局单例。
abstract interface class OfferTransport {
  /// 对端是否可达；false 时 propose 直接抛 providerOffline。
  Future<bool> isReachable(PeerId peer);

  /// 投递 offer；失败抛 LanFileException。
  Future<void> deliver(Map<String, Object?> frame, {required PeerId toPeer});
}

/// 永远可达的传输：单机自测与「本机即对端」场景。
final class LoopbackOfferTransport implements OfferTransport {
  LoopbackOfferTransport();

  /// 收到的帧，供测试断言投递内容。
  final List<Map<String, Object?>> delivered = <Map<String, Object?>>[];

  @override
  Future<bool> isReachable(PeerId peer) async => true;

  @override
  Future<void> deliver(Map<String, Object?> frame, {required PeerId toPeer}) async {
    delivered.add(frame);
  }
}

/// 传输服务实现的依赖集合。
final class OfferServiceImpl implements OfferService {
  OfferServiceImpl({
    required this.store,
    required this.identity,
    required this.codec,
    required OfferTransport transport,
    TempShareFactory? tempShareFactory,
    DateTime Function()? clock,
    String Function()? offerIdGenerator,
  // ignore: prefer_initializing_formals — 字段私有，不能作为公开构造的初始化形参
  })  : _transport = transport,
        _clock = clock ?? DateTime.now,
        _offerIdGenerator = offerIdGenerator ?? _defaultOfferId,
        _tempShares = tempShareFactory ??
            TempShareFactory(
              ownerPeerId: identity.peerId,
              clock: clock,
            );

  final LanFileStore store;
  final DeviceIdentity identity;
  final CapabilityCodec codec;
  final OfferTransport _transport;
  final TempShareFactory _tempShares;
  final DateTime Function() _clock;
  final String Function() _offerIdGenerator;

  final StreamController<List<OfferView>> _incoming =
      StreamController<List<OfferView>>.broadcast();

  /// 由 accept 建立、可被 revokeOffer 撤销的临时 share，键为 offerId。
  final Map<String, ShareId> _tempShareByOffer = <String, ShareId>{};

  bool _disposed = false;

  /// 本机发起的 offer，供发起方回读决策结果（诊断与 UI 用）。
  Future<List<OfferView>> outgoing() async {
    final List<ThreadRecord> _ = await store.listThreads();
    final Set<String> seen = <String>{};
    final List<OfferView> views = <OfferView>[];
    // 契约没有 listOffers；用「已知 id」集合逐个 findOffer。
    // 这里维护的是本进程内发起过的 id，足以支撑 UI 与测试。
    for (final String id in _proposedIds) {
      final OfferRecord? record = await store.findOffer(id);
      if (record == null) continue;
      await _settleExpiry(record);
      final OfferRecord? fresh = await store.findOffer(id);
      if (fresh == null || !seen.add(id)) continue;
      views.add(await _toView(fresh));
    }
    return views;
  }

  /// 本进程内发起过的 offer id（按时间顺序）。
  final List<String> _proposedIds = <String>[];

  // ------------------------------------------------------------ 发起方 API

  @override
  Future<String> propose({
    required PeerId toPeer,
    required List<String> localPaths,
    String? note,
  }) async {
    if (localPaths.isEmpty) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        'offer 至少要包含一个文件',
      );
    }
    if (toPeer == identity.peerId) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        '不能向自己发起 offer',
      );
    }

    // 对端离线：直接失败，不排队。排队会让发送方误以为已送达。
    final bool reachable = await _transport.isReachable(toPeer);
    if (!reachable) {
      throw LanFileException(
        LanFileErrorCode.providerOffline,
        '对方当前不在线，无法发送 offer: ${toPeer.value}',
      );
    }

    // 只读元数据：不打开内容，不读任何字节。
    final List<OfferFile> files = <OfferFile>[];
    for (final String path in localPaths) {
      files.add(await _describeLocalFile(path));
    }

    final DateTime now = _clock().toUtc();
    final DateTime expireAt = now.add(LanFileConstants.offerDecisionTtl);
    final String offerId = _offerIdGenerator();
    final OfferEnvelope envelope = OfferEnvelope(files: files);

    await store.putOffer(OfferRecord(
      id: offerId,
      origin: OfferOrigin.peer,
      fromPeer: identity.peerId,
      toPeer: toPeer,
      filesJson: envelope.encode(),
      sizeTotal: envelope.sizeTotal,
      status: OfferStatusWire.pending,
      createdAt: now,
      expireAt: expireAt,
      note: note,
      decidedAt: null,
    ));
    _proposedIds.add(offerId);

    await _transport.deliver(
      encodeProposeFrame(
        offerId: offerId,
        fromPeer: identity.peerId,
        toPeer: toPeer,
        files: files,
        createdAt: now,
        expireAt: expireAt,
        note: note,
      ),
      toPeer: toPeer,
    );
    await _broadcastIncoming();
    return offerId;
  }

  /// 读一个本地路径的元数据（name/size/mime），**不打开内容**。
  ///
  /// 只做 stat：`File.lengthSync` 一类调用只取元数据，不读字节。
  /// 路径处理一律走 toIoPath，复用桌面 FileRef 的长路径与规范化逻辑，
  /// 不在这里另起一套（否则 Windows 超长路径会在这里单独炸）。
  Future<OfferFile> _describeLocalFile(String path) async {
    final String plain = stripExtendedPrefix(path);
    if (!p.isAbsolute(plain)) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        'offer 的本地路径必须是绝对路径: $path',
      );
    }
    final String normalized = p.normalize(plain);
    final FileSystemEntityType type =
        FileSystemEntity.typeSync(toIoPath(normalized), followLinks: true);
    if (type == FileSystemEntityType.notFound) {
      throw LanFileException(
        LanFileErrorCode.notFound,
        '要发送的路径不存在: $normalized',
      );
    }
    final bool isDir = type == FileSystemEntityType.directory;
    final int size;
    if (isDir) {
      // 目录本身不占「传输字节」：真正的大小由接收方逐项拉取时再算。
      size = 0;
    } else {
      size = await File(toIoPath(normalized)).length();
    }
    return OfferFile(
      // itemKey 对目录用其绝对路径：接收方按它请求内容，发起方据此定位。
      itemKey: normalized,
      name: p.basename(normalized),
      size: size,
      mime: isDir ? null : _guessMime(normalized),
      isDir: isDir,
    );
  }

  /// 按扩展名猜 MIME；猜不出给 null 而不是编一个。
  static String? _guessMime(String absolutePath) {
    final String ext = p.extension(absolutePath).toLowerCase();
    switch (ext) {
      case '.txt':
      case '.log':
        return 'text/plain';
      case '.json':
        return 'application/json';
      case '.html':
      case '.htm':
        return 'text/html';
      case '.css':
        return 'text/css';
      case '.js':
        return 'text/javascript';
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.pdf':
        return 'application/pdf';
      case '.zip':
        return 'application/zip';
      case '.mp4':
        return 'video/mp4';
      case '.mp3':
        return 'audio/mpeg';
      default:
        return null;
    }
  }

  // ------------------------------------------------------------ 接收方 API

  @override
  Stream<List<OfferView>> watchIncoming() async* {
    yield await _pendingViewsFor(identity.peerId);
    yield* _incoming.stream;
  }

  @override
  Future<ShareRecord> accept(String offerId) async {
    final OfferRecord record = await _requireOffer(offerId);
    await _settleExpiry(record);
    final OfferRecord fresh = await _requireOffer(offerId);
    if (fresh.status != OfferStatusWire.pending) {
      throw LanFileException(
        fresh.status == OfferStatusWire.expired
            ? LanFileErrorCode.expired
            : LanFileErrorCode.conflict,
        '该 offer 已不可接受（当前状态 ${fresh.status.value}）: $offerId',
      );
    }
    if (fresh.toPeer != identity.peerId) {
      throw const LanFileException(
        LanFileErrorCode.accessDenied,
        '只有接收方可以接受这个 offer',
      );
    }

    final OfferEnvelope envelope = OfferEnvelope.decode(fresh.filesJson);
    final PeerId issuer = fresh.fromPeer ?? identity.peerId;

    // 生成临时 share：这一刻之前库里没有它，因此「接受前零字节」成立。
    final ShareRecord share = _tempShares.create(
      offerId: offerId,
      files: envelope.files,
      acceptedBy: identity.peerId,
    );
    await store.upsertShare(share);
    _tempShareByOffer[offerId] = share.id;

    // 凭证：sub 精确到接收方，别的主体拿到链接也读不了。
    final CapabilityGrant grant = _tempShares.grantFor(
      share: share,
      subject: identity.peerId,
      issuer: issuer,
      tokenId: 'o_$offerId',
    );
    // 只有本机是该 share 的 issuer 时才能本地签；否则由发起方签。
    String? token;
    if (grant.issuer == identity.peerId) {
      token = await codec.issue(grant);
      await store.upsertShare(
        _copyShare(share, revokedAt: null),
      );
    }

    await store.putOffer(_copyOffer(
      fresh,
      status: OfferStatusWire.accepted,
      decidedAt: _clock().toUtc(),
    ));
    await _broadcastIncoming();

    if (token != null) {
      await _transport.deliver(
        encodeDecisionFrame(
          offerId: offerId,
          accepted: true,
          shareId: share.id.value,
          token: token,
        ),
        toPeer: issuer,
      );
    }
    return share;
  }

  @override
  Future<void> reject(String offerId, {String? reason}) async {
    final OfferRecord record = await _requireOffer(offerId);
    await _settleExpiry(record);
    final OfferRecord fresh = await _requireOffer(offerId);
    if (fresh.status != OfferStatusWire.pending) {
      throw LanFileException(
        LanFileErrorCode.conflict,
        '该 offer 已不可拒绝（当前状态 ${fresh.status.value}）: $offerId',
      );
    }
    if (fresh.toPeer != identity.peerId) {
      throw const LanFileException(
        LanFileErrorCode.accessDenied,
        '只有接收方可以拒绝这个 offer',
      );
    }

    // 理由必须能被发起方读回：存进 envelope（契约无独立列）。
    final OfferEnvelope envelope =
        OfferEnvelope.decode(fresh.filesJson).withRejectReason(reason);
    await store.putOffer(_copyOffer(
      fresh,
      status: OfferStatusWire.rejected,
      decidedAt: _clock().toUtc(),
      filesJson: envelope.encode(),
    ));

    final PeerId? from = fresh.fromPeer;
    if (from != null && await _transport.isReachable(from)) {
      await _transport.deliver(
        encodeDecisionFrame(
          offerId: offerId,
          accepted: false,
          reason: reason,
        ),
        toPeer: from,
      );
    }
    await _broadcastIncoming();
  }

  // ------------------------------------------------------------ 撤销与过期

  /// 接收方拉完后撤销：临时 share 立即不可读（任务要求第 6 条）。
  Future<void> revokeOffer(String offerId) async {
    final OfferRecord record = await _requireOffer(offerId);
    final DateTime now = _clock().toUtc();
    final ShareId? shareId = _tempShareByOffer[offerId];
    if (shareId != null) {
      await store.revokeShare(shareId, at: now);
    }
    await store.putOffer(_copyOffer(
      record,
      status: OfferStatusWire.cancelled,
      decidedAt: now,
    ));
    await _broadcastIncoming();
  }

  /// 判断某 offer 的临时分享在 [at] 时刻是否可读（供测试与传输层判定）。
  Future<bool> isTempShareReadable(String offerId, {DateTime? at}) async {
    // 先确认 offer 存在：不存在应该是 notFound，而不是静默返回 false。
    await _requireOffer(offerId);
    final ShareId? shareId = _tempShareByOffer[offerId];
    if (shareId == null) {
      // 还没 accept：库中不存在临时 share，因此不可读（零字节承诺）。
      return false;
    }
    final ShareRecord? share = await store.findShare(shareId);
    if (share == null) return false;
    return isReadableAt(share, at ?? _clock().toUtc());
  }

  /// 找出某 offer 对应的临时 share（未 accept 时为 null）。
  Future<ShareRecord?> tempShareOf(String offerId) async {
    await _requireOffer(offerId);
    final ShareId? shareId = _tempShareByOffer[offerId];
    if (shareId == null) return null;
    return store.findShare(shareId);
  }

  /// 把超期的 pending 落成 expired 并写库。
  ///
  /// 每条读路径都先过这里：否则「过期」只存在于内存判断里，
  /// 重启后一条早就该过期的 offer 会复活成 pending。
  Future<void> _settleExpiry(OfferRecord record) async {
    if (record.status != OfferStatusWire.pending) return;
    final DateTime now = _clock().toUtc();
    if (now.isBefore(record.expireAt.toUtc())) return;
    await store.putOffer(_copyOffer(
      record,
      status: OfferStatusWire.expired,
      decidedAt: now,
    ));
  }

  // ---------------------------------------------------------- 入站帧

  /// 收到对端的 propose 帧：落库为 pending，并推给本机 UI。
  ///
  /// 由 HTTP 接收侧路由调用。**只落元数据**，不碰任何文件内容——
  /// 「接受前零字节」在接收侧同样成立。
  Future<void> receiveProposeFrame(Map<String, Object?> frame) async {
    final String offerId = _requireStr(frame, 'offerId');
    final String fromRaw = _requireStr(frame, 'from');
    final String toRaw = _requireStr(frame, 'to');
    final PeerId from = PeerId.tryParse(fromRaw) ??
        (throw LanFileException(
          LanFileErrorCode.invalidArgument,
          'propose 帧的 from 不是合法 peerId',
        ));
    final PeerId to = PeerId.tryParse(toRaw) ??
        (throw LanFileException(
          LanFileErrorCode.invalidArgument,
          'propose 帧的 to 不是合法 peerId',
        ));
    // 只接受发给本机的 offer，其余按 invalidArgument 拒绝（不静默丢弃）。
    if (to != identity.peerId) {
      throw LanFileException(
        LanFileErrorCode.accessDenied,
        '这条 offer 不是发给本机的：${to.value}',
      );
    }
    final List<OfferFile> files = decodeFrameFilesSafe(frame);
    final DateTime now = _clock().toUtc();
    final int expireMs = _requireInt(frame, 'expireAt');
    final OfferEnvelope envelope = OfferEnvelope(files: files);

    await store.putOffer(OfferRecord(
      id: offerId,
      origin: OfferOrigin.peer,
      fromPeer: from,
      toPeer: to,
      filesJson: envelope.encode(),
      sizeTotal: envelope.sizeTotal,
      status: OfferStatusWire.pending,
      createdAt: now,
      expireAt: DateTime.fromMillisecondsSinceEpoch(expireMs, isUtc: true),
      note: frame['note'] as String?,
      decidedAt: null,
    ));
    await _broadcastIncoming();
  }

  /// 收到对端的决策帧：把本机发起的 offer 置为 accepted / rejected。
  Future<void> receiveDecisionFrame(
    String offerId,
    Map<String, Object?> frame,
  ) async {
    final OfferRecord? record = await store.findOffer(offerId);
    if (record == null) {
      throw LanFileException(
        LanFileErrorCode.notFound,
        '没有这条 offer: $offerId',
      );
    }
    final Object? acceptedRaw = frame['accepted'];
    if (acceptedRaw is! bool) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        '决策帧缺少 accepted 布尔字段',
      );
    }
    final DateTime now = _clock().toUtc();
    // 契约的 OfferRecord 没有 rejectReason 列，理由随 envelope 存进 filesJson
    // （这是本模块文档里写明的契约缺口规避方式）。
    final OfferEnvelope env = OfferEnvelope.decode(record.filesJson);
    final OfferEnvelope withReason = acceptedRaw
        ? env
        : env.withRejectReason(frame['reason'] as String?);
    await store.putOffer(_copyOffer(
      record,
      status: acceptedRaw ? OfferStatusWire.accepted : OfferStatusWire.rejected,
      decidedAt: now,
      filesJson: withReason.encode(),
    ));
    await _broadcastIncoming();
  }

  String _requireStr(Map<String, Object?> m, String key) {
    final Object? v = m[key];
    if (v is! String || v.isEmpty) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '帧缺少字段: $key',
      );
    }
    return v;
  }

  int _requireInt(Map<String, Object?> m, String key) {
    final Object? v = m[key];
    if (v is! int) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '帧字段不是整数: $key',
      );
    }
    return v;
  }

  // ---------------------------------------------------------------- 内部

  Future<List<OfferView>> _pendingViewsFor(PeerId toPeer) async {
    final List<OfferRecord> pending =
        await store.listPendingOffers(toPeer);
    final List<OfferView> views = <OfferView>[];
    for (final OfferRecord record in pending) {
      await _settleExpiry(record);
      final OfferRecord? fresh = await store.findOffer(record.id);
      if (fresh == null || fresh.status != OfferStatusWire.pending) continue;
      views.add(await _toView(fresh));
    }
    return views;
  }

  Future<void> _broadcastIncoming() async {
    if (_disposed || _incoming.isClosed) return;
    _incoming.add(await _pendingViewsFor(identity.peerId));
  }

  Future<OfferView> _toView(OfferRecord record) async {
    final OfferEnvelope envelope = OfferEnvelope.decode(record.filesJson);
    return OfferView(
      id: record.id,
      fromLabel: record.fromPeer?.value ?? '网页访客',
      origin: record.origin,
      files: envelope.files
          .map((OfferFile f) => OfferViewFile(
                name: f.name,
                size: f.size,
                mime: f.mime,
              ))
          .toList(growable: false),
      sizeTotal: record.sizeTotal,
      createdAt: record.createdAt.toUtc(),
      expireAt: record.expireAt.toUtc(),
      status: record.status.value,
      note: record.note,
    );
  }

  Future<OfferRecord> _requireOffer(String offerId) async {
    final OfferRecord? record = await store.findOffer(offerId);
    if (record == null) {
      throw LanFileException(
        LanFileErrorCode.notFound,
        'offer 不存在: $offerId',
      );
    }
    return record;
  }

  ShareRecord _copyShare(ShareRecord r, {DateTime? revokedAt}) => ShareRecord(
        id: r.id,
        kind: r.kind,
        rootKind: r.rootKind,
        rootUri: r.rootUri,
        displayName: r.displayName,
        ownerPeerId: r.ownerPeerId,
        createdAt: r.createdAt,
        mode: r.mode,
        enabled: r.enabled,
        missing: r.missing,
        isEphemeral: r.isEphemeral,
        expiresAt: r.expiresAt,
        passwordHash: r.passwordHash,
        groupId: r.groupId,
        maxSpeedKbps: r.maxSpeedKbps,
        revokedAt: revokedAt ?? r.revokedAt,
        sessionId: r.sessionId,
      );

  OfferRecord _copyOffer(
    OfferRecord r, {
    OfferStatusWire? status,
    DateTime? decidedAt,
    String? filesJson,
  }) =>
      OfferRecord(
        id: r.id,
        origin: r.origin,
        toPeer: r.toPeer,
        filesJson: filesJson ?? r.filesJson,
        sizeTotal: r.sizeTotal,
        status: status ?? r.status,
        createdAt: r.createdAt,
        expireAt: r.expireAt,
        fromPeer: r.fromPeer,
        fromSession: r.fromSession,
        note: r.note,
        decidedAt: decidedAt ?? r.decidedAt,
      );

  /// 释放；之后不再广播。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (!_incoming.isClosed) await _incoming.close();
  }

  static String _defaultOfferId() {
    final String stamp =
        DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36);
    return 'f_$stamp';
  }
}

/// 从 propose 帧里解出文件元数据。
///
/// 放在类外是为了让 HTTP 接收侧也能复用；缺字段一律拒绝而不是补默认值
/// （默认值会让「对端发来残缺 offer」变成静默接受一条信息不全的请求）。
List<OfferFile> decodeFrameFilesSafe(Map<String, Object?> frame) {
  final Object? raw = frame['files'];
  if (raw is! List<Object?>) {
    throw const LanFileException(
      LanFileErrorCode.invalidArgument,
      'offer 帧缺少 files 数组',
    );
  }
  final List<OfferFile> out = <OfferFile>[];
  for (final Object? item in raw) {
    if (item is! Map<String, Object?>) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        'offer 帧的 files 项不是对象',
      );
    }
    out.add(OfferFile.fromJson(item));
  }
  return out;
}