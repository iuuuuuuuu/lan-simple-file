// SPDX-License-Identifier: GPL-3.0-only

/// 分享取件接口的真实 HTTP 测试：真起 HttpServer、真 HttpClient、真临时目录。
///
/// 不用 mock 文件系统：每个用例都在临时目录里真建文件，
/// 断言的是真实字节、真实分页与真实解压结果。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/files/local_ref_factory.dart';
import 'package:lan_simple_file/core/server/api/share_api.dart';
import 'package:lan_simple_file/core/server/api/tree_api.dart';
import 'package:lan_simple_file/core/server/api/zip_api.dart';
import 'package:lan_simple_file/core/server/http_server_host.dart';
import 'package:lan_simple_file/core/server/router.dart';
import 'package:lan_simple_file/core/server/static/static_handler.dart';

const String kShareId = 'shrTEST01';

/// 页面模板的进程内副本：测试不依赖 assets 目录是否被 pubspec 声明。
const String kShareTemplate = '''
<!DOCTYPE html>
<html><head><title>__LSF_SHARE_NAME__</title></head>
<body data-share-id="__LSF_SHARE_ID__" data-share-peer="__LSF_SHARE_PEER__">
<a id="download-client" href="lsf://open">下载客户端</a>
</body></html>
''';

Future<Uint8List> _collect(HttpClientResponse response) async {
  final BytesBuilder builder = BytesBuilder(copy: false);
  await for (final List<int> chunk in response) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

Future<HttpClientResponse> _get(
  HttpClient client,
  Uri uri, {
  Map<String, String> headers = const <String, String>{},
  String method = 'GET',
}) async {
  final HttpClientRequest request = await client.openUrl(method, uri);
  headers.forEach(request.headers.set);
  return request.close();
}

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

void main() {
  late Directory root;
  late HttpServerHost host;
  late HttpClient client;
  late ShareTarget target;
  late int port;

  Uri url(String path) => Uri.parse('http://127.0.0.1:$port$path');

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lsf_share_');
    // 三层嵌套 + 中文名 + 空格名。
    final Directory nested = await Directory('${root.path}/a/b')
        .create(recursive: true);
    await File('${root.path}/top.txt').writeAsString('top-level');
    await File('${root.path}/a/mid.bin')
        .writeAsBytes(List<int>.generate(700, (int i) => i % 256));
    await File('${nested.path}/deep.txt').writeAsString('deep');
    await File('${root.path}/中文 名字.txt').writeAsString('中文内容');
    await File('${root.path}/空文件.txt').writeAsBytes(<int>[]);

    final LocalRefFactory factory = const LocalRefFactory();
    final FileRef rootRef = await factory.openRoot(root.path);
    target = ShareTarget(
      id: ShareId.parse(kShareId),
      displayName: '测试分享',
      root: rootRef,
      ownerPeerId: PeerId.parse('p_7fk3m9x2a1cdk'),
    );

    final MapShareSource source = MapShareSource(<String, ShareTarget>{
      kShareId: target,
    });
    final Router router = Router();
    registerShareRoutes(
      router,
      source,
      templates: MemoryStaticAssetSource(<String, List<int>>{
        kSharePageAsset: utf8.encode(kShareTemplate),
      }),
    );
    registerTreeRoutes(router, source);
    registerZipRoutes(router, source);

    host = HttpServerHost(
      router: router,
      bindAddress: InternetAddress.loopbackIPv4,
      preferredPort: 0,
    );
    port = await host.start();
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await host.stop();
    if (root.existsSync()) {
      await root.delete(recursive: true);
    }
  });

  group('取件页', () {
    test('GET /s/:id 注入分享标识与名字，并含客户端引导入口', () async {
      final HttpClientResponse response = await _get(
        client,
        url('/s/$kShareId'),
      );
      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'text/html');
      final String html = utf8.decode(await _collect(response));
      expect(html, contains('data-share-id="$kShareId"'));
      expect(html, contains('测试分享'));
      expect(html, contains('p_7fk3m9x2a1cdk'));
      expect(html, contains('下载客户端'));
      expect(html, isNot(contains(kShareIdPlaceholder)));
      expect(html, isNot(contains(kShareNamePlaceholder)));
    });

    test('分享名字里的 HTML 元字符被转义', () async {
      final MapShareSource source = MapShareSource(<String, ShareTarget>{
        'shrXSS01': ShareTarget(
          id: ShareId.parse('shrXSS01'),
          displayName: '<script>alert(1)</script>',
          root: target.root,
        ),
      });
      final Router router = Router();
      registerShareRoutes(
        router,
        source,
        templates: MemoryStaticAssetSource(<String, List<int>>{
          kSharePageAsset: utf8.encode(kShareTemplate),
        }),
      );
      final HttpServerHost other = HttpServerHost(
        router: router,
        bindAddress: InternetAddress.loopbackIPv4,
        preferredPort: 0,
      );
      final int otherPort = await other.start();
      try {
        final HttpClientResponse response = await _get(
          client,
          Uri.parse('http://127.0.0.1:$otherPort/s/shrXSS01'),
        );
        final String html = utf8.decode(await _collect(response));
        expect(html, isNot(contains('<script>alert(1)</script>')));
        expect(html, contains('&lt;script&gt;'));
      } finally {
        await other.stop();
      }
    });

    test('未知分享返回 404 且带可读提示', () async {
      final HttpClientResponse response = await _get(
        client,
        url('/s/shrUNKNOWN01'),
      );
      expect(response.statusCode, 404);
      final Map<String, Object?> json = jsonDecode(
        utf8.decode(await _collect(response)),
      ) as Map<String, Object?>;
      expect(json['code'], LanFileErrorCode.notFound.name);
      expect(json['message'], contains('不存在'));
    });
  });

  group('tree 分页', () {
    test(
      'HTTP directory cursor survives deletion and orders folders first',
      () async {
        Directory('${root.path}/z-folder').createSync();
        Future<Map<String, dynamic>> page(String? cursor) async {
          final uri = url('/s/$kShareId/tree')
              .replace(queryParameters: {'limit': '1', 'cursor': ?cursor});
          final response = await _get(client, uri);
          expect(response.statusCode, 200);
          return jsonDecode(utf8.decode(await _collect(response)))
              as Map<String, dynamic>;
        }

        final first = await page(null);
        expect(first['entries'].single['key'], 'a');
        Directory('${root.path}/a').deleteSync(recursive: true);
        final second = await page(first['nextCursor'] as String);
        expect(second['entries'].single['key'], 'z-folder');
        final third = await page(second['nextCursor'] as String);
        expect(third['entries'].single['isDir'], isFalse);
      },
    );

    test(
      'literal percent names survive query decoding and file downloads',
      () async {
        final folder = await Directory('${root.path}/100%20').create();
        await File('${folder.path}/50%.txt').writeAsString('percent-bytes');
        for (final route in ['tree', 'zip']) {
          final response = await _get(
            client,
            url('/s/$kShareId/$route')
                .replace(queryParameters: {'path': '100%20'}),
          );
          final bytes = await _collect(response);
          expect(response.statusCode, 200);
          if (route == 'tree') {
            final data = jsonDecode(utf8.decode(bytes));
            expect(data['entries'].single['key'], '100%20/50%.txt');
          } else {
            final zip = ZipDecoder().decodeBytes(bytes);
            expect(zip.files.single.name, '50%.txt');
            expect(utf8.decode(zip.files.single.content), 'percent-bytes');
          }
        }
        final response = await _get(
          client,
          url('/s/$kShareId/f/100%2520/50%25.txt'),
        );
        expect(response.statusCode, 200);
        expect(utf8.decode(await _collect(response)), 'percent-bytes');
      },
    );

    test('根目录列出条目，结构完整且目录排在前', () async {
      final HttpClientResponse response = await _get(
        client,
        url('/s/$kShareId/tree'),
      );
      expect(response.statusCode, 200);
      final Map<String, Object?> json = jsonDecode(
        utf8.decode(await _collect(response)),
      ) as Map<String, Object?>;
      final List<Object?> entries = json['entries']! as List<Object?>;
      final List<Map<String, Object?>> rows = entries
          .cast<Map<String, Object?>>();
      final Set<String> names = rows
          .map((Map<String, Object?> r) => r['name']! as String)
          .toSet();
      expect(
        names,
        containsAll(<String>['a', 'top.txt', '中文 名字.txt', '空文件.txt']),
      );
      final Map<String, Object?> first = rows.first;
      expect(first.keys.toSet(), <String>{
        'key',
        'name',
        'isDir',
        'size',
        'modifiedAt',
        'mime',
      });
      expect(json['nextCursor'], isNull);
      final Map<String, Object?> dirRow = rows.firstWhere(
        (Map<String, Object?> r) => r['name'] == 'a',
      );
      expect(dirRow['isDir'], isTrue);
    });

    test('limit=2 时逐页翻完不重不漏', () async {
      final List<String> seen = <String>[];
      String? cursor;
      int guard = 0;
      while (true) {
        final Uri uri = cursor == null
            ? url('/s/$kShareId/tree?limit=2')
            : url(
                '/s/$kShareId/tree?limit=2&cursor=${Uri.encodeQueryComponent(cursor)}',
              );
        final HttpClientResponse response = await _get(client, uri);
        final Map<String, Object?> json = jsonDecode(
          utf8.decode(await _collect(response)),
        ) as Map<String, Object?>;
        final List<Map<String, Object?>> rows =
            (json['entries']! as List<Object?>).cast<Map<String, Object?>>();
        expect(rows.length, lessThanOrEqualTo(2));
        seen.addAll(rows.map((Map<String, Object?> r) => r['key']! as String));
        cursor = json['nextCursor'] as String?;
        if (cursor == null) break;
        if (++guard > 20) fail('分页未收敛');
      }
      expect(seen.toSet().length, seen.length, reason: '不得重复');
      expect(seen.length, 4, reason: '根目录共 4 项（a 目录 + 3 个文件）');
    });

    test('path 指向子目录时只列该目录', () async {
      final HttpClientResponse response = await _get(
        client,
        url('/s/$kShareId/tree?path=${Uri.encodeQueryComponent('a/b')}'),
      );
      expect(response.statusCode, 200);
      final Map<String, Object?> json = jsonDecode(
        utf8.decode(await _collect(response)),
      ) as Map<String, Object?>;
      final List<Map<String, Object?>> rows =
          (json['entries']! as List<Object?>).cast<Map<String, Object?>>();
      expect(rows.map((Map<String, Object?> r) => r['name']), <String>[
        'deep.txt',
      ]);
    });

    test('对文件调用 tree 返回 400', () async {
      final HttpClientResponse response = await _get(
        client,
        url('/s/$kShareId/tree?path=top.txt'),
      );
      expect(response.statusCode, 400);
      final Map<String, Object?> json = jsonDecode(
        utf8.decode(await _collect(response)),
      ) as Map<String, Object?>;
      expect(json['code'], LanFileErrorCode.invalidArgument.name);
    });
  });

  group('单文件下载与 Range', () {
    test('取完整文件，字节与磁盘一致', () async {
      final File source = File('${root.path}/a/mid.bin');
      final Uint8List expected = await source.readAsBytes();
      final HttpClientResponse response = await _get(
        client,
        url('/s/$kShareId/f/a/mid.bin'),
      );
      expect(response.statusCode, 200);
      expect(response.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
      expect(response.headers.value(HttpHeaders.etagHeader), isNotNull);
      final Uint8List actual = await _collect(response);
      expect(sha256Hex(actual), sha256Hex(expected));
    });

    test('Range: bytes=100-199 返回 206 且字节正确', () async {
      final Uint8List expected = await File('${root.path}/a/mid.bin')
          .readAsBytes();
      final HttpClientResponse response = await _get(
        client,
        url('/s/$kShareId/f/a/mid.bin'),
        headers: <String, String>{HttpHeaders.rangeHeader: 'bytes=100-199'},
      );
      expect(response.statusCode, HttpStatus.partialContent);
      expect(response.headers.contentLength, 100);
      final Uint8List actual = await _collect(response);
      expect(actual.length, 100);
      expect(actual, expected.sublist(100, 200));
    });

    test('越界 Range 返回 416', () async {
      final HttpClientResponse response = await _get(
        client,
        url('/s/$kShareId/f/a/mid.bin'),
        headers: <String, String>{HttpHeaders.rangeHeader: 'bytes=5000-6000'},
      );
      expect(response.statusCode, HttpStatus.requestedRangeNotSatisfiable);
      await _collect(response);
    });

    test('HEAD 无实体但 Content-Length 与 GET 一致', () async {
      final int total = await File('${root.path}/a/mid.bin').length();
      final HttpClientResponse response = await _get(
        client,
        url('/s/$kShareId/f/a/mid.bin'),
        method: 'HEAD',
      );
      expect(response.statusCode, 200);
      expect(response.headers.contentLength, total);
      expect(await _collect(response), isEmpty);
    });

    test('If-None-Match 命中 ETag 时返回 304', () async {
      final HttpClientResponse first = await _get(
        client,
        url('/s/$kShareId/f/top.txt'),
      );
      final String? etag = first.headers.value(HttpHeaders.etagHeader);
      await _collect(first);
      expect(etag, isNotNull);
      final HttpClientResponse second = await _get(
        client,
        url('/s/$kShareId/f/top.txt'),
        headers: <String, String>{HttpHeaders.ifNoneMatchHeader: etag!},
      );
      expect(second.statusCode, HttpStatus.notModified);
      await _collect(second);
    });

    test('中文文件名的 Content-Disposition 走 RFC5987', () async {
      final HttpClientResponse response = await _get(
        client,
        url('/s/$kShareId/f/${Uri.encodeComponent('中文 名字.txt')}'),
      );
      expect(response.statusCode, 200);
      final String? disposition = response.headers.value('content-disposition');
      expect(disposition, isNotNull);
      expect(disposition, contains("filename*=UTF-8''"));
      expect(
        disposition,
        contains(Uri.encodeComponent('中文 名字.txt').replaceAll('%20', '%20')),
      );
      await _collect(response);
    });

    test('零字节文件返回 200 且长度 0', () async {
      final HttpClientResponse response = await _get(
        client,
        url('/s/$kShareId/f/${Uri.encodeComponent('空文件.txt')}'),
      );
      expect(response.statusCode, 200);
      expect(response.headers.contentLength, 0);
      expect(await _collect(response), isEmpty);
    });
  });

  group('路径穿越必须被拒绝', () {
    test('三变体全部 403 且不泄漏文件内容', () async {
      final List<String> attacks = <String>[
        '/s/$kShareId/f/..%2F..%2Fetc%2Fpasswd',
        '/s/$kShareId/f/%2Fetc%2Fpasswd',
        '/s/$kShareId/f/a%2F..%2F..%2Ftop.txt',
      ];
      for (final String attack in attacks) {
        final HttpClientResponse response = await _get(client, url(attack));
        expect(response.statusCode, 403, reason: 'attack: $attack');
        final Uint8List body = await _collect(response);
        expect(
          body,
          isNot(contains('top-level'.codeUnits)),
          reason: 'attack: $attack 泄漏了 root 内内容',
        );
        expect(
          body,
          isNot(contains('root:'.codeUnits)),
          reason: 'attack: $attack 泄漏了系统文件',
        );
      }
    });

    test('带盘符的路径被拒绝', () async {
      final HttpClientResponse response = await _get(
        client,
        url('/s/$kShareId/f/C%3A%5CWindows%5Cwin.ini'),
      );
      expect(response.statusCode, 403);
      await _collect(response);
    });

    test('tree 的 path 同样拒绝穿越', () async {
      final HttpClientResponse response = await _get(
        client,
        url('/s/$kShareId/tree?path=${Uri.encodeQueryComponent('../..')}'),
      );
      expect(response.statusCode, 403);
      await _collect(response);
    });
  });

  group('zip 打包', () {
    test('打包后可解压，文件数与内容 sha256 全部一致', () async {
      final HttpClientResponse response = await _get(
        client,
        url('/s/$kShareId/zip'),
      );
      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'application/zip');
      final Uint8List archiveBytes = await _collect(response);

      final Archive archive = ZipDecoder().decodeBytes(archiveBytes);
      final List<ArchiveFile> files = archive
          .where((ArchiveFile f) => f.isFile)
          .toList();
      expect(files.length, 5, reason: '根下共 5 个文件（含两级子目录）');

      final Map<String, List<int>> actual = <String, List<int>>{
        for (final ArchiveFile file in files) file.name: file.content,
      };
      expect(actual.keys.toSet(), <String>{
        'top.txt',
        'a/mid.bin',
        'a/b/deep.txt',
        '中文 名字.txt',
        '空文件.txt',
      });

      for (final String name in actual.keys) {
        final List<int> expected = await File('${root.path}/$name')
            .readAsBytes();
        expect(
          sha256Hex(actual[name]!),
          sha256Hex(expected),
          reason: 'zip 内 $name 内容不一致',
        );
      }
    });

    test('zip 条目使用 store（不压缩），长度与原文一致', () async {
      final HttpClientResponse response = await _get(
        client,
        url('/s/$kShareId/zip'),
      );
      final Uint8List archiveBytes = await _collect(response);
      final Archive archive = ZipDecoder().decodeBytes(archiveBytes);
      for (final ArchiveFile file in archive.where(
        (ArchiveFile f) => f.isFile,
      )) {
        expect(
          file.compression,
          CompressionType.none,
          reason: '${file.name} 应为 store',
        );
      }
    });

    test('指定子目录时只打包该子树，条目路径以该目录为根', () async {
      final HttpClientResponse response = await _get(
        client,
        url('/s/$kShareId/zip?path=a'),
      );
      expect(response.statusCode, 200);
      final Archive archive = ZipDecoder().decodeBytes(
        await _collect(response),
      );
      final Set<String> names = archive
          .where((ArchiveFile f) => f.isFile)
          .map((ArchiveFile f) => f.name)
          .toSet();
      expect(names, <String>{'mid.bin', 'b/deep.txt'});
    });

    test('空目录返回 404 而不是产出空 zip', () async {
      await Directory('${root.path}/empty').create();
      final HttpClientResponse response = await _get(
        client,
        url('/s/$kShareId/zip?path=empty'),
      );
      expect(response.statusCode, 404);
      await _collect(response);
    });

    test('超过 2000 个文件时返回清单 JSON，不撑爆内存', () async {
      final Directory many = await Directory('${root.path}/many').create();
      for (int i = 0; i < kZipMaxEntries + 5; i++) {
        await File('${many.path}/f$i.bin').writeAsBytes(<int>[i % 256]);
      }
      final HttpClientResponse response = await _get(
        client,
        url('/s/$kShareId/zip?path=many'),
      );
      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'application/json');
      final Map<String, Object?> json = jsonDecode(
        utf8.decode(await _collect(response)),
      ) as Map<String, Object?>;
      expect(json['mode'], 'manifest');
      expect(json['total'], greaterThan(kZipMaxEntries));
      expect((json['sample']! as List<Object?>).length, lessThanOrEqualTo(20));

      await many.delete(recursive: true);
    });
  });
}
