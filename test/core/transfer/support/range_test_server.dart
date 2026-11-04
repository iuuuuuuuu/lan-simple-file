// SPDX-License-Identifier: GPL-3.0-only

/// 测试夹具：一个真实的本地 HttpServer，提供带 Range / ETag 的文件响应。
///
/// 不用 mock：分片请求真的走 TCP，Range 真的按头解析，
/// 并且服务端自己统计收到的 Range 请求，供「resume 只补缺口」断言使用。
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// 夹具内部信号：模拟连接中断。
final class _ConnectionBroken implements Exception {
  const _ConnectionBroken();
}

/// 服务端观察到的一次 Range 请求。
final class RangeRequestLog {
  RangeRequestLog({required this.method, required this.rawRange, this.start, this.end});

  final String method;
  final String? rawRange;
  final int? start;
  final int? end;

  @override
  String toString() => '$method Range=$rawRange';
}

/// 支持 Range 的文件服务端。
final class RangeTestServer {
  RangeTestServer._(this._server, this.payload);

  final HttpServer _server;
  final Uint8List payload;

  int get port => _server.port;

  Uri urlFor(String name) =>
      Uri.parse('http://127.0.0.1:$port/files/$name');

  /// 收到的全部请求（按时间顺序）。
  final List<RangeRequestLog> requests = <RangeRequestLog>[];

  /// 只统计带 Range 头的请求。
  List<RangeRequestLog> get rangeRequests =>
      requests.where((RangeRequestLog r) => r.rawRange != null).toList();

  /// 累计请求过的字节数（按请求区间求和），用于断言「没有重下已完成的段」。
  int get totalRequestedBytes => rangeRequests.fold<int>(
        0,
        (int sum, RangeRequestLog r) =>
            sum + ((r.start == null || r.end == null) ? 0 : (r.end! - r.start! + 1)),
      );

  String etag = '"v1"';

  /// 每个响应最多写多少字节后主动断开；null 表示不注入故障。
  int? breakAfterBytes;

  /// 每次响应里的分块大小（小一点更容易触发中断点）。
  int responseChunkBytes = 64 * 1024;

  /// 是否故意返回错误字节（校验失败用例）。
  bool corruptPayload = false;

  /// 响应前的人为延迟，用于制造「慢速传输」。
  Duration delayPerChunk = Duration.zero;

  /// 是否忽略 Range 头（返回整份 200），用于测协议异常路径。
  bool ignoreRange = false;

  /// 收到请求时的回调（测试可在里面 abort 客户端）。
  void Function(RangeRequestLog log)? onRequest;

  Completer<void>? _firstRequest;

  /// 等到至少收到一个请求。
  Future<void> waitFirstRequest() {
    final Completer<void> completer = _firstRequest ??= Completer<void>();
    if (requests.isNotEmpty && !completer.isCompleted) completer.complete();
    return completer.future;
  }

  static Future<RangeTestServer> start(int sizeBytes) async {
    final Uint8List payload = _generatePattern(sizeBytes);
    final HttpServer server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final RangeTestServer fixture = RangeTestServer._(server, payload);
    server.listen(fixture._handle);
    return fixture;
  }

  /// 可被测试独立复算的确定性字节模式。
  static Uint8List patternFor(int size) => _generatePattern(size);

  static Uint8List _generatePattern(int size) {
    final Uint8List bytes = Uint8List(size);
    for (int i = 0; i < size; i++) {
      bytes[i] = (i * 31 + (i >> 8) * 7 + (i >> 16) * 13) & 0xFF;
    }
    return bytes;
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      await _handleInner(request);
    } on _ConnectionBroken {
      // 故意的中断，不算夹具错误。
    }
  }

  Future<void> _handleInner(HttpRequest request) async {
    final String? rawRange = request.headers.value(HttpHeaders.rangeHeader);
    int? start;
    int? end;
    if (rawRange != null && !ignoreRange) {
      final RegExpMatch? match =
          RegExp(r'bytes=(\d+)-(\d*)').firstMatch(rawRange);
      if (match != null) {
        start = int.parse(match.group(1)!);
        end = match.group(2)!.isEmpty
            ? payload.length - 1
            : int.parse(match.group(2)!);
      }
    }
    final RangeRequestLog log = RangeRequestLog(
      method: request.method,
      rawRange: rawRange,
      start: start,
      end: end,
    );
    requests.add(log);
    if (requests.length == 1) {
      final Completer<void> completer = _firstRequest ??= Completer<void>();
      if (!completer.isCompleted) completer.complete();
    }
    onRequest?.call(log);

    final HttpResponse response = request.response;
    response.headers.set(HttpHeaders.etagHeader, etag);
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.contentType = ContentType.binary;

    if (start == null) {
      // 无 Range：整份返回。
      response.statusCode = HttpStatus.ok;
      response.contentLength = payload.length;
      if (request.method == 'HEAD') {
        await response.close();
        return;
      }
      await _write(response, 0, payload.length);
      await response.close();
      return;
    }

    if (start >= payload.length) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers
          .set(HttpHeaders.contentRangeHeader, 'bytes */${payload.length}');
      response.contentLength = 0;
      await response.close();
      return;
    }
    final int clampedEnd = math.min(end ?? (payload.length - 1), payload.length - 1);
    response.statusCode = HttpStatus.partialContent;
    response.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes $start-$clampedEnd/${payload.length}',
    );
    response.contentLength = clampedEnd - start + 1;
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }
    // 探测请求（bytes=0-0）永远不注入中断：它只取 1 字节，
    // 若在这里断，下载连实体长度都拿不到，测的就不是续传而只是失败。
    final bool isProbe = start == 0 && clampedEnd == 0;
    await _write(
      response,
      start,
      clampedEnd - start + 1,
      allowBreak: !isProbe,
      allowDelay: !isProbe,
    );
    await response.close();
  }

  Future<void> _write(
    HttpResponse response,
    int start,
    int length, {
    bool allowBreak = true,
    bool allowDelay = true,
  }) async {
    int sent = 0;
    while (sent < length) {
      if (allowBreak && breakAfterBytes != null && sent >= breakAfterBytes!) {
        // 模拟连接中断。注意：response 已经写出过头，detachSocket 会抛
        // "Headers already sent"，所以这里改用 close() 之后销毁底层连接：
        // 直接抛出让 _handle 的调用方结束，配合 Content-Length 不匹配，
        // 客户端会观察到连接提前关闭。
        try {
          await response.close();
        } on Object {
          // 连接已断，忽略。
        }
        throw const _ConnectionBroken();
      }
      final int take = math.min(responseChunkBytes, length - sent);
      final int from = start + sent;
      final Uint8List slice = Uint8List.sublistView(payload, from, from + take);
      if (corruptPayload) {
        // 破坏第一个字节，让校验必然不一致。
        slice[0] = (slice[0] + 1) & 0xFF;
      }
      response.add(slice);
      await response.flush();
      sent += take;
      if (allowDelay && delayPerChunk > Duration.zero) {
        await Future<void>.delayed(delayPerChunk);
      }
    }
  }

  Future<void> stop() async {
    await _server.close(force: true);
  }
}
