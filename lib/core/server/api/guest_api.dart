// SPDX-License-Identifier: GPL-3.0-only

/// /w/ 系列路由：guest 握手、心跳、受权上传、会话结束上报。
///
/// 路由只负责 HTTP 形状（解析、状态码、JSON），业务判定全部落在
/// WebShareServiceImpl。**上传接口的 403 来自授权层，不在这里手写判断**，
/// 这样「接受前零字节」只有唯一一处实现。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/webshare/guest_session_registry.dart';
import 'package:lan_simple_file/core/webshare/web_share_service_impl.dart';

import '../response.dart';
import '../router.dart';
import '../static/static_handler.dart';

/// guest 页面模板在 assets/web 下的路径。
const String kGuestPageAsset = 'guest.html';

/// 握手请求体上限：只有一个小公钥。
const int kMaxHandshakeBodyBytes = 8 * 1024;

/// 分片请求体上限：契约分片 4MB，留一倍余量。
const int kMaxChunkBodyBytes = LanFileConstants.rangeChunkBytes * 2;

/// 会话 id 段长上限。
const int kMaxGuestSegmentLength = 64;

/// 把 /w/ 路由注册到 [router] 上。
///
/// [service] 为 null 时（网页会话功能未启用）所有 /w/ 接口一律 503，
/// 而不是 404——前者说明「功能存在但未就绪」，后者会误导成路由写错。
void registerGuestRoutes(
  Router router, {
  required WebShareServiceImpl? service,
  StaticAssetSource? templates,
}) {
  router.get('/w/guest', guestPageHandler(templates));
  router.post('/w/session', handshakeHandler(service));
  router.post('/w/session/:id/beat', heartbeatHandler(service));
  router.post(
    '/w/session/:id/close',
    sessionCloseHandler(service),
  );
  router.post('/w/session/:id/revoke', revokeHandler(service));
  router.post(
    '/w/session/:id/upload/:uploadId',
    uploadChunkHandler(service),
  );
  router.post(
    '/w/session/:id/upload/:uploadId/finish',
    uploadFinishHandler(service),
  );
}

/// 未启用网页会话时的统一响应。
WebShareServiceImpl _requireService(WebShareServiceImpl? service) {
  if (service == null) {
    throw const LanFileException(
      LanFileErrorCode.providerOffline,
      '网页会话分享未启用',
    );
  }
  return service;
}

/// GET /w/guest：guest 页面。
Handler guestPageHandler(StaticAssetSource? templates) {
  return (HttpRequest request) async {
    final StaticAssetSource? source = templates;
    if (source == null) {
      throw const LanFileException(
        LanFileErrorCode.notFound,
        '缺少网页会话页面模板',
      );
    }
    final Uint8List? bytes = await source.load(kGuestPageAsset);
    if (bytes == null) {
      throw LanFileException(
        LanFileErrorCode.notFound,
        '缺少页面模板: $kGuestPageAsset',
      );
    }
    final HttpResponse response = request.response;
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.html;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.contentLength = bytes.length;
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }
    response.add(bytes);
    await response.close();
  };
}

/// POST /w/session  body {"pubkey": "..."}
Handler handshakeHandler(WebShareServiceImpl? service) {
  return (HttpRequest request) async {
    final WebShareServiceImpl impl = _requireService(service);
    final Map<String, Object?> body = await _readJson(request);
    final Object? pubkey = body['pubkey'];
    if (pubkey is! String) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        'pubkey 必须是字符串（base64url 编码的 ECDSA P-256 公钥）',
      );
    }
    final String sessionId = await impl.openSession(clientPubkey: pubkey);
    final GuestSession? session = impl.registry.find(sessionId);
    await jsonResponse(request.response, HttpStatus.ok, <String, Object?>{
      'guestSessionId': sessionId,
      'hostPeer': impl.hostPeer.value,
      'heartbeatSeconds': impl.registry.heartbeatInterval.inSeconds,
      'quotaBytes': session?.quotaBytes ?? impl.registry.quotaBytes,
      'gracePeriodSeconds': impl.registry.gracePeriod.inSeconds,
    });
  };
}

/// POST /w/session/:id/beat
Handler heartbeatHandler(WebShareServiceImpl? service) {
  return (HttpRequest request) async {
    final WebShareServiceImpl impl = _requireService(service);
    final String sessionId = _segment(request.uri, 3);
    final bool alive = await impl.heartbeat(sessionId);
    if (!alive) {
      // 心跳失败 = 会话已结束：按契约语义回 410，让页面立刻停止操作。
      throw const LanFileException(
        LanFileErrorCode.revoked,
        '会话已结束，心跳被拒',
      );
    }
    final GuestSession? session = impl.registry.find(sessionId);
    await jsonResponse(request.response, HttpStatus.ok, <String, Object?>{
      'ok': true,
      'usedBytes': session?.usedBytes ?? 0,
      'quotaBytes': session?.quotaBytes ?? 0,
    });
  };
}

/// POST /w/session/:id/close —— 页面 beforeunload / pagehide 上报。
Handler sessionCloseHandler(WebShareServiceImpl? service) {
  return (HttpRequest request) async {
    final WebShareServiceImpl impl = _requireService(service);
    final String sessionId = _segment(request.uri, 3);
    await impl.closeSession(sessionId);
    await jsonResponse(request.response, HttpStatus.ok, <String, Object?>{
      'ok': true,
      'reason': 'pageClosed',
    });
  };
}

