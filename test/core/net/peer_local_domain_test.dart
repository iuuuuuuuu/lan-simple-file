// SPDX-License-Identifier: GPL-3.0-only
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/net/peer_local_domain.dart';

void main() {
  final peer = PeerId.parse('p_devicefirst01');
  late HttpServer server;
  late Object body;
  var status = 200;
  setUp(() async {
    status = 200;
    body = {
      'peerId': peer.value,
      'ready': true,
      'host': 'phone.local',
      'httpPort': 47778,
    };
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = status;
      if (status == 302) request.response.headers.set('location', '/redirect');
      request.response.write(body is String ? body : jsonEncode(body));
      await request.response.close();
    });
  });
  tearDown(() => server.close(force: true));
  Future<PeerLocalDomain?> fetch({bool requireIdentity = true}) =>
      fetchPeerLocalDomain(peer, (
        host: '127.0.0.1',
        port: server.port,
      ), requireIdentity: requireIdentity);

  test(
    'preserves the phone browser port and accepts a matching identity',
    () async {
      expect(await fetch(), (host: 'phone.local', port: 47778));
    },
  );
  test('refuses mismatched identity and malformed domain metadata', () async {
    final original = Map<String, dynamic>.from(body as Map);
    for (final change in [
      {'peerId': 'p_devicesecond2'},
      {'ready': false},
      {'host': 'phone.local;evil'},
      {'host': 'example.com'},
      {'httpPort': 0},
      {'httpPort': 65536},
      {'httpPort': '80'},
    ]) {
      body = {...original, ...change};
      expect(await fetch(), isNull, reason: '$change');
    }
  });
  test('legacy response only supports explicitly requested links', () async {
    (body as Map).remove('peerId');
    expect(await fetch(), isNull);
    expect(await fetch(requireIdentity: false), (
      host: 'phone.local',
      port: 47778,
    ));
  });
  test('refuses redirects, oversized bodies and malformed JSON', () async {
    status = 302;
    expect(await fetch(), isNull);
    status = 200;
    for (final invalid in ['x' * 4097, 'not json', '[]']) {
      body = invalid;
      expect(await fetch(), isNull);
    }
  });
  test('does not send requests to non-LAN endpoints', () async {
    expect(
      await fetchPeerLocalDomain(peer, (host: 'example.com', port: 80)),
      isNull,
    );
    expect(
      await fetchPeerLocalDomain(peer, (host: '8.8.8.8', port: 80)),
      isNull,
    );
  });
}
