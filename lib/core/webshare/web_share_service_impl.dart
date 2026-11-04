// SPDX-License-Identifier: GPL-3.0-only

/// WebShareService 实现：guest 握手 + 心跳 + 受权上传 + 会话失效回收。
///
/// 四条产品硬约束在这里落地：
/// 1. **接受前零字节**：上传必须先拿到 [UploadGrant]，它只由
///    [acknowledgeAcceptedOffer] 在 offer 被接受后签发；没有 grant 一律 403，
///    且 [beginUpload] 之前不创建任何文件。
/// 2. **会话即生命周期**：心跳缺拍 / 页面关闭 / 显式撤销 → share 立即 revoked，
///    链接 410；磁盘文件要等宽限期后才由 [SessionSweeper] 删除。
/// 3. 配额按会话累计，超额 507。
/// 4. 时间全部可注入，测试推时钟即可，不 sleep。
library;

import 'dart:typed_data';

import 'package:lan_simple_file/core/contracts/contracts.dart';

import 'guest_session_registry.dart';
import 'session_sweeper.dart';
import 'staging_area.dart';

/// 一次上传的会话内登记。
final class UploadTicket {
  UploadTicket({
    required this.upload,
    required this.grant,
  });

  final StagingUpload upload;
  final UploadGrant grant;
  int written = 0;
}

/// 网页会话分享服务。
final class WebShareServiceImpl implements WebShareService {
  WebShareServiceImpl({
    required this.registry,
    required this.staging,
    required this.sweeper,
    required this.store,
    required this.hostPeer,
    this.idGenerator,
    this.revokedChecker,
  });

  final GuestSessionRegistry registry;
  final StagingArea staging;
  final SessionSweeper sweeper;
  final LanFileStore store;
  final PeerId hostPeer;

  /// 分享 id 生成器；测试固定后便于断言。
  final String Function()? idGenerator;

  /// 链接准入：给定 shareId 判断是否仍然可读（410 判定）。
  ///
  /// 由组装层注入（真正实现在 share_guard / share_api 一侧）。
  /// 为 null 时本服务不参与可读性判定。
  final Future<bool> Function(ShareId id)? revokedChecker;

  final Map<String, UploadTicket> _tickets = <String, UploadTicket>{};
  final Map<String, List<String>> _sharesBySession =
      <String, List<String>>{};
  int _seq = 0;

  /// 某会话名下的临时 share id 列表（诊断与清理用）。
  List<String> sharesOf(String sessionId) =>
      List<String>.unmodifiable(_sharesBySession[sessionId] ?? const <String>[]);

  /// 当前悬挂的上传 ticket 数（授权后未完成的上传）。
  int get pendingTicketCount => _tickets.length;

  @override
  Future<String> openSession({required String clientPubkey}) async {
    final GuestSession session = registry.openSession(clientPubkey);
    // 握手即落库：guest 会话必须能在重启后被识别为「已结束」而不是不存在。
    await store.putGuestSession(session.toRecord());
    return session.sessionId;
  }

  @override
  Future<bool> heartbeat(String sessionId) async {
    final bool alive = registry.heartbeat(sessionId);
    if (!alive) return false;
    final GuestSession? session = registry.find(sessionId);
    if (session != null) {
      await store.putGuestSession(session.toRecord());
    }
    return true;
  }

  @override
  Future<void> revokeSession(String sessionId) async {
    registry.endSession(sessionId, SessionEndReason.explicitRevoke);
    await _revokeSharesOf(sessionId);
  }

  /// 页面 beforeunload / pagehide 主动上报：与显式撤销同一后果，
  /// 但原因记为 pageClosed，便于诊断「是谁结束的会话」。
  Future<void> closeSession(String sessionId) async {
    registry.endSession(sessionId, SessionEndReason.pageClosed);
    await _revokeSharesOf(sessionId);
  }

  /// offer 被目标 peer 接受后调用：签发一次性上传凭证。
  ///
  /// **这是唯一能让上传接口放行的入口。** 未经此步，
  /// [beginAuthorizedUpload] 必然抛 403，并且不会创建任何目录或文件。
  UploadGrant acknowledgeAcceptedOffer({
    required String sessionId,
    required String offerId,
    required String fileName,
    required int declaredSize,
  }) {
    return registry.grantUpload(
      sessionId: sessionId,
      offerId: offerId,
      fileName: fileName,
      declaredSize: declaredSize,
    );
  }

  /// 校验凭证并准备落点。
  ///
  /// 顺序刻意是「先验授权、后建目录」：一旦顺序反过来，
  /// 未授权请求就会在磁盘上留下空目录，「零字节」承诺即被破坏。
  Future<UploadTicket> beginAuthorizedUpload({
    required String sessionId,
    required String offerId,
    required String fileName,
    required int declaredSize,
    required String token,
    required String uploadId,
  }) async {
    final UploadGrant grant = registry.consumeGrant(
      token: token,
      sessionId: sessionId,
      offerId: offerId,
      fileName: fileName,
    );
    final StagingUpload upload = await staging.beginUpload(
      sessionId: sessionId,
      uploadId: uploadId,
      fileName: fileName,
      declaredSize: declaredSize,
    );
    final UploadTicket ticket = UploadTicket(upload: upload, grant: grant);
    _tickets[uploadId] = ticket;
    return ticket;
  }

