// SPDX-License-Identifier: GPL-3.0-only

/// Lead 侧验收：网页分享链接必须**浏览器能直接打开并下载**。
///
/// 用户原话：「我说的链接是局域网内可以用的 网页链接，可以直接下载的」。
/// 之前只产出 lsf:// 深链（要求对方装 App），浏览器打不开——这是设计错误。
/// 本用例走真链路：本机地址 -> http 链接 -> 真发 HTTP -> 页面 200 -> 能下到文件。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/assembly.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/net/lan_address.dart';
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lsf_weblink_');
    webAssetsFallbackDir = 'assets${Platform.pathSeparator}web';
  });
  tearDown(() {
    for (int i = 0; i < 8; i++) {
      try {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        sleep(const Duration(milliseconds: 150));
      }
    }
  });

  test('pickLanAddress 只给私有段；拿不到时返回 null 而不是猜', () async {
    final String? ip = await pickLanAddress();
    if (ip == null) {
      // 无网卡环境（CI）允许为 null，但此时绝不能编一个地址。
      expect(ip, isNull);
      return;
    }
    expect(ip.contains(':'), isFalse, reason: '必须是 IPv4');
    expect(ip.startsWith('127.'), isFalse, reason: '回环对方连不上');
    expect(ip.startsWith('169.254.'), isFalse, reason: '链路本地通常没 DHCP');
    // 必须是能过局域网守卫的地址。
    expect(
      () => buildWebShareUrl(
        host: ip,
        port: 1234,
        shareId: ShareId.parse('abcd1234'),
      ),
      returnsNormally,
    );
  });

  test('网页链接是 http 地址且带端口与 /s/ 路径', () {
    final Uri u = buildWebShareUrl(
      host: '192.168.1.23',
      port: 47778,
      shareId: ShareId.parse('7Qm2xK'),
      token: 'tk-1',
    );
    expect(u.scheme, 'http');
    expect(u.host, '192.168.1.23');
    expect(u.port, 47778);
    expect(u.path, '/s/7Qm2xK');
    expect(u.queryParameters['k'], 'tk-1');
    // 与 lsf 深链的区别：这是浏览器可直接打开的地址。
    expect(u.toString(), startsWith('http://'));
  });

  test('公网地址必须被拒（不能把局域网分享指到公网）', () {
    expect(
      () => buildWebShareUrl(
        host: '8.8.8.8',
        port: 80,
        shareId: ShareId.parse('abcd1234'),
      ),
      throwsA(isA<LanFileException>()),
    );
  });

  test('端到端：网页链接真能打开并下载文件', () async {
    final AppServices s = await AppAssembler.assemble(
      dataDir: Directory('${tmp.path}${Platform.pathSeparator}a'),
      httpPortOverride: 0,
      udpPortOverride: 0,
      enableDiscovery: false,
    );
    try {
      final Directory root =
          Directory('${tmp.path}${Platform.pathSeparator}share')..createSync();
      File('${root.path}${Platform.pathSeparator}报告.txt')
          .writeAsStringSync('这是网页能下载到的内容');

      final ShareRecord rec = await s.shares.create(
        CreateShareRequest(
          rootKind: ShareRootKind.localPath,
          rootUri: root.path,
          displayName: '网页分享',
          mode: ShareMode.lan,
        ),
      );

      // 用 127.0.0.1 当 host 模拟「浏览器访问」（回环也过守卫）。
      final Uri webUrl = buildWebShareUrl(
        host: '127.0.0.1',
        port: s.port,
        shareId: rec.id,
      );
      expect(webUrl.toString(), startsWith('http://'));

      final HttpClient c = HttpClient();

      // 1) 页面本身必须 200 且是 HTML
      final HttpClientRequest pageReq = await c.getUrl(webUrl);
      final HttpClientResponse pageRes = await pageReq.close();
      expect(pageRes.statusCode, 200);
      expect(
        pageRes.headers.contentType?.mimeType,
        'text/html',
        reason: '浏览器打开必须是 HTML 页面，不是 JSON',
      );
      final String html = await pageRes.transform(utf8.decoder).join();
      expect(html.contains('网页分享'), isTrue, reason: '页面要显示分享名');

      // 2) 文件必须能下载，且字节一致
      final Uri fileUrl = webUrl.replace(
        path: '${webUrl.path}/f/${Uri.encodeComponent('报告.txt')}',
      );
      final HttpClientRequest fileReq = await c.getUrl(fileUrl);
      final HttpClientResponse fileRes = await fileReq.close();
      expect(fileRes.statusCode, 200);
      final List<int> got = await fileRes.fold<List<int>>(
        <int>[],
        (List<int> acc, List<int> chunk) => acc..addAll(chunk),
      );
      expect(utf8.decode(got), '这是网页能下载到的内容');
      c.close();
    } finally {
      await s.stop();
    }
  });

  test('AppServices.buildWebLink 在没有局域网地址时给可读错误', () async {
    final AppServices s = await AppAssembler.assemble(
      dataDir: Directory('${tmp.path}${Platform.pathSeparator}b'),
      httpPortOverride: 0,
      udpPortOverride: 0,
      enableDiscovery: false,
    );
    try {
      // 本机若有局域网地址则不该抛；否则必须是可读的 providerOffline。
      try {
        final Uri u = await s.buildWebLink(ShareId.parse('abcd1234'));
        expect(u.toString(), startsWith('http://'));
        expect(u.host, s.lanHost);
      } on LanFileException catch (e) {
        expect(e.code, LanFileErrorCode.providerOffline);
        expect(e.message, contains('局域网地址'));
      }
    } finally {
      await s.stop();
    }
  });
}