/// POST /w/session/:id/revoke —— 显式撤销。
Handler revokeHandler(WebShareServiceImpl? service) {
  return (HttpRequest request) async {
    final WebShareServiceImpl impl = _requireService(service);
    final String sessionId = _segment(request.uri, 3);
    await impl.revokeSession(sessionId);
    await jsonResponse(request.response, HttpStatus.ok, <String, Object?>{
      'ok': true,
      'reason': 'explicitRevoke',
    });
  };
}

/// POST /w/session/:id/upload/:uploadId
///
/// 请求头：
///   X-LSF-Grant: 上传凭证（offer 被接受后才签发）
///   X-LSF-Offer: offer id
///   X-LSF-Name:  URL 编码的文件名
///   X-LSF-Size:  声明大小
///   X-LSF-Offset: 本片起始偏移
///
/// 缺少 grant 时一律 403，且**不会**在 staging 里创建任何目录或文件。
Handler uploadChunkHandler(WebShareServiceImpl? service) {
  return (HttpRequest request) async {
    final WebShareServiceImpl impl = _requireService(service);
    final String sessionId = _segment(request.uri, 3);
    final String uploadId = _segment(request.uri, 5);

    final String? grant = request.headers.value('x-lsf-grant');
    final String offerId = request.headers.value('x-lsf-offer') ?? '';
    final String rawName = request.headers.value('x-lsf-name') ?? '';
    final String fileName = _decodeHeaderName(rawName);
    final int declaredSize =
        int.tryParse(request.headers.value('x-lsf-size') ?? '') ?? -1;
    final int offset =
        int.tryParse(request.headers.value('x-lsf-offset') ?? '') ?? -1;

    if (grant == null || grant.isEmpty) {
      // 未授权：直接 403，不读 body、不碰磁盘。
      throw const LanFileException(
        LanFileErrorCode.accessDenied,
        '未获得接收方接受，拒绝上传',
        httpStatus: HttpStatus.forbidden,
      );
    }
    if (offerId.isEmpty || fileName.isEmpty || declaredSize < 0 || offset < 0) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        '缺少 X-LSF-Offer / X-LSF-Name / X-LSF-Size / X-LSF-Offset',
      );
    }

    final List<int> data = await _readBytes(request, kMaxChunkBodyBytes);

    await impl.beginAuthorizedUpload(
      sessionId: sessionId,
      offerId: offerId,
      fileName: fileName,
      declaredSize: declaredSize,
      token: grant,
      uploadId: uploadId,
    );
    final int written = await impl.writeChunk(
      sessionId: sessionId,
      uploadId: uploadId,
      offset: offset,
      data: data,
    );

    await jsonResponse(request.response, HttpStatus.ok, <String, Object?>{
      'received': written,
      'declaredSize': declaredSize,
    });
  };
}

/// POST /w/session/:id/upload/:uploadId/finish
Handler uploadFinishHandler(WebShareServiceImpl? service) {
  return (HttpRequest request) async {
    final WebShareServiceImpl impl = _requireService(service);
    final String sessionId = _segment(request.uri, 3);
    final String uploadId = _segment(request.uri, 5);
    final Map<String, Object?> body = await _readJson(request);
    final Object? name = body['displayName'];
    final ShareRecord record = await impl.completeUpload(
      sessionId: sessionId,
      uploadId: uploadId,
      displayName: name is String && name.isNotEmpty ? name : '网页访客的文件',
    );
    await jsonResponse(request.response, HttpStatus.ok, <String, Object?>{
      'shareId': record.id.value,
      'displayName': record.displayName,
      'mode': record.mode.name,
      'isEphemeral': record.isEphemeral,
      'sessionId': record.sessionId,
    });
  };
}

String _segment(Uri uri, int index) {
  final List<String> parts = uri.path.split('/');
  final String value = index < parts.length ? parts[index] : '';
  if (value.length > kMaxGuestSegmentLength) {
    throw const LanFileException(
      LanFileErrorCode.invalidArgument,
      '路径段过长',
    );
  }
  return value;
}

/// 头里的文件名是 percent-encoded（非 ASCII 名必须能过 HTTP 头）。
String _decodeHeaderName(String raw) {
  if (raw.isEmpty) return raw;
  try {
    return Uri.decodeComponent(raw);
  } on ArgumentError {
    throw const LanFileException(
      LanFileErrorCode.invalidArgument,
      'X-LSF-Name 不是合法的百分号编码',
    );
  }
}

Future<Map<String, Object?>> _readJson(HttpRequest request) async {
  final List<int> bytes = await _readBytes(request, kMaxHandshakeBodyBytes);
  if (bytes.isEmpty) {
    throw const LanFileException(
      LanFileErrorCode.invalidArgument,
      '请求体为空，需要 JSON 对象',
    );
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw const LanFileException(
      LanFileErrorCode.invalidArgument,
      '请求体不是合法 JSON',
    );
  }
  if (decoded is! Map<String, Object?>) {
    throw const LanFileException(
      LanFileErrorCode.invalidArgument,
      '请求体必须是 JSON 对象',
    );
  }
  return decoded;
}

/// 读请求体并限制大小；超限时先把剩余 body 排空再抛，原因见 M0 的 413 回归。
Future<List<int>> _readBytes(HttpRequest request, int maxBytes) async {
  final List<int> bytes = <int>[];
  bool exceeded = false;
  await for (final List<int> chunk in request) {
    if (exceeded) continue;
    bytes.addAll(chunk);
    if (bytes.length > maxBytes) {
      exceeded = true;
      bytes.clear();
    }
  }
  if (exceeded) {
    throw LanFileException(
      LanFileErrorCode.invalidArgument,
      '请求体超过 $maxBytes 字节上限',
      httpStatus: HttpStatus.requestEntityTooLarge,
    );
  }
  return bytes;
}