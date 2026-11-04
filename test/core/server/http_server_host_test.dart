// SPDX-License-Identifier: GPL-3.0-only

/// HttpServerHost 的真实行为测试：真绑定端口、真 HttpClient 请求、真关闭。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/server/http_server_host.dart';
import 'package:lan_simple_file/core/server/response.dart';
import 'package:lan_simple_file/core/server/router.dart';

/// 契约 Types._peerIdPattern 为 ^p_[a-z0-9]{13}$，共 13 个字符。
const String kSelfPeerId = 'p_7fk3m9x2a1cdk';

Future<HttpClientResponse> _send(
  HttpClient client,
  Uri uri, {
  String method = 'GET',
  Map<String, String> headers = const <String, String>{},
  List<int>? body,
}) async {
  final HttpClientRequest request = await client.openUrl(method, uri);
  headers.forEach((String name, String value) {
    request.headers.set(name, value);
  });
  if (body != null) request.add(body);
  return request.close();
}

Future<List<int>> _bodyOf(HttpClientResponse response) =>
    response.fold<List<int>>(<int>[], (List<int> acc, List<int> chunk) {
      acc.addAll(chunk);
      return acc;
    });

Future<Map<String, Object?>> _jsonOf(HttpClientResponse response) async =>
    jsonDecode(utf8.decode(await _bodyOf(response))) as Map<String, Object?>;

Router _pingRouter() {
  final Router router = Router();
  router.get('/api/v1/ping', (HttpRequest request) async {
    await jsonResponse(request.response, HttpStatus.ok, <String, Object?>{
      'peerId': kSelfPeerId,
      'name': 'YG 的台式机',
      'proto': LanFileConstants.protocolVersion,
    });
  });
  return router;
}

