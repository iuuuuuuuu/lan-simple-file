// SPDX-License-Identifier: GPL-3.0-only

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/server/http_server_host.dart';
import 'package:lan_simple_file/core/server/router.dart';

void main() {
  test('浏览器入口和内部入口共用实际分享内容，第二端口不能顺延到别的端口', () async {
    var title = '项目资料';
    final router = Router();
    router.get('/s/share123', (request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write(title);
      await request.response.close();
    });
    final internal = HttpServerHost(router: router, preferredPort: 0);
    final browser = HttpServerHost(
      router: router,
      preferredPort: 0,
      fallbackSpan: 0,
    );
    final client = HttpClient();
    await internal.start();
    await browser.start();
    addTearDown(() async {
      client.close(force: true);
      await browser.stop();
      await internal.stop();
    });
    Future<String> read(int port) async {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/s/share123'),
      );
      final response = await request.close();
      expect(response.statusCode, 200);
      return response.transform(utf8.decoder).join();
    }

    expect(await read(internal.port!), '项目资料');
    expect(await read(browser.port!), '项目资料');
    title = '已修改的备注';
    expect(await read(browser.port!), '已修改的备注');
    expect(await read(internal.port!), '已修改的备注');
    final occupied = HttpServerHost(
      router: router,
      preferredPort: browser.port!,
      fallbackSpan: 0,
    );
    await expectLater(occupied.start(), throwsA(isA<LanFileException>()));
    expect(occupied.port, isNull);
    expect(await read(browser.port!), '已修改的备注');
  });
}
