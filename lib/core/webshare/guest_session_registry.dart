// SPDX-License-Identifier: GPL-3.0-only

/// 网页访客会话登记表：会话、上传凭证、心跳缺拍判定。
///
/// 时间来源全部来自注入的 [GuestClock]，因此「停 2 拍」可以用推时钟验证，
/// 不需要 sleep。这是产品硬约束的测试前提。
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

import 'package:lan_simple_file/core/contracts/contracts.dart';

/// 可注入的时间源。
final class GuestClock {
  GuestClock({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  DateTime now() => _now();
}

/// 会话终止原因。
enum SessionEndReason {
  /// 页面 beforeunload / pagehide 主动上报。
  pageClosed,

  /// 心跳连续缺拍。
  heartbeatTimeout,

  /// 用户显式撤销。
  explicitRevoke,
}

/// 一次上传的授权凭证（一次性）。
final class UploadGrant {
  const UploadGrant({
    required this.token,
    required this.sessionId,
    required this.offerId,
    required this.fileName,
    required this.declaredSize,
    required this.expiresAt,
  });

  final String token;
  final String sessionId;
  final String offerId;
  final String fileName;
  final int declaredSize;
  final DateTime expiresAt;

  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);
}

/// 一个 guest 会话的运行时视图。
final class GuestSession {
  GuestSession({
    required this.sessionId,
    required this.hostPeer,
    required this.clientPubkey,
    required this.createdAt,
    required this.lastBeat,
    required this.quotaBytes,
    this.usedBytes = 0,
    this.revokedAt,
    this.endReason,
    this.missedBeats = 0,
    this.releasedAt,
  });

  final String sessionId;
  final PeerId hostPeer;

  /// 浏览器 WebCrypto 生成的 ECDSA P-256 公钥（base64url）。
  final String clientPubkey;
  final DateTime createdAt;
  DateTime lastBeat;
  final int quotaBytes;
  int usedBytes;

  /// 会话被判失效的时刻；非 null 即「已结束」。
  DateTime? revokedAt;
  SessionEndReason? endReason;

  /// 连续缺拍次数。
  int missedBeats;

  /// 宽限期结束、临时文件被真正删除的时刻。
  DateTime? releasedAt;

  bool get isEnded => revokedAt != null;

  /// 落到存储层的记录形态。
  GuestSessionRecord toRecord() => GuestSessionRecord(
    sessionId: sessionId,
    hostPeer: hostPeer,
    pubkey: _decodePubkey(clientPubkey),
    createdAt: createdAt,
    lastBeat: lastBeat,
    quotaBytes: quotaBytes,
    usedBytes: usedBytes,
    revokedAt: revokedAt,
  );

  static Uint8List _decodePubkey(String base64url) {
    final String normalized = base64url
        .replaceAll('-', '+')
        .replaceAll('_', '/');
    final int padding = (4 - normalized.length % 4) % 4;
    try {
      return Uint8List.fromList(base64.decode(normalized + '=' * padding));
    } on FormatException {
      return Uint8List(0);
    }
  }
}

/// 会话 + 凭证登记表。
final class GuestSessionRegistry {
  GuestSessionRegistry({
    required this.hostPeer,
    GuestClock? clock,
    this.quotaBytes = LanFileConstants.webShareQuotaBytes,
    this.gracePeriod = LanFileConstants.webShareGracePeriod,
    this.heartbeatInterval = LanFileConstants.guestHeartbeat,
    this.missedBeatsBeforeExpiry =
        LanFileConstants.guestMissedBeatsBeforeExpiry,
    Random? random,
    String Function()? sessionIdGenerator,
  }) : clock = clock ?? GuestClock(),
       _random = random ?? Random.secure(),
       _sessionIdGenerator = sessionIdGenerator; // ignore: prefer_initializing_formals

  final PeerId hostPeer;
  final GuestClock clock;
  final int quotaBytes;
  final Duration gracePeriod;
  final Duration heartbeatInterval;
  final int missedBeatsBeforeExpiry;
  final Random _random;
  final String Function()? _sessionIdGenerator;

  final Map<String, GuestSession> _sessions = <String, GuestSession>{};
  final Map<String, UploadGrant> _grants = <String, UploadGrant>{};

  /// 会话总数（含已结束的，便于断言清理行为）。
  int get sessionCount => _sessions.length;

  /// 已知会话 id，按创建顺序。
  List<String> get sessionIds => _sessions.keys.toList(growable: false);

  GuestSession? find(String sessionId) => _sessions[sessionId];

