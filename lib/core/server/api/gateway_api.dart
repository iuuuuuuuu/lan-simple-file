// SPDX-License-Identifier: GPL-3.0-only

/// `GET /j/:shareId[?k=token]`：分享链接的网关跳转。
///
/// 这是「链接与网络拓扑解耦」的最后一块拼图：
///
/// ```
/// 浏览器 / 其它节点  --GET /j/SID?k=TOKEN-->  任意在线节点
///                                     |
///                        本机有该 share  ->  302 /s/SID?k=...
///                        否则查 peers 表  ->  302 http://<owner>/s/SID?k=...
///                        都找不到        ->  410 「提供者已离线」
/// ```
///
/// 三种结果都不把 IP 写进**链接**本身：链接永远是 `lsf://open?share=..`，
/// 跳转目标里的地址是**运行时从 peers 表查出来的**，换 IP 后旧链接照常可用。
library;

import 'dart:async';
import 'dart:io';

import 'package:lan_simple_file/core/contracts/contracts.dart';

import '../response.dart';
import '../router.dart';
import 'share_api.dart';

/// 跳到对端时使用的地址来源。
///
/// 发现层公告里带 `port`，但**不保证带 IP**（契约里 `ip` 允许空串）。
/// 因此这里要一个能回答「这个 peer 现在用什么地址能连上」的最小接口，
/// 由组装层用「发现层活动表 + 最近一次公告的源地址」或「peers 表」实现。
abstract interface class PeerEndpointLookup {
  /// 查不到（从未见过 / 已过期 / 不知道地址）返回 null。
  Future<PeerEndpoint?> find(PeerId peerId);
}

/// 一个对端的可连接地址。
final class PeerEndpoint {
  const PeerEndpoint({required this.host, required this.port});

  /// 主名（IP 或局域网主机名）；允许为空串表示「未知」。
  final String host;

  /// HTTP 端口。
  final int port;

  /// 是否可以拿来拼跳转地址。
  bool get isUsable =>
      host.trim().isNotEmpty && port > 0 && port <= 65535;

  @override
  String toString() => '$host:$port';
}

/// 网关决策结果，供测试与排障直接断言（不依赖 HTTP 层）。
enum GatewayOutcome {
  /// 本机拥有该分享，跳到本机 `/s/`。
  local,

  /// 远端拥有，跳到对端地址。
  remote,

  /// 本机没有、也知道 owner 是谁，但拿不到可用地址。
  ownerUnknownAddress,

  /// 整个 peers 表里根本没有这个分享的归属信息。
  ownerOffline,
}

/// 一次网关决策的完整结果。
final class GatewayDecision {
  const GatewayDecision({
    required this.outcome,
    this.location,
    this.reason = '',
  });

  final GatewayOutcome outcome;

  /// 302 的目标；[GatewayOutcome] 为 local/remote 时非空。
  final String? location;

  /// 无法跳转时的可读原因（给 410 的 body 用）。
  final String reason;

  /// 是否应当回 302。
  bool get isRedirect =>
      outcome == GatewayOutcome.local || outcome == GatewayOutcome.remote;
}

/// 网关决策器：不含 HTTP，纯逻辑，便于直接单测。
final class GatewayResolver {
  const GatewayResolver({
    required this.ownShares,
    required this.ownerLookup,
    required this.endpoints,
    this.selfPeerId,
    this.selfPort,
  });

  /// 本机是否拥有某个分享。
  final ShareSource ownShares;

  /// 分享 -> owner 的归属查询（本机没有时用）。
  ///
  /// 返回 null 表示「本机不知道这个 share 归谁」。
  final Future<PeerId?> Function(ShareId shareId) ownerLookup;

  /// owner -> 可连接地址。
  final PeerEndpointLookup endpoints;

  /// 本机 peerId；查到 owner 就是自己时直接按本机处理。
  final PeerId? selfPeerId;

  /// 本机 HTTP 端口；用于拼本机跳转地址（只在需要绝对地址时使用）。
  final int? selfPort;