  /// 写一个分片。
  Future<int> writeChunk({
    required String sessionId,
    required String uploadId,
    required int offset,
    required List<int> data,
  }) async {
    if (!registry.isUsable(sessionId)) {
      throw const LanFileException(
        LanFileErrorCode.revoked,
        '会话已结束，拒绝写入',
      );
    }
    final UploadTicket? ticket = _tickets[uploadId];
    if (ticket == null) {
      throw const LanFileException(
        LanFileErrorCode.accessDenied,
        '上传未授权或已结束',
        httpStatus: 403,
      );
    }
    final int now = await staging.writeChunk(
      upload: ticket.upload,
      offset: offset,
      data: data,
      expectedTotal: ticket.grant.declaredSize,
    );
    ticket.written = now > ticket.written ? now : ticket.written;
    return ticket.written;
  }

  /// 把已完成的上传落成 mode=session 的临时 share。
  Future<ShareRecord> completeUpload({
    required String sessionId,
    required String uploadId,
    required String displayName,
  }) async {
    final UploadTicket? ticket = _tickets[uploadId];
    if (ticket == null) {
      throw const LanFileException(
        LanFileErrorCode.accessDenied,
        '上传未授权或已结束',
        httpStatus: 403,
      );
    }
    if (ticket.written < ticket.grant.declaredSize) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '上传未完成：已写 ${ticket.written} / ${ticket.grant.declaredSize}',
      );
    }
    registry.accountUsed(sessionId, ticket.written);
    final ShareRecord record = await _registerSessionShare(
      sessionId: sessionId,
      rootUri: ticket.upload.directory,
      displayName: displayName,
      kind: 'file',
    );
    _tickets.remove(uploadId);
    return record;
  }

  @override
  Future<ShareRecord> acceptUpload(
    String sessionId,
    OfferView offer,
    FileRef stagingRoot,
  ) async {
    // 契约入口：把已接受的 offer 直接登记为临时 share。
    // 真实字节写入走 beginAuthorizedUpload / writeChunk / completeUpload，
    // 这里只负责「登记 + 绑定会话」，不复制文件。
    final String rootUri = stagingRoot.itemKey.value;
    return _registerSessionShare(
      sessionId: sessionId,
      rootUri: rootUri,
      displayName: offer.fromLabel.isEmpty ? '网页访客' : offer.fromLabel,
      kind: 'folder',
    );
  }

  Future<ShareRecord> _registerSessionShare({
    required String sessionId,
    required String rootUri,
    required String displayName,
    required String kind,
  }) async {
    if (!registry.isUsable(sessionId)) {
      throw const LanFileException(
        LanFileErrorCode.revoked,
        '会话已结束，不能再登记临时分享',
      );
    }
    final GuestSession? session = registry.find(sessionId);
    if (session == null) {
      throw LanFileException(
        LanFileErrorCode.notFound,
        '没有这个 guest 会话: $sessionId',
      );
    }
    _seq++;
    final String id =
        idGenerator?.call() ?? 'ws${_seq.toString().padLeft(6, '0')}';
    final ShareRecord record = ShareRecord(
      id: ShareId.parse(id),
      kind: kind,
      rootKind: 'localPath',
      rootUri: rootUri,
      displayName: displayName,
      ownerPeerId: hostPeer,
      createdAt: registry.clock.now(),
      mode: ShareMode.session,
      enabled: true,
      missing: false,
      isEphemeral: true,
      expiresAt: registry.clock.now().add(LanFileConstants.offerShareTtl),
      sessionId: sessionId,
    );
    await store.upsertShare(record);
    (_sharesBySession[sessionId] ??= <String>[]).add(id);
    return record;
  }

  /// 会话结束时撤销其名下全部 share（立即 410）。
  Future<List<String>> _revokeSharesOf(String sessionId) async {
    final List<String> ids = _sharesBySession[sessionId] ?? <String>[];
    final DateTime now = registry.clock.now();
    for (final String id in ids) {
      await store.revokeShare(ShareId.parse(id), at: now);
    }
    return ids;
  }

  /// 链接是否仍然可读；已结束会话 → false（调用方据此回 410）。
  Future<bool> isLinkReadable(ShareId id) async {
    final Future<bool> Function(ShareId id)? checker = revokedChecker;
    if (checker != null) return checker(id);
    final ShareRecord? record = await store.findShare(id);
    return record != null && record.enabled && record.revokedAt == null;
  }

  /// 跑一轮回收（心跳超时 + 宽限期删除）。
  Future<SweepResult> sweep() => sweeper.sweep();

  /// 释放所有句柄（测试收尾用；不删文件）。
  Future<void> dispose() async {
    _tickets.clear();
  }

  /// 该会话的临时区目录是否还存在（测试断言「10 分钟后真的消失」）。
  Future<bool> hasStagingResidue(String sessionId) =>
      staging.hasResidue(sessionId);

  /// 浏览器手的公钥字节（诊断用）。
  Uint8List? clientPubkeyOf(String sessionId) {
    final GuestSession? session = registry.find(sessionId);
    return session?.toRecord().pubkey;
  }
}