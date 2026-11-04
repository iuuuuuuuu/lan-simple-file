// SPDX-License-Identifier: GPL-3.0-only

/// fileRangeResponse 的端到端测试：真 20 MB 磁盘文件 + 真 HttpServer + 真 HttpClient。
///
/// 断言逐字节比对，不接受「状态码对了就算过」。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/server/http_server_host.dart';
import 'package:lan_simple_file/core/server/response.dart';
import 'package:lan_simple_file/core/server/router.dart';

import 'support/local_file_ref.dart';

/// 20 MB。
const int kFileSize = 20 * 1024 * 1024;

/// 确定性字节模式：按索引取模，不靠随机数，任意切片可独立复算。
Uint8List _patternBytes(int offset, int length) {
  final Uint8List bytes = Uint8List(length);
  for (int i = 0; i < length; i++) {
    final int index = offset + i;
    bytes[i] = (index * 31 + (index >> 8) * 7 + (index >> 16)) & 0xFF;
  }
  return bytes;
}

Future<Directory> _makeTempDir() =>
    Directory.systemTemp.createTemp('lsf_range_');

/// 直接对绝对 URL 发一个请求，供「另起一个 server」的用例复用。
Future<HttpClientResponse> requestRaw(
  HttpClient client,
  String method,
  String url,
) async {
  final HttpClientRequest request = await client.openUrl(
    method,
    Uri.parse(url),
  );
  return request.close();
}

/// 真实写一个 20 MB 文件到磁盘。
Future<File> _writeSampleFile(Directory dir, String name) async {
  final File file = File('${dir.path}/$name');
  final RandomAccessFile handle = await file.open(mode: FileMode.write);
  try {
    const int chunk = 1024 * 1024;
    for (int offset = 0; offset < kFileSize; offset += chunk) {
      final int length = (kFileSize - offset < chunk) ? kFileSize - offset : chunk;
      await handle.writeFrom(_patternBytes(offset, length));
    }
  } finally {
    await handle.close();
  }
  return file;
}

/// 独立重算期望字节，用来逐字节比对（不回读被测代码的输出）。
Uint8List _expectSlice(int start, int endInclusive) =>
    _patternBytes(start, endInclusive - start + 1);

