// SPDX-License-Identifier: GPL-3.0-only

/// 生产环境的下载地址解析：按 peers 表查提供者地址，拼出带 Range 的文件 URL。
///
/// 这是传输链路能真正工作的最后一环：没有它，TransferService 只会用固定 URL。
library;

import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/net/lan_address_guard.dart';
import 'package:lan_simple_file/core/transfer/transfer_service_impl.dart';

/// 对端地址表：由发现层维护，传输层只读。
abstract interface class PeerEndpointSource {
  /// 返回该 peer 的 host:port；未知返回 null。
  Future<({String host, int port})?> findEndpoint(PeerId peer);
}

/// 按 shareId 拼接对方文件 URL。
///
/// 两条安全约束写死在这里，调用方绕不过去：
/// 1. 必须能查到对端地址，查不到即抛 providerOffline（不许猜 IP）；
/// 2. 地址必须落在局域网段内，否则拒绝明文传输
///    （Flutter 的 dart:io 不走 Android java.net 栈，NSC 对 Dart 侧不生效，
///    所以这条只能在 Dart 里做）。
final class StoreTargetResolver implements TransferTargetResolver {
  const StoreTargetResolver({required this.endpoints});

  final PeerEndpointSource endpoints;

  @override
  Future<Uri> resolve({
    required PeerId peer,
    required ShareId share,
    required ItemKey itemKey,
  }) async {
    final ({String host, int port})? endpoint = await endpoints.findEndpoint(peer);
    if (endpoint == null) {
      throw LanFileException(
        LanFileErrorCode.providerOffline,
        '提供者已离线，无法下载：${peer.value}',
      );
    }
    LanAddressGuard.requireCleartextAllowed(endpoint.host);
    final String encodedPath = itemKey.value
        .split('/')
        .map(Uri.encodeComponent)
        .join('/');
    return Uri(
      scheme: 'http',
      host: endpoint.host,
      port: endpoint.port,
      path: '/s/${share.value}/f/$encodedPath',
    );
  }
}
