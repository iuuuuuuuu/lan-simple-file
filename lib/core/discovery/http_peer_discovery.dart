// SPDX-License-Identifier: GPL-3.0-only
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../contracts/contracts.dart';
import '../identity/ed25519_signer.dart';
import '../net/lan_address_guard.dart';
import '../server/router.dart';
import '../server/response.dart';
import '../server/api/profile_api.dart';
import 'announce_service_impl.dart';

/// Signed HTTP discovery for hosts reachable across a NAT that blocks multicast.
class HttpPeerDiscovery {
  HttpPeerDiscovery({
    required this.identity,
    required this.announce,
    required this.accept,
  });
  static const path = '/api/v1/discovery/exchange';
  final DeviceIdentity identity;
  final AnnounceServiceImpl announce;
  final Future<void> Function(AnnouncePacket, Uint8List, String, int) accept;
  final _client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  Timer? _timer;
  final Map<({String host, int port}), Future<PeerId?>> _pending = {};
  bool _disposed = false;
  String? lastError;
  Future<Map<String, Object?>> envelope() async => {
    'publicKey': base64Url.encode(identity.publicKey),
    'packet': (await announce.buildSignedPacket()).toJson(),
  };
  Future<PeerId> receive(
    Map<String, Object?> body,
    String host,
    int? endpointPort,
  ) async {
    LanAddressGuard.requireCleartextAllowed(host);
    final rawKey = body['publicKey'];
    final rawPacket = body['packet'];
    if (rawKey is! String || rawPacket is! Map) {
      throw const LanFileException(LanFileErrorCode.invalidArgument, '发现数据无效');
    }
    late final Uint8List key;
    late final AnnouncePacket packet;
    try {
      key = base64Url.decode(rawKey);
      packet = AnnouncePacket.fromJson(Map<String, Object?>.from(rawPacket));
      if (key.length != 32 ||
          derivePeerId(key) != packet.peerId ||
          packet.version != LanFileConstants.protocolVersion ||
          packet.port < 1 ||
          packet.port > 65535 ||
          packet.name.length > 64 ||
          (DateTime.now().millisecondsSinceEpoch - packet.timestamp).abs() >
              60000 ||
          !await Ed25519Signer().verify(
            Uint8List.fromList(packet.signableBytes()),
            base64Url.decode(base64Url.normalize(packet.signature)),
            key,
          )) {
        throw const FormatException('签名无效');
      }
    } on Object {
      throw const LanFileException(LanFileErrorCode.accessDenied, '发现签名无效或已过期');
    }
    if (packet.peerId == identity.peerId) return packet.peerId;
    if (!_disposed) {
      final endpointHost = endpointPort == null ? packet.ip : host;
      LanAddressGuard.requireCleartextAllowed(endpointHost);
      await accept(packet, key, endpointHost, endpointPort ?? packet.port);
    }
    return packet.peerId;
  }

  void register(Router router) {
    router.post(path, (request) async {
      try {
        final host = request.connectionInfo?.remoteAddress.address ?? '';
        await receive(
          await readJsonObject(request, maxBytes: 8192),
          host,
          null,
        );
        await jsonResponse(request.response, 200, await envelope());
      } on LanFileException catch (error) {
        await errorResponse(request.response, error);
      } on Object {
        await errorResponse(
          request.response,
          const LanFileException(LanFileErrorCode.invalidArgument, '发现请求无效'),
        );
      }
    });
  }

  Future<PeerId?> exchange(String host, int port) {
    if (_disposed) return Future.value();
    final endpoint = (host: host, port: port);
    return _pending.putIfAbsent(
      endpoint,
      () => _exchange(host, port).whenComplete(() {
        _pending.remove(endpoint);
      }),
    );
  }

  Future<PeerId?> _exchange(String host, int port) async {
    try {
      LanAddressGuard.requireCleartextAllowed(host);
      if (port < 1 || port > 65535) throw const FormatException('端口无效');
      final request = await _client.postUrl(
        Uri(scheme: 'http', host: host, port: port, path: path),
      );
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(await envelope()));
      final response = await request.close().timeout(
        const Duration(seconds: 3),
      );
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw const FormatException('对端不支持直接发现');
      }
      final buffer = BytesBuilder();
      await for (final chunk in response.timeout(const Duration(seconds: 3))) {
        if (buffer.length + chunk.length > 8192) {
          throw const FormatException('发现响应过大');
        }
        buffer.add(chunk);
      }
      final id = await receive(
        Map<String, Object?>.from(
          jsonDecode(utf8.decode(buffer.takeBytes())) as Map,
        ),
        host,
        port,
      );
      lastError = null;
      return id;
    } on Object catch (error) {
      lastError = error.toString();
      return null;
    }
  }

  void startHostPolling(
    String host,
    int port,
    Future<void> Function(PeerId) onPeer,
  ) {
    Future<void> probe() async {
      if (_disposed) return;
      final id = await exchange(host, port);
      if (!_disposed && id != null && id != identity.peerId) {
        try {
          await onPeer(id);
        } on Object {
          /* A later poll retries a temporarily unavailable peer. */
        }
      }
    }

    unawaited(probe());
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(probe()),
    );
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    _client.close(force: true);
    await Future.wait(_pending.values.toList());
  }
}