void main() {
  late Directory dir;
  late File sampleFile;
  late LocalFileRef ref;
  late HttpServerHost host;
  late HttpClient client;
  late int port;

  setUpAll(() async {
    dir = await _makeTempDir();
    sampleFile = await _writeSampleFile(dir, 'sample-20mb.bin');
    ref = LocalFileRef(sampleFile.path);
    expect(await sampleFile.length(), kFileSize);
  });

  tearDownAll(() async {
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  });

  setUp(() async {
    final Router router = Router();
    const String path = '/file/sample-20mb.bin';
    router.get(path, (HttpRequest request) async {
      await fileRangeResponse(request.response, ref, request);
    });
    host = HttpServerHost(
      router: router,
      bindAddress: InternetAddress.loopbackIPv4,
      preferredPort: 0,
    );
    port = await host.start();
    client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  });

  tearDown(() async {
    client.close(force: true);
    await host.stop();
  });

  Future<HttpClientResponse> request(
    String method, {
    String path = '/file/sample-20mb.bin',
    Map<String, String> headers = const <String, String>{},
  }) async {
    final HttpClientRequest req = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    headers.forEach((String name, String value) {
      req.headers.set(name, value);
    });
    return req.close();
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

  group('fileRangeResponse', () {
    test('GET 全量：200、Content-Length 正确、20 MB 逐字节一致', () async {
      final HttpClientResponse response = await request('GET');
      expect(response.statusCode, 200);
      expect(response.contentLength, kFileSize);
      expect(response.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
      expect(response.headers.value(HttpHeaders.etagHeader), isNotNull);

      final Uint8List body = await drain(response);
      expect(body.length, kFileSize);
      expect(body, equals(_patternBytes(0, kFileSize)));
    });

    test('HEAD 无 body 且 Content-Length 与 GET 相同', () async {
      final HttpClientResponse head = await request('HEAD');
      expect(head.statusCode, 200);
      expect(head.contentLength, kFileSize);
      final Uint8List body = await drain(head);
      expect(body, isEmpty);
      expect(head.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
    });

    test('Range: bytes=100-2000 返回 206 且切片逐字节一致', () async {
      final HttpClientResponse response = await request(
        'GET',
        headers: <String, String>{HttpHeaders.rangeHeader: 'bytes=100-2000'},
      );
      expect(response.statusCode, HttpStatus.partialContent);
      expect(response.contentLength, 2000 - 100 + 1);
      expect(
        response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 100-2000/$kFileSize',
      );

      final Uint8List body = await drain(response);
      expect(body.length, 1901);
      expect(body, equals(_expectSlice(100, 2000)));
    });

    test('越界 Range 返回 416 且 Content-Range 说明实体长度', () async {
      final HttpClientResponse response = await request(
        'GET',
        headers: <String, String>{
          HttpHeaders.rangeHeader: 'bytes=${kFileSize + 100}-${kFileSize + 200}',
        },
      );
      expect(response.statusCode, HttpStatus.requestedRangeNotSatisfiable);
      expect(
        response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes */$kFileSize',
      );
      final Uint8List body = await drain(response);
      final Map<String, Object?> json =
          jsonDecode(utf8.decode(body)) as Map<String, Object?>;
      expect(json['code'], LanFileErrorCode.invalidArgument.name);
    });

    test('HEAD + Range 返回 206 且无 body', () async {
      final HttpClientResponse response = await request(
        'HEAD',
        headers: <String, String>{HttpHeaders.rangeHeader: 'bytes=0-99'},
      );
      expect(response.statusCode, HttpStatus.partialContent);
      expect(response.contentLength, 100);
      expect(
        response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 0-99/$kFileSize',
      );
      expect(await drain(response), isEmpty);
    });

    test('后缀 Range bytes=-128 取末尾 128 字节', () async {
      final HttpClientResponse response = await request(
        'GET',
        headers: <String, String>{HttpHeaders.rangeHeader: 'bytes=-128'},
      );
      expect(response.statusCode, HttpStatus.partialContent);
      expect(response.contentLength, 128);
      final Uint8List body = await drain(response);
      expect(body, equals(_expectSlice(kFileSize - 128, kFileSize - 1)));
    });

    test('开区间 bytes=${kFileSize - 50}- 一直读到文件尾', () async {
      final HttpClientResponse response = await request(
        'GET',
        headers: <String, String>{
          HttpHeaders.rangeHeader: 'bytes=${kFileSize - 50}-',
        },
      );
      expect(response.statusCode, HttpStatus.partialContent);
      expect(response.contentLength, 50);
      final Uint8List body = await drain(response);
      expect(body, equals(_expectSlice(kFileSize - 50, kFileSize - 1)));
    });

    test('If-None-Match 命中 ETag 返回 304', () async {
      final HttpClientResponse first = await request('HEAD');
      final String? etag = first.headers.value(HttpHeaders.etagHeader);
      await drain(first);
      expect(etag, isNotNull);

      final HttpClientResponse second = await request(
        'GET',
        headers: <String, String>{HttpHeaders.ifNoneMatchHeader: etag!},
      );
      expect(second.statusCode, HttpStatus.notModified);
      expect(await drain(second), isEmpty);
    });

    test('中文文件名 Content-Disposition 同时给出 ASCII 兜底与 RFC 5987 编码', () async {
      final Router local = Router();
      local.get('/cn', (HttpRequest request) async {
        await fileRangeResponse(
          request.response,
          ref,
          request,
          downloadName: '季度 报告-2026.pdf',
        );
      });
      final HttpServerHost second = HttpServerHost(
        router: local,
        bindAddress: InternetAddress.loopbackIPv4,
        preferredPort: 0,
      );
      final int secondPort = await second.start();
      try {
        final HttpClientResponse response = await requestRaw(
          client,
          'HEAD',
          'http://127.0.0.1:$secondPort/cn',
        );
        final String? disposition =
            response.headers.value('content-disposition');
        expect(disposition, isNotNull);
        expect(disposition, startsWith('attachment;'));
        expect(disposition, contains('filename="'));
        expect(
          disposition,
          contains("filename*=UTF-8''"),
        );
        // 「季度 报告-2026.pdf」的 UTF-8 percent-encoding。
        expect(
          disposition,
          contains(
            "%E5%AD%A3%E5%BA%A6%20%E6%8A%A5%E5%91%8A-2026.pdf",
          ),
        );
        // 头值里不允许出现裸 CR/LF。
        expect(disposition, isNot(contains('\r')));
        expect(disposition, isNot(contains('\n')));
        expect(await drain(response), isEmpty);
      } finally {
        await second.stop();
      }
    });

    test('文件名里的 CRLF 无法注入额外响应头', () async {
      final Router local = Router();
      local.get('/inject', (HttpRequest request) async {
        await fileRangeResponse(
          request.response,
          ref,
          request,
          downloadName: 'evil\r\nX-Injected: 1\r\n\r\n.txt',
        );
      });
      final HttpServerHost second = HttpServerHost(
        router: local,
        bindAddress: InternetAddress.loopbackIPv4,
        preferredPort: 0,
      );
      final int secondPort = await second.start();
      try {
        final HttpClientResponse response = await requestRaw(
          client,
          'HEAD',
          'http://127.0.0.1:$secondPort/inject',
        );
        expect(response.statusCode, 200);
        expect(response.headers.value('x-injected'), isNull);
        final String? disposition =
            response.headers.value('content-disposition');
        expect(disposition, isNotNull);
        expect(disposition, isNot(contains('\r')));
        expect(disposition, isNot(contains('\n')));
        expect(
          response.headers.value('content-disposition'),
          contains('evil'),
        );
      } finally {
        await second.stop();
      }
    });
  });

  group('parseRangeHeader', () {
    test('无 Range 头时为 absent', () {
      expect(parseRangeHeader(null, 100).outcome, RangeOutcome.absent);
      expect(parseRangeHeader('   ', 100).outcome, RangeOutcome.absent);
    });

    test('单段可取时为 satisfiable 并夹紧到实体末尾', () {
      final RangeParseResult result = parseRangeHeader('bytes=10-999', 100);
      expect(result.outcome, RangeOutcome.satisfiable);
      expect(result.range, const ByteRange(10, 99));
    });

    test('起点越界为 unsatisfiable', () {
      expect(
        parseRangeHeader('bytes=100-200', 100).outcome,
        RangeOutcome.unsatisfiable,
      );
    });

    test('零长度实体上的任何 Range 都不可满足', () {
      expect(
        parseRangeHeader('bytes=0-0', 0).outcome,
        RangeOutcome.unsatisfiable,
      );
    });

    test('多段、非法单位、倒序区间一律忽略而非报错', () {
      expect(
        parseRangeHeader('bytes=0-1,5-6', 100).outcome,
        RangeOutcome.ignored,
      );
      expect(parseRangeHeader('items=0-1', 100).outcome, RangeOutcome.ignored);
      expect(parseRangeHeader('bytes=50-10', 100).outcome, RangeOutcome.ignored);
      expect(parseRangeHeader('bytes=abc', 100).outcome, RangeOutcome.ignored);
    });
  });
}
