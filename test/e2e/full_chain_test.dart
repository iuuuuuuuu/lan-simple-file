// SPDX-License-Identifier: GPL-3.0-only

/// 真实端到端验收：起服务栈 -> 建分享 -> 通过 HTTP 逐层浏览并下载 -> 校验字节。
///
/// 这条不是单测：它走完整链路（SQLite -> ShareService -> /s/ 路由 -> FileRef -> HTTP 响应），
/// 任何一环没接上都会失败。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/assembly.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lsf_full_e2e_');
    // flutter test 没有 asset bundle，页面模板只能从磁盘读。
    webAssetsFallbackDir = 'assets${Platform.pathSeparator}web';
  });
  tearDown(() {
    for (int i = 0; i < 8; i++) {
      try {
        if (tmp.existsSync()) {
          tmp.deleteSync(recursive: true);
        }
        return;
      } on FileSystemException {
        sleep(const Duration(milliseconds: 150));
      }
    }
  });

  Future<Map<String, Object?>> getJson(HttpClient c, Uri u) async {
    final HttpClientRequest req = await c.getUrl(u);
    final HttpClientResponse res = await req.close();
    final String text = await res.transform(utf8.decoder).join();
    return <String, Object?>{
      'status': res.statusCode,
      'body': text,
    };
  }

  test('全链路：建分享 -> /s/:id 页 200 -> 目录树 -> 下载文件字节一致', () async {
    final AppServices svc = await AppAssembler.assemble(
      dataDir: tmp,
      httpPortOverride: 0,
      udpPortOverride: 0,
      enableDiscovery: false,
      name: 'E2E',
    );
    try {
      // 真实目录与文件
      final Directory root =
          Directory('${tmp.path}${Platform.pathSeparator}shared')
            ..createSync();
      Directory('${root.path}${Platform.pathSeparator}sub').createSync();
      final File f1 = File('${root.path}${Platform.pathSeparator}a.txt')
        ..writeAsStringSync('顶层文件内容');
      File('${root.path}${Platform.pathSeparator}sub${Platform.pathSeparator}b.txt')
          .writeAsStringSync('子目录文件内容');

      final ShareRecord share = await svc.shares.create(
        CreateShareRequest(
          rootKind: ShareRootKind.localPath,
          rootUri: root.path,
          displayName: 'E2E 分享',
          mode: ShareMode.lan,
        ),
      );

      final HttpClient c = HttpClient();
      final String base = 'http://127.0.0.1:${svc.port}';

      // 1) 分享页必须 200
      final Map<String, Object?> page =
          await getJson(c, Uri.parse('$base/s/${share.id.value}'));
      expect(page['status'], 200, reason: '分享页必须可访问');
      expect((page['body']! as String).contains('E2E 分享'), isTrue,
          reason: '页面必须显示分享名');

      // 2) 目录树接口必须给出条目
      final Map<String, Object?> tree = await getJson(
        c,
        Uri.parse('$base/s/${share.id.value}/tree'),
      );
      expect(tree['status'], 200);
      final Map<String, Object?> treeJson =
          jsonDecode(tree['body']! as String) as Map<String, Object?>;
      final List<Object?> entries = treeJson['entries']! as List<Object?>;
      expect(entries.length, greaterThanOrEqualTo(2),
          reason: '根目录应有 1 个文件 + 1 个目录');

      // 3) 下载文件，字节必须与磁盘一致
      final HttpClientRequest req = await c.getUrl(
        Uri.parse('$base/s/${share.id.value}/f/a.txt'),
      );
      final HttpClientResponse res = await req.close();
      expect(res.statusCode, 200);
      final List<int> got = await res.fold<List<int>>(
        <int>[],
        (List<int> acc, List<int> chunk) => acc..addAll(chunk),
      );
      final Uint8List expected = await f1.readAsBytes();
      expect(got.length, expected.length, reason: '下载字节数必须与磁盘一致');
      expect(got, equals(expected.toList()), reason: '逐字节一致');

      // 4) 带 Range 的请求必须 206
      final HttpClientRequest rangeReq = await c.getUrl(
        Uri.parse('$base/s/${share.id.value}/f/a.txt'),
      );
      rangeReq.headers.set(HttpHeaders.rangeHeader, 'bytes=0-5');
      final HttpClientResponse rangeRes = await rangeReq.close();
      expect(rangeRes.statusCode, 206);
      final List<int> part = await rangeRes.fold<List<int>>(
        <int>[],
        (List<int> acc, List<int> chunk) => acc..addAll(chunk),
      );
      expect(part.length, 6);

      // 5) 不存在的分享必须 404（不是 200 空页）
      final Map<String, Object?> missing =
          await getJson(c, Uri.parse('$base/s/zzzz9999'));
      expect(missing['status'], 404);

      c.close();
    } finally {
      await svc.stop();
    }
  });

  test('停用分享后立即 404（不是缓存命中）', () async {
    final AppServices svc = await AppAssembler.assemble(
      dataDir: tmp,
      httpPortOverride: 0,
      udpPortOverride: 0,
      enableDiscovery: false,
    );
    try {
      final Directory root =
          Directory('${tmp.path}${Platform.pathSeparator}root2')
            ..createSync();
      File('${root.path}${Platform.pathSeparator}x.txt').writeAsStringSync('x');
      final ShareRecord share = await svc.shares.create(
        CreateShareRequest(
          rootKind: ShareRootKind.localPath,
          rootUri: root.path,
          displayName: '可停用',
          mode: ShareMode.lan,
        ),
      );
      final HttpClient c = HttpClient();
      final String url = 'http://127.0.0.1:${svc.port}/s/${share.id.value}';
      expect((await getJson(c, Uri.parse(url)))['status'], 200);
      await svc.shares.stop(share.id);
      expect((await getJson(c, Uri.parse(url)))['status'], 404,
          reason: '停用后必须立即不可读');
      c.close();
    } finally {
      await svc.stop();
    }
  });
}
