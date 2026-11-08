// SPDX-License-Identifier: GPL-3.0-only

/// dart:io HTTP 服务宿主：端口顺延、请求分派、错误映射、优雅关闭。
///
/// 只负责「把请求交给 Router，把异常变成 JSON 错误体」，不含任何业务路由。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lan_simple_file/core/contracts/contracts.dart';

import '../diagnostics/network_log.dart';

import 'response.dart';
import 'router.dart';

/// 未匹配到路由时的处理器。
typedef NotFoundHandler = Future<void> Function(
  HttpRequest request,
  Set<String> allowedMethods,
);

/// 未预期异常的兜底上报；默认写 stderr，绝不静默吞掉。
typedef UnhandledErrorReporter = void Function(
  Object error,
  StackTrace stackTrace,
);

/// 一个绑定在局域网地址上的 HTTP 服务。
final class HttpServerHost {
  HttpServerHost({
    required this.router,
    this.bindAddress,
    this.preferredPort = LanFileConstants.httpPort,
    this.fallbackSpan = LanFileConstants.httpPortFallbackSpan,
    this.notFoundHandler,
    this.onUnhandledError,
    this.stopGracePeriod = const Duration(seconds: 10),
  });

  /// 路由表。
  final Router router;

  /// 监听地址；默认 [InternetAddress.anyIPv4]，即局域网可达。
  final InternetAddress? bindAddress;

  /// 首选端口；传 0 表示由系统分配（测试常用）。
  final int preferredPort;

  /// 端口被占用时向后顺延的最大跨度。
  final int fallbackSpan;

  /// 自定义 404/405 处理器；默认输出 JSON 错误体。
  final NotFoundHandler? notFoundHandler;

  /// 兜底异常上报；默认写 stderr。
  final UnhandledErrorReporter? onUnhandledError;

  /// 关闭时等待进行中请求的上限。
  final Duration stopGracePeriod;

  HttpServer? _server;
  int _inFlight = 0;
  Completer<void>? _drained;

  /// 实际监听端口；未启动时为 null。
  int? get port => _server?.port;

  /// 正在处理中的请求数，供测试与关闭逻辑使用。
  int get inFlightRequests => _inFlight;

  bool get isRunning => _server != null;

  /// 启动服务，返回实际监听端口。
  ///
  /// 端口被占用时按 [fallbackSpan] 依次顺延；全部占用则抛
  /// [LanFileErrorCode.io] 的 [LanFileException]。
  Future<int> start() async {
    if (_server != null) {
      throw LanFileException(
        LanFileErrorCode.conflict,
        'HTTP 服务已在端口 $port 上运行',
      );
    }
    final int attempts = preferredPort == 0 ? 1 : fallbackSpan + 1;
    Object? lastError;
    for (int offset = 0; offset < attempts; offset++) {
      final int candidate = preferredPort == 0 ? 0 : preferredPort + offset;
      if (candidate > 65535) break;
      try {
        final HttpServer server = await HttpServer.bind(
          bindAddress ?? InternetAddress.anyIPv4,
          candidate,
          shared: false,
        );
        server.autoCompress = false;
        _server = server;
        NetworkLog.record('http.listening', {
          'address': server.address.address,
          'port': server.port,
        });
        server.listen(
          _handleRequest,
          onError: (Object error, StackTrace stackTrace) {
            _report(error, stackTrace);
          },
        );
        return server.port;
      } on SocketException catch (error) {
        NetworkLog.record('http.bind_error', {
          'attemptPort': candidate,
          ...NetworkLog.errorFields(error),
        });
        lastError = error;
        continue;
      }
    }
    throw LanFileException(
      LanFileErrorCode.io,
      '端口 $preferredPort 起连续 $attempts 个端口均不可用',
      cause: lastError,
    );
  }

