// SPDX-License-Identifier: GPL-3.0-only
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/server/api/share_download_observer.dart';
import 'package:lan_simple_file/core/server/http_server_host.dart';
import 'package:lan_simple_file/core/server/router.dart';

void main() {
  test('history failures preserve HTTP responses and send failures remain failures', () async {
    final events = <ShareDownloadEvent>[];
    final router = Router();
    for (final broken in [false, true]) {
      router.get(
        broken ? '/broken' : '/ok',
        (request) => observeShareDownload(
          request,
          name: 'test.txt',
          share: ShareId.parse('share_test'),
          item: ItemKey.parse('test.txt'),
          observer: (event) async {
            events.add(event);
            throw StateError('history unavailable');
          },
          send: () async {
            if (broken) throw StateError('file unavailable');
            request.response.contentLength = 3;
            request.response.add(utf8.encode('abc'));
            await request.response.close();
          },
        ),
      );
    }
    final server = HttpServerHost(router: router, preferredPort: 0);
    final port = await server.start();
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.stop();
    });
    final ok = await (await client.getUrl(
      Uri.parse('http://127.0.0.1:$port/ok'),
    )).close();
    expect(ok.statusCode, 200);
    expect(await ok.transform(utf8.decoder).join(), 'abc');
    final failed = await (await client.getUrl(
      Uri.parse('http://127.0.0.1:$port/broken'),
    )).close();
    expect(failed.statusCode, 500);
    await failed.drain<void>();
    expect(events.map((event) => event.status), ['sent', 'failed']);
    expect(events.last.bytes, isNull);
  });
}