void main() {
  group('HttpServerHost', () {
    late HttpServerHost host;
    late HttpClient client;
    late int port;

    setUp(() async {
      host = HttpServerHost(
        router: _pingRouter(),
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

    test('start 返回真实监听端口，port getter 与之相同', () {
      expect(host.port, isNotNull);
      expect(host.port, greaterThan(0));
      expect(host.port, port);
      expect(host.isRunning, isTrue);
    });

    test('ping 返回 200 且 JSON 字段齐全', () async {
      final HttpClientResponse response = await _send(
        client,
        Uri.parse('http://127.0.0.1:$port/api/v1/ping'),
      );
      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'application/json');

      final Map<String, Object?> json = await _jsonOf(response);
      expect(json.keys, containsAll(<String>['peerId', 'name', 'proto']));
      expect(json['peerId'], kSelfPeerId);
      expect(json['name'], 'YG 的台式机');
      expect(json['proto'], LanFileConstants.protocolVersion);
      expect(response.headers.value(HttpHeaders.cacheControlHeader), 'no-store');
    });

    test('未知路径返回 404 且 body 是可解析的 JSON 错误对象', () async {
      final HttpClientResponse response = await _send(
        client,
        Uri.parse('http://127.0.0.1:$port/api/v1/nope'),
      );
      expect(response.statusCode, 404);
      expect(response.headers.contentType?.mimeType, 'application/json');

      final Map<String, Object?> json = await _jsonOf(response);
      expect(json['code'], LanFileErrorCode.notFound.name);
      expect(json['message'], isA<String>());
      expect((json['message'] as String).isNotEmpty, isTrue);
    });

    test('已注册路径用错方法返回 405 且带 Allow 头', () async {
      final HttpClientResponse response = await _send(
        client,
        Uri.parse('http://127.0.0.1:$port/api/v1/ping'),
        method: 'POST',
      );
      expect(response.statusCode, 405);
      expect(response.headers.value(HttpHeaders.allowHeader), contains('GET'));
      final Map<String, Object?> json = await _jsonOf(response);
      expect(json['code'], LanFileErrorCode.invalidArgument.name);
    });

    test('处理器抛 LanFileException 时映射为状态码与错误码', () async {
      final Router router = Router();
      router.get('/boom', (HttpRequest request) async {
        throw const LanFileException(
          LanFileErrorCode.accessDenied,
          '不允许访问',
        );
      });
      final HttpServerHost local = HttpServerHost(
        router: router,
        bindAddress: InternetAddress.loopbackIPv4,
        preferredPort: 0,
      );
      final int localPort = await local.start();
      try {
        final HttpClientResponse response = await _send(
          client,
          Uri.parse('http://127.0.0.1:$localPort/boom'),
        );
        expect(response.statusCode, 403);
        final Map<String, Object?> json = await _jsonOf(response);
        expect(json['code'], LanFileErrorCode.accessDenied.name);
        expect(json['message'], '不允许访问');
      } finally {
        await local.stop();
      }
    });

    test('处理器抛非契约异常时收成 500 + internal，且不静默吞掉', () async {
      final List<Object> reported = <Object>[];
      final Router router = Router();
      router.get('/kaboom', (HttpRequest request) async {
        throw StateError('意外失败');
      });
      final HttpServerHost local = HttpServerHost(
        router: router,
        bindAddress: InternetAddress.loopbackIPv4,
        preferredPort: 0,
        onUnhandledError: (Object error, StackTrace stackTrace) {
          reported.add(error);
        },
      );
      final int localPort = await local.start();
      try {
        final HttpClientResponse response = await _send(
          client,
          Uri.parse('http://127.0.0.1:$localPort/kaboom'),
        );
        expect(response.statusCode, 500);
        final Map<String, Object?> json = await _jsonOf(response);
        expect(json['code'], LanFileErrorCode.internal.name);
        expect(reported, hasLength(1));
        expect(reported.single, isA<StateError>());
      } finally {
        await local.stop();
      }
    });

    test('端口占用时顺延到下一个可用端口，且顺延后的端口真能服务', () async {
      const int preferred = LanFileConstants.httpPort;
      ServerSocket? blocker;
      try {
        blocker = await ServerSocket.bind(InternetAddress.anyIPv4, preferred);
      } on SocketException {
        // 端口已被本机其他进程占用，效果等价：仍然测「被占用就顺延」。
        blocker = null;
      }
      final HttpServerHost shifted = HttpServerHost(
        router: _pingRouter(),
        bindAddress: InternetAddress.anyIPv4,
        preferredPort: preferred,
        fallbackSpan: LanFileConstants.httpPortFallbackSpan,
      );
      try {
        final int actual = await shifted.start();
        expect(actual, isNot(preferred));
        expect(actual, greaterThan(preferred));
        expect(
          actual,
          lessThanOrEqualTo(preferred + LanFileConstants.httpPortFallbackSpan),
        );

        final HttpClientResponse response = await _send(
          client,
          Uri.parse('http://127.0.0.1:$actual/api/v1/ping'),
        );
        expect(response.statusCode, 200);
        expect((await _jsonOf(response))['name'], 'YG 的台式机');
      } finally {
        await shifted.stop();
        await blocker?.close();
      }
    });

    test('全部端口被占用时抛 LanFileException(io) 而不是返回假端口', () async {
      const int preferred = LanFileConstants.httpPort;
      final int span = LanFileConstants.httpPortFallbackSpan;
      final List<ServerSocket> blockers = <ServerSocket>[];
      try {
        for (int offset = 0; offset <= span; offset++) {
          try {
            blockers.add(
              await ServerSocket.bind(
                InternetAddress.anyIPv4,
                preferred + offset,
              ),
            );
          } on SocketException {
            // 该端口已被本机其它进程（例如开发者自己开着的应用实例）占用。
            // 那同样是「被占用」，不需要我们再 bind 一次——测试要验证的是
            // 「顺延用尽后抛 io」，不是「本机没有别的进程」。
          }
        }
        final HttpServerHost blocked = HttpServerHost(
          router: Router(),
          bindAddress: InternetAddress.anyIPv4,
          preferredPort: preferred,
          fallbackSpan: span,
        );
        await expectLater(
          blocked.start(),
          throwsA(
            isA<LanFileException>().having(
              (LanFileException e) => e.code,
              'code',
              LanFileErrorCode.io,
            ),
          ),
        );
        expect(blocked.port, isNull);
        expect(blocked.isRunning, isFalse);
      } finally {
        for (final ServerSocket socket in blockers) {
          await socket.close();
        }
      }
    });

    test('stop 后端口释放且 port 回到 null', () async {
      final int bound = host.port!;
      await host.stop();
      expect(host.port, isNull);
      expect(host.isRunning, isFalse);
      expect(host.inFlightRequests, 0);

      // 端口确实释放了，可以重新绑定。
      final ServerSocket socket =
          await ServerSocket.bind(InternetAddress.anyIPv4, bound);
      await socket.close();
    });

    test('重复 start 抛 conflict，不会泄漏第二个监听', () async {
      await expectLater(
        host.start(),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.conflict,
          ),
        ),
      );
      expect(host.port, port);
    });

    test('优雅关闭会等待进行中的请求跑完', () async {
      final Completer<void> entered = Completer<void>();
      final Completer<void> release = Completer<void>();
      bool finished = false;

      final Router router = Router();
      router.get('/slow', (HttpRequest request) async {
        entered.complete();
        await release.future;
        await jsonResponse(request.response, HttpStatus.ok, <String, Object?>{
          'ok': true,
        });
        finished = true;
      });
      final HttpServerHost local = HttpServerHost(
        router: router,
        bindAddress: InternetAddress.loopbackIPv4,
        preferredPort: 0,
      );
      final int localPort = await local.start();
      final Future<HttpClientResponse> pending = _send(
        client,
        Uri.parse('http://127.0.0.1:$localPort/slow'),
      );
      await entered.future;
      expect(local.inFlightRequests, 1);

      final Future<void> stopping = local.stop();
      expect(finished, isFalse);

      release.complete();
      final HttpClientResponse response = await pending;
      expect(response.statusCode, 200);
      expect(await _jsonOf(response), <String, Object?>{'ok': true});

      await stopping;
      expect(finished, isTrue);
      expect(local.inFlightRequests, 0);
    });
  });
}
