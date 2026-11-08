// SPDX-License-Identifier: GPL-3.0-only
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/net/peer_share_catalog.dart';

void main() {
  final peer = PeerId.parse('p_aaaaaaaaaaaaa');
  late HttpServer server;
  late PeerShareClient client;
  late Future<void> Function(HttpRequest) handler;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      try {
        await handler(request);
      } finally {
        await request.response.close();
      }
    });
    client = PeerShareClient(
      peer: peer,
      endpointFor: () async => (host: '127.0.0.1', port: server.port),
    );
  });
  tearDown(() async {
    client.close();
    await server.close(force: true);
  });
  Map<String, Object?> catalog({String? id, String href = '/s/share_test'}) => {
    'owner': {'name': 'Same name', 'peerId': id ?? peer.value},
    'shares': [
      {'name': 'Photos', 'kind': 'folder', 'access': 'browse', 'href': href},
      {'name': 'Private', 'kind': 'folder', 'access': 'password', 'href': null},
    ],
  };
  test(
    'catalog preserves visibility and browse sends opaque document ID once',
    () async {
      handler = (request) async {
        if (request.uri.path == '/api/v1/shared-roots') {
          request.response.write(jsonEncode(catalog()));
        } else {
          expect(request.uri.path, '/s/share_test/tree');
          expect(request.uri.queryParameters['path'], 'primary:1/100%20');
          expect(request.uri.queryParameters['cursor'], 'primary:1/100%20/a');
          request.response.write(
            jsonEncode({
              'entries': [
                {
                  'key': 'primary:1/100%20/b',
                  'name': 'b',
                  'isDir': false,
                  'size': 8,
                },
              ],
              'nextCursor': null,
            }),
          );
        }
      };
      final result = await client.catalog();
      expect(result.name, 'Same name');
      expect(result.shares.first.id!.value, 'share_test');
      expect(result.shares.last.id, isNull);
      final page = await client.browse(
        result.shares.first.id!,
        path: ItemKey.parse('primary:1/100%20'),
        cursor: 'primary:1/100%20/a',
      );
      expect(page.entries.single.size, 8);
    },
  );
  test('different device ID is rejected even with the same name', () async {
    handler = (request) async =>
        request.response.write(jsonEncode(catalog(id: 'p_bbbbbbbbbbbbb')));
    await expectLater(
      client.catalog(),
      throwsA(
        isA<LanFileException>().having(
          (e) => e.code,
          'code',
          LanFileErrorCode.conflict,
        ),
      ),
    );
  });
  test(
    'catalog cannot inject remote URLs or traversal into a share link',
    () async {
      for (final href in [
        'https://example.com/s/other',
        '//other/s/foo',
        '/s/../admin',
        '/s/id?k=secret',
      ]) {
        handler = (request) async =>
            request.response.write(jsonEncode(catalog(href: href)));
        await expectLater(client.catalog(), throwsA(isA<LanFileException>()));
      }
    },
  );
  test(
    'redirect and authorization denial are surfaced; retry succeeds',
    () async {
      for (final status in [302, 403]) {
        handler = (request) async {
          request.response.statusCode = status;
          request.response.headers.set('location', 'http://example.com/');
        };
        await expectLater(client.catalog(), throwsA(isA<LanFileException>()));
      }
      handler = (request) async =>
          request.response.write(jsonEncode(catalog()));
      expect((await client.catalog()).shares.length, 2);
    },
  );
  test('offline and public endpoints are rejected', () async {
    for (final endpoint in [null, (host: '8.8.8.8', port: 80)]) {
      final offline = PeerShareClient(
        peer: peer,
        endpointFor: () async => endpoint,
      );
      await expectLater(offline.catalog(), throwsA(isA<LanFileException>()));
      offline.close();
    }
  });
}