  /// 决策一次 `/j/` 请求。
  Future<GatewayDecision> resolve(ShareId shareId, {String? token}) async {
    // 1) 本机拥有 -> 直接给相对路径，不暴露任何地址。
    final ShareTarget? local = await ownShares.find(shareId);
    if (local != null) {
      return GatewayDecision(
        outcome: GatewayOutcome.local,
        location: _localLocation(shareId, token),
      );
    }

    // 2) 问归属。
    final PeerId? owner = await ownerLookup(shareId);
    if (owner == null) {
      return const GatewayDecision(
        outcome: GatewayOutcome.ownerOffline,
        // 验收要求：都找不到时必须给出「提供者已离线」这样可读的原因。
        reason: '本机不认识这个分享：提供者已离线，或从未与本机通过信',
      );
    }
    if (selfPeerId != null && owner == selfPeerId) {
      // 归属是自己、但 ownShares 里没有 —— 说明分享已停止或撤销。
      return const GatewayDecision(
        outcome: GatewayOutcome.ownerOffline,
        reason: '该分享由本机提供，但已停止共享或已被撤销',
      );
    }

    // 3) 查 owner 的地址。
    final PeerEndpoint? endpoint = await endpoints.find(owner);
    if (endpoint == null || !endpoint.isUsable) {
      return GatewayDecision(
        outcome: GatewayOutcome.ownerUnknownAddress,
        reason: '提供者 ${owner.value} 已离线，或本机尚未获知它的地址',
      );
    }
    return GatewayDecision(
      outcome: GatewayOutcome.remote,
      location: _remoteLocation(endpoint, shareId, token),
    );
  }

  String _localLocation(ShareId shareId, String? token) {
    final String base = '/s/${Uri.encodeComponent(shareId.value)}';
    if (token == null || token.isEmpty) {
      return base;
    }
    return '$base?k=${Uri.encodeQueryComponent(token)}';
  }

  String _remoteLocation(PeerEndpoint endpoint, ShareId shareId, String? token) {
    final String path = _localLocation(shareId, token);
    return 'http://${endpoint.host}:${endpoint.port}$path';
  }
}

/// 410 的 body：必须是可读文案，且明确说明「提供者已离线」。
Map<String, Object?> gatewayGoneBody(GatewayDecision decision) {
  return <String, Object?>{
    'code': LanFileErrorCode.notFound.name,
    'message': decision.reason,
    'hint': '链接本身仍然有效，提供者上线后可以重试',
  };
}

/// `GET /j/:shareId` 处理器。
Handler gatewayHandler(GatewayResolver resolver) {
  return (HttpRequest request) async {
    final String rawId = _segment(request.uri, 2);
    final String? token = request.uri.queryParameters['k'];

    final ShareId shareId;
    try {
      shareId = parseShareId(rawId);
    } on LanFileException catch (error) {
      await errorResponse(request.response, error);
      return;
    }

    final GatewayDecision decision =
        await resolver.resolve(shareId, token: token);

    if (decision.isRedirect) {
      // 302 + Location；不缓存，避免提供者换地址后客户端拿旧跳转。
      request.response.statusCode = HttpStatus.found;
      request.response.headers.set(HttpHeaders.locationHeader, decision.location!);
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      request.response.contentLength = 0;
      await request.response.close();
      return;
    }

    await jsonResponse(
      request.response,
      HttpStatus.gone,
      <String, Object?>{
        ...gatewayGoneBody(decision),
        'shareId': shareId.value,
        'outcome': decision.outcome.name,
      },
    );
  };
}

/// 把 `/j/` 路由注册到 [router] 上。
void registerGatewayRoutes(Router router, GatewayResolver resolver) {
  router.get('/j/:shareId', gatewayHandler(resolver));
}

String _segment(Uri uri, int index) {
  final List<String> parts = uri.path.split('/');
  return index < parts.length ? parts[index] : '';
}