  /// 优雅关闭：停止接受新连接，等待进行中的请求结束后再返回。
  Future<void> stop() async {
    final HttpServer? server = _server;
    if (server == null) return;
    _server = null;
    NetworkLog.record('http.stop', {'port': server.port});
    if (_inFlight > 0 && (_drained == null || _drained!.isCompleted)) {
      _drained = Completer<void>();
    }
    try {
      await server.close(force: false);
      final Completer<void>? drained = _drained;
      if (drained != null && !drained.isCompleted) {
        await drained.future.timeout(stopGracePeriod, onTimeout: () {});
      }
    } finally {
      _drained = null;
    }
  }

  void _handleRequest(HttpRequest request) {
    _inFlight++;
    unawaited(_runRequest(request));
  }

  Future<void> _runRequest(HttpRequest request) async {
    // Log only fixed route categories: URLs may carry capability credentials.
    final route = request.uri.path == '/'
        ? 'root'
        : request.uri.path == '/api/v1/ping'
        ? 'ping'
        : 'other';
    NetworkLog.record('http.request', {
      'source': request.connectionInfo?.remoteAddress.address,
      'localPort': request.connectionInfo?.localPort,
      'method': request.method,
      'route': route,
    });
    try {
      await _dispatch(request);
    } catch (error, stackTrace) {
      await _failRequest(request, error, stackTrace);
    } finally {
      NetworkLog.record('http.response', {
        'route': route,
        'status': request.response.statusCode,
      });
      _inFlight--;
      final Completer<void>? drained = _drained;
      if (_inFlight == 0 && drained != null && !drained.isCompleted) {
        drained.complete();
      }
    }
  }

  Future<void> _dispatch(HttpRequest request) async {
    final String path = request.uri.path;
    final RouteMatch? match = router.match(request.method, path);
    if (match != null) {
      await match.handler(request);
      return;
    }
    final Set<String> allowed = router.allowedMethods(path);
    final NotFoundHandler? custom = notFoundHandler;
    if (custom != null) {
      await custom(request, allowed);
      return;
    }
    if (allowed.isEmpty) {
      await errorResponse(
        request.response,
        LanFileException(
          LanFileErrorCode.notFound,
          '没有这个接口: ${request.method} $path',
        ),
      );
      return;
    }
    request.response.headers.set(HttpHeaders.allowHeader, allowed.join(', '));
    await errorResponse(
      request.response,
      LanFileException(
        LanFileErrorCode.invalidArgument,
        '该路径不接受 ${request.method} 方法',
        httpStatus: HttpStatus.methodNotAllowed,
      ),
    );
  }

  Future<void> _failRequest(
    HttpRequest request,
    Object error,
    StackTrace stackTrace,
  ) async {
    final HttpResponse response = request.response;
    // 非契约异常一律上报：既写回 500，也不让原始堆栈悄悄消失。
    if (error is! LanFileException) {
      _report(error, stackTrace);
    }
    try {
      if (error is LanFileException) {
        await errorResponse(response, error);
        return;
      }
      await errorResponse(
        response,
        LanFileException(LanFileErrorCode.internal, '服务端处理请求时出错', cause: error),
      );
    } catch (secondary, secondaryStack) {
      _report(error, stackTrace);
      _report(secondary, secondaryStack);
      try {
        await response.close();
      } on Object catch (closeError, closeStack) {
        _report(closeError, closeStack);
      }
    }
  }

  void _report(Object error, StackTrace stackTrace) {
    NetworkLog.record('http.error', NetworkLog.errorFields(error));
    final UnhandledErrorReporter? reporter = onUnhandledError;
    if (reporter != null) {
      reporter(error, stackTrace);
      return;
    }
    stderr.writeln('[http] 未处理的请求异常: $error');
    stderr.writeln(stackTrace.toString());
  }

  /// 把 JSON 字节写出（供测试与少量内部用途）。
  static List<int> encodeJson(Map<String, Object?> body) =>
      utf8.encode(jsonEncode(body));
}
