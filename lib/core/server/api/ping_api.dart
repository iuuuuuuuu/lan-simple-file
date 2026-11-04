// SPDX-License-Identifier: GPL-3.0-only

/// 存活探测接口：对端与网页端用最小代价确认「这台机器在线、说的是同一版协议」。
library;

import 'dart:io';

import 'package:lan_simple_file/core/contracts/contracts.dart';

import '../response.dart';
import '../router.dart';

/// `GET /api/v1/ping` 的响应载荷。
///
/// 字段名与公告对齐：peerId/name/proto，proto 取 [LanFileConstants.protocolVersion]。
final class PingPayload {
  const PingPayload({required this.peerId, required this.name, this.proto});

  final PeerId peerId;
  final String name;

  /// 协议版本；缺省取全局常量。
  final int? proto;

  int get protocol => proto ?? LanFileConstants.protocolVersion;

  Map<String, Object?> toJson() => <String, Object?>{
        'peerId': peerId.value,
        'name': name,
        'proto': protocol,
      };
}

/// 构造 ping 处理器；[nameReader] 每次请求现取，改名后立刻生效。
Handler pingHandler({
  required PeerId peerId,
  required String Function() nameReader,
}) {
  return (HttpRequest request) async {
    final PingPayload payload = PingPayload(
      peerId: peerId,
      name: nameReader(),
    );
    await jsonResponse(request.response, HttpStatus.ok, payload.toJson());
  };
}

/// 把 ping 路由注册到 $router 上。
void registerPingRoutes(
  Router router, {
  required PeerId peerId,
  required String Function() nameReader,
}) {
  router.get(
    '${LanFileConstants.apiPrefix}/ping',
    pingHandler(peerId: peerId, nameReader: nameReader),
  );
}
