// SPDX-License-Identifier: GPL-3.0-only

/// 静态页测试：直接读仓库里真实的 assets/web/**，经真 HttpServer 返回。
///
/// 因此这些用例同时验证了「文件确实存在」与「Content-Type 正确」。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/server/http_server_host.dart';
import 'package:lan_simple_file/core/server/router.dart';
import 'package:lan_simple_file/core/server/static/static_handler.dart';

/// 从仓库根读取 assets/web 下的真实文件；找不到资源时直接失败而不是跳过。
MemoryStaticAssetSource _realWebAssets() {
  final Directory dir = Directory('assets/web');
  if (!dir.existsSync()) {
    fail('assets/web 不存在，工作目录: ${Directory.current.path}');
  }
  final MemoryStaticAssetSource source = MemoryStaticAssetSource();
  for (final FileSystemEntity entity in dir.listSync(recursive: true)) {
    if (entity is! File) continue;
    final String relative = entity.path
        .replaceFirst(RegExp(r'^assets[\\/]web[\\/]'), '')
        .replaceAll('\\', '/');
    source.put(relative, entity.readAsBytesSync());
  }
  if (source.paths.isEmpty) {
    fail('assets/web 下没有任何文件');
  }
  return source;
}

void main() {
  group('StaticHandler', () {
    late MemoryStaticAssetSource source;
    late HttpServerHost host;
    late HttpClient client;
    late int port;

    setUp(() async {
      source = _realWebAssets();
      final Router router = Router();
      final StaticHandler handler = StaticHandler(source: source);
      registerStaticRoutes(router, handler);
      // 测试专用入口：query 里的原始路径不经 Uri 归一化，直接喂给 handler。
      router.get('/__raw', (HttpRequest request) async {
        await handler.handle(
          request,
          assetPath: request.uri.queryParameters['p'] ?? '',
        );
      });
      host = HttpServerHost(
        router: router,
        bindAddress: InternetAddress.loopbackIPv4,
        preferredPort: 0,
      );
      port = await host.start();
      client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    });

    tearDown(() async {
      client.close(force: true);
      await host.stop();
    });

    Future<HttpClientResponse> get(
      String path, {
      String method = 'GET',
    }) async {
      final HttpClientRequest request = await client.openUrl(
        method,
        Uri.parse('http://127.0.0.1:$port$path'),
      );
      return request.close();
    }

    Future<Uint8List> drain(HttpClientResponse response) async {
      final List<int> bytes = await response.fold<List<int>>(
        <int>[],
        (List<int> acc, List<int> chunk) {
          acc.addAll(chunk);
          return acc;
        },
      );
      return Uint8List.fromList(bytes);
    }

    test('资产夹具包含 index.html / app.js / style.css 三个真实文件', () {
      expect(source.paths, containsAll(<String>['index.html', 'app.js', 'style.css']));
      expect(source.paths.where((String p) => p.endsWith('.html')), isNotEmpty);
    });

    test('GET / 返回 200 + text/html', () async {
      final HttpClientResponse response = await get('/');
      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'text/html');
      expect(response.headers.contentType?.charset, 'utf-8');

      final String html = utf8.decode(await drain(response));
      expect(html, contains('<title>lan-simple-file</title>'));
      expect(html, contains('/web/app.js'));
    });

    test('GET /web/app.js 返回 200 + text/javascript', () async {
      final HttpClientResponse response = await get('/web/app.js');
      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'text/javascript');
      final String js = utf8.decode(await drain(response));
      expect(js, contains('/api/v1/ping'));
    });

    test('GET /web/style.css 返回 200 + text/css 且含双色 token', () async {
      final HttpClientResponse response = await get('/web/style.css');
      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'text/css');
      final String css = utf8.decode(await drain(response));
      expect(css, contains('--accent'));
      expect(css, contains('prefers-color-scheme'));
      expect(
        css,
        contains('#0e1116'),
        reason: '暗色 bg token 必须在 css 里，明暗两套都要有',
      );
      expect(css, contains('#f7f8fa'));
    });

    test('HEAD /web/style.css 无 body 但 Content-Length 与 GET 一致', () async {
      final HttpClientResponse getResponse = await get('/web/style.css');
      final int length = getResponse.contentLength;
      await drain(getResponse);

      final HttpClientResponse headResponse =
          await get('/web/style.css', method: 'HEAD');
      expect(headResponse.statusCode, 200);
      expect(headResponse.contentLength, length);
      expect(await drain(headResponse), isEmpty);
    });

    test('未知资源返回 404 + JSON 错误体', () async {
      final HttpClientResponse response = await get('/web/missing.js');
      expect(response.statusCode, 404);
      final Map<String, Object?> json =
          jsonDecode(utf8.decode(await drain(response))) as Map<String, Object?>;
      expect(json['code'], 'notFound');
    });

    test('目录穿越路径在 handler 内被折叠，读不到资源表以外的内容', () async {
      // 注意：直接写 /web/../../pubspec.yaml 会被 Uri.parse 提前归一化成
      // /pubspec.yaml，测到的是 router 而不是 handler。这里用 query 参数
      // 把原始穿越串原样喂给 handler，才真正测归一化本身。
      final HttpClientResponse response = await get(
        '/__raw?p=${Uri.encodeQueryComponent('../../pubspec.yaml')}',
      );
      expect(response.statusCode, 404);
      final String body = utf8.decode(await drain(response));
      expect(body, contains('notFound'));
      expect(
        body,
        isNot(contains('lan_simple_file')),
        reason: '仓库根的 pubspec.yaml 绝不能经静态路由泄出',
      );
    });

    test('折叠后仍落在资源表内的穿越路径正常返回（证明折叠是真的）', () async {
      final HttpClientResponse response = await get(
        '/__raw?p=${Uri.encodeQueryComponent('web/../index.html')}',
      );
      expect(response.statusCode, 200);
      expect(
        utf8.decode(await drain(response)),
        contains('<title>lan-simple-file</title>'),
      );
    });

    test('查表键会折叠 ..，normalizeAssetPath 可单测', () {
      expect(normalizeAssetPath('/a/b/../c'), 'a/c');
      expect(normalizeAssetPath('../../etc/passwd'), 'etc/passwd');
      expect(normalizeAssetPath('/'), '');
      expect(normalizeAssetPath('//a//b//'), 'a/b');
    });

    test('Content-Type 推断覆盖 html/js/css/json/svg 与未知扩展名', () {
      expect(contentTypeForAsset('a.html').mimeType, 'text/html');
      expect(contentTypeForAsset('a.JS').mimeType, 'text/javascript');
      expect(contentTypeForAsset('a.css').mimeType, 'text/css');
      expect(contentTypeForAsset('a.json').mimeType, 'application/json');
      expect(contentTypeForAsset('a.svg').mimeType, 'image/svg+xml');
      expect(
        contentTypeForAsset('a.bin').mimeType,
        'application/octet-stream',
      );
      expect(
        contentTypeForAsset('noext').mimeType,
        'application/octet-stream',
      );
    });
  });
}
