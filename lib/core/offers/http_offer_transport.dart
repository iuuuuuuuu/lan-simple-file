// SPDX-License-Identifier: GPL-3.0-only

/// HTTP 投递器：把 offer 帧真的 POST 到对端，而不是同进程假投递。
///
/// 这是 offer 链路唯一的真实网络出口。没有它，propose 只是往内存里塞一条，
/// 对端永远收不到。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/net/lan_address_guard.dart';
import 'package:lan_simple_file/core/offers/offer_service_impl.dart';
import 'package:lan_simple_file/core/transfer/store_target_resolver.dart';
/// 走真实 HTTP 的 offer 投递。
final class HttpOfferTransport implements OfferTransport {
  HttpOfferTransport({
    required this.endpoints,
    this.path = '/api/v1/offers',
    this.timeout = const Duration(seconds: 5),
    HttpClient Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  /// 对端地址来源；与传输层同源（发现层活动表）。
  final PeerEndpointSource endpoints;

  /// 接收侧路由路径。
  final String path;

  final Duration timeout;
  final HttpClient Function() _clientFactory;

  @override
  Future<bool> isReachable(PeerId peer) async {
    final ({String host, int port})? ep = await endpoints.findEndpoint(peer);
    return ep != null;
  }

  @override
  Future<void> deliver(
    Map<String, Object?> frame, {
    required PeerId toPeer,
  }) async {
    final ({String host, int port})? ep = await endpoints.findEndpoint(toPeer);
    if (ep == null) {
      throw LanFileException(
        LanFileErrorCode.providerOffline,
        '对方当前不在线，offer 无法投递：${toPeer.value}',
      );
    }
    // 明文边界：非局域网地址一律拒绝（NSC 对 dart:io 不生效，只能在这里挡）。
    LanAddressGuard.requireCleartextAllowed(ep.host);

    final HttpClient client = _clientFactory();
    try {
      client.connectionTimeout = timeout;
      final Uri uri = Uri(
        scheme: 'http',
        host: ep.host,
        port: ep.port,
        path: path,
      );
      final HttpClientRequest req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      final List<int> body = utf8.encode(jsonEncode(frame));
      req.contentLength = body.length;
      req.add(body);
      final HttpClientResponse res = await req.close().timeout(timeout);
      final String text = await res.transform(utf8.decoder).join();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw LanFileException(
          LanFileErrorCode.network,
          '对端拒绝接收 offer：${res.statusCode} $text',
        );
      }
    } on LanFileException {
      rethrow;
    } on Object catch (error) {
      // 网络异常统一映射，不让 SocketException 直接冒到 UI 层。
      throw LanFileException(
        LanFileErrorCode.network,
        '投递 offer 失败：$error',
        cause: error,
      );
    } finally {
      client.close(force: true);
    }
  }
}
