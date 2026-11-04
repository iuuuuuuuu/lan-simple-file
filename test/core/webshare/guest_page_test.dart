// SPDX-License-Identifier: GPL-3.0-only

/// guest 静态页：读仓库里真实的 assets/web/guest.* 文件，经真 HttpServer 返回。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/server/static/static_handler.dart';

import 'support/web_share_fixture.dart';

/// 从仓库根读取 assets/web 下的真实文件。
MemoryStaticAssetSource realWebAssets() {
  final Directory dir = Directory('assets/web');
  if (!dir.existsSync()) {
    fail('assets/web 不存在，工作目录: ${Directory.current.path}');
  }
  final MemoryStaticAssetSource source = MemoryStaticAssetSource();
  for (final FileSystemEntity entity in dir.listSync(recursive: true)) {
    if (entity is! File) continue;
    final String name = entity.path.split(Platform.pathSeparator).last;
    source.put(name, entity.readAsBytesSync());
  }
  return source;
}

void main() {
  group('guest 静态页', () {
    test('GET /w/guest 返回 200 + text/html，且页面引用 guest.js', () async {
      final WebShareFixture f = await WebShareFixture.create();
      addTearDown(f.dispose);
      final MemoryStaticAssetSource assets = realWebAssets();
      expect(assets.paths, contains('guest.html'));
      expect(assets.paths, contains('guest.js'));
      expect(assets.paths, contains('guest.css'));

      final GuestHttpServer server = await GuestHttpServer.start(
        service: f.service,
        templates: assets,
      );
      addTearDown(server.stop);
      final HttpClient client = HttpClient();
      addTearDown(() => client.close(force: true));

      final HttpClientRequest request = await client.openUrl(
        'GET',
        server.url('/w/guest'),
      );
      final HttpClientResponse response = await request.close();
      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'text/html');

      final List<int> raw = await response.fold<List<int>>(
        <int>[],
        (List<int> acc, List<int> chunk) {
          acc.addAll(chunk);
          return acc;
        },
      );
      final String html = utf8.decode(raw);
      expect(html, contains('/web/guest.js'));
      expect(html, contains('/web/guest.css'));
      expect(html, contains('接受'));
    });

    test('guest.js 含握手、心跳、pagehide 上报三件事', () async {
      final MemoryStaticAssetSource assets = realWebAssets();
      final Uint8List? bytes = await assets.load('guest.js');
      expect(bytes, isNotNull);
      final String js = utf8.decode(bytes!);
      expect(js, contains('/w/session'));
      expect(js, contains('/beat'));
      expect(js, contains('pagehide'));
      expect(js, contains('beforeunload'));
      expect(js, contains('ECDSA'));
    });

    test('guest.css 复用双色 token，不引入新色相', () async {
      final MemoryStaticAssetSource assets = realWebAssets();
      final Uint8List? bytes = await assets.load('guest.css');
      final String css = utf8.decode(bytes!);
      expect(css, contains('--accent'));
      expect(css, contains('--line'));
      // 不应出现硬编码的十六进制新色相。
      expect(RegExp(r'#[0-9a-fA-F]{3,6}').hasMatch(css), isFalse);
    });

    test('未配置模板时 /w/guest 返回 404', () async {
      final WebShareFixture f = await WebShareFixture.create();
      addTearDown(f.dispose);
      final GuestHttpServer server = await GuestHttpServer.start(
        service: f.service,
      );
      addTearDown(server.stop);
      final HttpClient client = HttpClient();
      addTearDown(() => client.close(force: true));
      final HttpClientRequest request = await client.openUrl(
        'GET',
        server.url('/w/guest'),
      );
      final HttpClientResponse response = await request.close();
      expect(response.statusCode, 404);
    });
  });
}
