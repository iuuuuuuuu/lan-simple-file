// SPDX-License-Identifier: GPL-3.0-only

/// WS 服务端端点：把 dart:io 的 HttpRequest 升级成 WebSocket，并接纳链路。
///
/// 只负责升级与注册链路，业务语义在 messaging_service_impl。
/// 这样 HTTP 层与消息层可各自测试：本文件单测「非 WS 请求被拒绝」，
/// 消息语义单测纯逻辑，互不牵连。
library;

import 'dart:io';
import 'dart:async';

import '../contracts/contracts.dart';
import '../server/response.dart';
import 'ws_hub.dart';

/// WS 的路径。
const String kWsPath = '/ws';

/// WebSocket 升级被接受后的回调。
typedef WsUpgradeHandler = Future<void> Function(WsLink link);

/// 把 `/ws` 的 [HttpRequest] 升级为 WebSocket 并交给 [onUpgrade]。
///
/// 非升级请求返回 400 JSON 错误体，而不是留下 101 半开——
/// 让误用 WS 路径的普通 GET 得到可读原因。
Future<void> handleWsRequest(
  HttpRequest request,
  WsUpgradeHandler onUpgrade, {
  required PeerId localPeerId,
  required String localName,
  required String localAvatarHash,
  required Set<String> localCapabilities,
  Future<PeerId?> Function(HttpRequest)? authenticate,
}) async {
  if (request.uri.path != kWsPath) {
    await errorResponse(
      request.response,
      LanFileException(
        LanFileErrorCode.notFound,
        '没有这个 WS 端点: ${request.uri.path}',
      ),
    );
    return;
  }
  if (!WebSocketTransformer.isUpgradeRequest(request)) {
    await errorResponse(
      request.response,
      const LanFileException(
        LanFileErrorCode.invalidArgument,
        '该路径只接受 WebSocket 升级请求',
      ),
    );
    return;
  }

  final PeerId? authenticatedPeer = await authenticate?.call(request);
  if (authenticate != null && authenticatedPeer == null) {
    await errorResponse(
      request.response,
      const LanFileException(LanFileErrorCode.accessDenied, '聊天连接身份验证失败'),
    );
    return;
  }
  final WebSocket socket = await WebSocketTransformer.upgrade(request);
  final WsLink link = WsLink(
    transport: IoWsTransport(socket),
    localPeerId: localPeerId,
    localName: localName,
    localAvatarHash: localAvatarHash,
    localCapabilities: localCapabilities,
  );
  if (authenticatedPeer != null) {
    link.start();
    link.sendHello();
    try {
      final remote = await link.handshake.timeout(const Duration(seconds: 2));
      if (remote.peerId != authenticatedPeer) {
        await link.close(reason: 'identity mismatch');
        return;
      }
    } on Object {
      await link.close(reason: 'handshake failed');
      return;
    }
  }
  await onUpgrade(link);
}

/// 把 dart:io 的 [WebSocket] 包成 [WsTransport]。
final class IoWsTransport implements WsTransport {
  IoWsTransport(this._socket);

  final WebSocket _socket;

  @override
  Stream<Object?> get stream => _socket;

  @override
  void add(Object? data) => _socket.add(data);

  @override
  Future<void> close([int? code, String? reason]) =>
      _socket.close(code, reason);
}
