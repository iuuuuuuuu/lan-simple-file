// SPDX-License-Identifier: GPL-3.0-only
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../contracts/contracts.dart';
import 'lan_address_guard.dart';
import 'local_domain.dart';

typedef PeerLocalDomain = ({String host, int port});

Future<PeerLocalDomain?> fetchPeerLocalDomain(
  PeerId peer,
  ({String host, int port}) endpoint, {
  bool requireIdentity = false,
}) async {
  if (!LanAddressGuard.allowsCleartext(endpoint.host)) return null;
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 2)
    ..findProxy = (_) => 'DIRECT';
  Future<PeerLocalDomain?> read() async {
    final request = await client.getUrl(
      Uri(
        scheme: 'http',
        host: endpoint.host,
        port: endpoint.port,
        path: '/api/v1/local-domain',
      ),
    );
    request.followRedirects = false;
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) return null;
    final buffer = BytesBuilder();
    await for (final chunk in response) {
      if (buffer.length + chunk.length > 4096) return null;
      buffer.add(chunk);
    }
    final data = jsonDecode(utf8.decode(buffer.takeBytes()));
    if (data is! Map<String, dynamic>) return null;
    final id = data['peerId'];
    if ((requireIdentity || id != null) && id != peer.value) return null;
    final host = data['host'], port = data['httpPort'];
    if (data['ready'] != true ||
        host is! String ||
        !isLocalDomain(host) ||
        port is! int ||
        port < 1 ||
        port > 65535) {
      return null;
    }
    return (host: host, port: port);
  }

  try {
    return await read().timeout(const Duration(seconds: 4));
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
}