  /// 开一个会话。
  GuestSession openSession(String clientPubkey) {
    if (clientPubkey.trim().isEmpty) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        '握手必须携带 clientPubkey',
      );
    }
    final DateTime now = clock.now();
    final String sessionId = _sessionIdGenerator?.call() ?? _newSessionId();
    final GuestSession session = GuestSession(
      sessionId: sessionId,
      hostPeer: hostPeer,
      clientPubkey: clientPubkey.trim(),
      createdAt: now,
      lastBeat: now,
      quotaBytes: quotaBytes,
    );
    _sessions[sessionId] = session;
    return session;
  }

  String _newSessionId() {
    const String alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final StringBuffer buffer = StringBuffer('gs_');
    for (int i = 0; i < 20; i++) {
      buffer.write(alphabet[_random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }

  /// 心跳：会话不存在或已结束返回 false。
  bool heartbeat(String sessionId) {
    final GuestSession? session = _sessions[sessionId];
    if (session == null || session.isEnded) return false;
    session.lastBeat = clock.now();
    session.missedBeats = 0;
    return true;
  }

  /// 按当前时间推进缺拍判定；返回本次被判定结束的会话。
  ///
  /// 用「已过时长 ÷ 心跳间隔」算缺拍数而不是累加计数器：
  /// 即使进程在两次检查之间长时间没跑，判定依然正确。
  List<GuestSession> reapExpired() {
    final DateTime now = clock.now();
    final List<GuestSession> ended = <GuestSession>[];
    for (final GuestSession session in _sessions.values) {
      if (session.isEnded) continue;
      final Duration silent = now.difference(session.lastBeat);
      final int missed = silent.inMilliseconds ~/ heartbeatInterval.inMilliseconds;
      session.missedBeats = missed;
      if (missed >= missedBeatsBeforeExpiry) {
        session.revokedAt = now;
        session.endReason = SessionEndReason.heartbeatTimeout;
        ended.add(session);
      }
    }
    return ended;
  }

  /// 结束会话；重复调用幂等，不覆盖首次原因。
  GuestSession endSession(String sessionId, SessionEndReason reason) {
    final GuestSession? session = _sessions[sessionId];
    if (session == null) {
      throw LanFileException(
        LanFileErrorCode.notFound,
        '没有这个 guest 会话: $sessionId',
      );
    }
    if (!session.isEnded) {
      session.revokedAt = clock.now();
      session.endReason = reason;
    }
    // 会话一结束，它名下的上传凭证立即全部作废。
    _grants.removeWhere(
      (String _, UploadGrant grant) => grant.sessionId == sessionId,
    );
    return session;
  }

  /// 为一次**已被接受**的 offer 签发上传凭证。
  ///
  /// 这是「接受前零字节」的唯一授权来源：没有这里签出的 token，
  /// [consumeGrant] 必然拒绝，上传接口只能 403。
  UploadGrant grantUpload({
    required String sessionId,
    required String offerId,
    required String fileName,
    required int declaredSize,
  }) {
    final GuestSession? session = _sessions[sessionId];
    if (session == null) {
      throw LanFileException(
        LanFileErrorCode.notFound,
        '没有这个 guest 会话: $sessionId',
      );
    }
    if (session.isEnded) {
      throw LanFileException(
        LanFileErrorCode.revoked,
        '会话已结束（${session.endReason?.name ?? "unknown"}），不能再签发上传凭证',
      );
    }
    if (declaredSize < 0) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        '声明大小不能为负',
      );
    }
    final String token = _newGrantToken();
    final UploadGrant grant = UploadGrant(
      token: token,
      sessionId: sessionId,
      offerId: offerId,
      fileName: fileName,
      declaredSize: declaredSize,
      expiresAt: clock.now().add(LanFileConstants.offerShareTtl),
    );
    _grants[token] = grant;
    return grant;
  }

  String _newGrantToken() {
    final List<int> bytes = List<int>.generate(24, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// 校验上传凭证并消费它（一次性）。
  ///
  /// 任何一项不满足都抛对应错误，**绝不返回「宽松通过」**：
  /// - 会话不存在 → notFound
  /// - 会话已结束 → revoked（410）
  /// - token 不在表里（伪造/已用/未授权） → 403
  /// - 与目标文件不匹配 → 403
  /// - 已过期 → expired
  UploadGrant consumeGrant({
    required String token,
    required String sessionId,
    required String offerId,
    required String fileName,
  }) {
    final GuestSession? session = _sessions[sessionId];
    if (session == null) {
      throw LanFileException(
        LanFileErrorCode.notFound,
        '没有这个 guest 会话: $sessionId',
      );
    }
    if (session.isEnded) {
      throw const LanFileException(
        LanFileErrorCode.revoked,
        '会话已结束，上传被拒',
      );
    }
    final UploadGrant? grant = _grants[token];
    if (grant == null) {
      // 这一分支就是「接受前零字节」的闸门：没被 accept 过就没有 grant。
      throw const LanFileException(
        LanFileErrorCode.accessDenied,
        '上传凭证无效、未授权或已被使用',
        httpStatus: 403,
      );
    }
    if (grant.sessionId != sessionId ||
        grant.offerId != offerId ||
        grant.fileName != fileName) {
      throw const LanFileException(
        LanFileErrorCode.accessDenied,
        '上传凭证与目标文件不匹配',
        httpStatus: 403,
      );
    }
    if (grant.isExpiredAt(clock.now())) {
      throw const LanFileException(
        LanFileErrorCode.expired,
        '上传凭证已过期',
      );
    }
    _grants.remove(token);
    return grant;
  }

  /// 已签发但未消费的凭证数量（诊断用）。
  int get pendingGrantCount => _grants.length;

  /// 宽限期已过、可以真正删文件的会话。
  List<GuestSession> releasable() {
    final DateTime now = clock.now();
    return _sessions.values
        .where(
          (GuestSession s) =>
              s.isEnded &&
              s.releasedAt == null &&
              now.difference(s.revokedAt!) >= gracePeriod,
        )
        .toList(growable: false);
  }

  /// 标记某会话的临时文件已释放。
  void markReleased(String sessionId) {
    _sessions[sessionId]?.releasedAt = clock.now();
  }

  /// 该会话是否应当拒绝一切读写（已结束即拒）。
  bool isUsable(String sessionId) {
    final GuestSession? session = _sessions[sessionId];
    return session != null && !session.isEnded;
  }

  /// 累计用量记账（上传落盘后调用）。
  void accountUsed(String sessionId, int bytes) {
    final GuestSession? session = _sessions[sessionId];
    if (session == null) return;
    session.usedBytes += bytes;
  }
}