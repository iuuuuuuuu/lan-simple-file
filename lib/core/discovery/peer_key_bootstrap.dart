// SPDX-License-Identifier: GPL-3.0-only

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../contracts/contracts.dart';
import '../identity/ed25519_signer.dart';
import '../net/lan_address_guard.dart';

/// 从公告的真实发送者查询公钥；只有派生 ID 相同的公钥才可用于公告验签。
/// 公钥暂存在这里，设备资料仍由验签后的 PeerUpsertSink 写入。
final class PeerKeyBootstrap {
  final Map<PeerId, Uint8List> _keys = <PeerId, Uint8List>{};
  final Map<PeerId, Future<Uint8List?>> _running =
      <PeerId, Future<Uint8List?>>{};

  Uint8List? keyFor(PeerId peer) => _keys[peer];

  Future<Uint8List?> resolve(
    AnnouncePacket packet,
    InternetAddress sender,
  ) async {
    if (packet.ip != sender.address ||
        !LanAddressGuard.allowsCleartext(sender.address) ||
        packet.port < 1 ||
        packet.port > 65535) {
      return null;
    }
    if (_keys.containsKey(packet.peerId)) return _keys[packet.peerId];
    final Future<Uint8List?>? pending = _running[packet.peerId];
    if (pending != null) return pending;
    if (_running.length >= 16) return null;
    final Future<Uint8List?> task = _fetch(packet);
    _running[packet.peerId] = task;
    try {
      return await task;
    } finally {
      _running.remove(packet.peerId);
    }
  }

  Future<Uint8List?> _fetch(AnnouncePacket packet) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 2);
    try {
      final HttpClientRequest request = await client.getUrl(
        Uri(
          scheme: 'http',
          host: packet.ip,
          port: packet.port,
          path: '/api/v1/identity',
        ),
      );
      request.followRedirects = false;
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 2),
      );
      if (response.statusCode != HttpStatus.ok) return null;
      final BytesBuilder body = BytesBuilder(copy: false);
      await for (final List<int> chunk in response.timeout(
        const Duration(seconds: 2),
      )) {
        if (body.length + chunk.length > 4096) return null;
        body.add(chunk);
      }
      final Map<String, dynamic> data =
          jsonDecode(utf8.decode(body.takeBytes())) as Map<String, dynamic>;
      if (data['peerId'] != packet.peerId.value ||
          data['publicKey'] is! String) {
        return null;
      }
      final Uint8List key = base64Url.decode(data['publicKey'] as String);
      if (key.length != kEd25519PublicKeyBytes ||
          derivePeerId(key) != packet.peerId) {
        return null;
      }
      if (_keys.length >= 64) _keys.remove(_keys.keys.first);
      _keys[packet.peerId] = key;
      return key;
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
