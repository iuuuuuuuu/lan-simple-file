// SPDX-License-Identifier: GPL-3.0-only

/// link 层用例：解析器正/负向、链接构造器、无网络地址硬门禁、round-trip。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/link/link_parser.dart';
import 'package:lan_simple_file/core/link/share_link_builder.dart';

void main() {
  const LinkParser parser = LinkParser();
  const LinkBuilderFacadeHelper helper = LinkBuilderFacadeHelper();

  group('LinkParser 正向', () {
    test('解析带凭证的链接', () {
      final ShareLink link = parser.parse('lsf://open?share=share-0001&k=abc.DEF');
      expect(link.shareId.value, 'share-0001');
      expect(link.token, 'abc.DEF');
      expect(link.hasToken, isTrue);
    });

    test('解析不带凭证的链接', () {
      final ShareLink link = parser.parse('lsf://open?share=share-0001');
      expect(link.shareId.value, 'share-0001');
      expect(link.token, isNull);
      expect(link.hasToken, isFalse);
    });

    test('空 k 参数视为无凭证', () {
      final ShareLink link = parser.parse('lsf://open?share=share-0001&k=');
      expect(link.token, isNull);
      expect(link.hasToken, isFalse);
    });

    test('额外查询参数被忽略，不影响解析', () {
      final ShareLink link =
          parser.parse('lsf://open?share=share-0001&k=tok&utm_source=wx');
      expect(link.shareId.value, 'share-0001');
      expect(link.token, 'tok');
    });
  });

  group('LinkParser 负向（5 种非法输入）', () {
    test('空串', () {
      expect(
        () => parser.parse(''),
        throwsA(isA<LanFileException>().having(
          (LanFileException e) => e.code,
          'code',
          LanFileErrorCode.invalidArgument,
        )),
      );
    });

    test('scheme 不对（http 链接）', () {
      expect(
        () => parser.parse('http://open?share=share-0001'),
        throwsA(isA<LanFileException>().having(
          (LanFileException e) => e.code,
          'code',
          LanFileErrorCode.invalidArgument,
        )),
      );
    });

    test('host 不对', () {
      expect(
        () => parser.parse('lsf://other?share=share-0001'),
        throwsA(isA<LanFileException>()),
      );
    });

    test('缺 share 参数', () {
      expect(
        () => parser.parse('lsf://open?k=tok'),
        throwsA(isA<LanFileException>().having(
          (LanFileException e) => e.message,
          'message',
          contains('缺少 share'),
        )),
      );
    });

    test('shareId 格式非法', () {
      expect(
        () => parser.parse('lsf://open?share=bad id!'),
        throwsA(isA<LanFileException>()),
      );
    });

    test('链接带端口必须拒绝（地址泄漏）', () {
      expect(
        () => parser.parse('lsf://open:47778?share=share-0001'),
        throwsA(isA<LanFileException>().having(
          (LanFileException e) => e.message,
          'message',
          contains('端口'),
        )),
      );
    });

    test('链接带 ip/host/port 查询参数必须拒绝', () {
      for (final String key in <String>['ip', 'host', 'port']) {
        expect(
          () => parser.parse('lsf://open?share=share-0001&$key=1.2.3.4'),
          throwsA(isA<LanFileException>().having(
            (LanFileException e) => e.message,
            'message',
            contains('网络定位参数'),
          )),
          reason: '参数 $key 必须被拒绝',
        );
      }
    });

    test('tryParse 非法时返回 null 而不是抛', () {
      expect(parser.tryParse('garbage'), isNull);
      expect(parser.tryParse('lsf://open?share=share-0001'), isNotNull);
    });
  });

  group('ShareLinkBuilder', () {
    test('buildPlain 产出可解析的 lsf 链接且无凭证', () {
      final ShareLinkResult result = helper.buildPlain(ShareId.parse('share-0001'));
      expect(result.text, startsWith('lsf://open?share=share-0001'));
      expect(result.token, isNull);
      result.assertNoNetworkAddress();
      final ShareLink parsed = parser.parse(result.text);
      expect(parsed.shareId, ShareId.parse('share-0001'));
    });

    test('buildSigned 带凭证，round-trip 一致', () async {
      final ShareLinkResult result = await helper.buildSigned(
        shareId: ShareId.parse('share-0001'),
        tokenId: 'jti-1',
      );
      expect(result.token, isNotNull);
      expect(result.token, isNotEmpty);
      final ShareLink parsed = parser.parse(result.text);
      expect(parsed.shareId, ShareId.parse('share-0001'));
      expect(parsed.token, result.token);
    });

    test('硬门禁：链接不含 192.168 / 127.0.0.1 / http:// / 47778', () async {
      final ShareLinkResult result = await helper.buildSigned(
        shareId: ShareId.parse('share-0001'),
        tokenId: 'jti-1',
      );
      final String text = result.text;
      // 逐条断言 false —— 这是验收要求的硬门禁。
      expect(text.contains('192.168.'), isFalse);
      expect(text.contains('127.0.0.1'), isFalse);
      expect(text.contains('http://'), isFalse);
      expect(text.contains('47778'), isFalse);
      expect(text.contains('239.255.'), isFalse);
      result.assertNoNetworkAddress();
    });

    test('门禁能真红：人为塞进 IP 必须抛异常', () {
      // 直接构造一个坏结果，证明 assertNoNetworkAddress 不是空壳。
      final ShareLinkResult bad = ShareLinkResult(
        uri: _evilUri,
        shareId: _evilShareId,
      );
      expect(
        bad.assertNoNetworkAddress,
        throwsA(isA<LanFileException>().having(
          (LanFileException e) => e.message,
          'message',
          contains('网络地址成分'),
        )),
      );
    });
  });
}

/// 简化调用点的小助手：固定一组测试用身份与 codec。
final class LinkBuilderFacadeHelper {
  const LinkBuilderFacadeHelper();

  ShareLinkResult buildPlain(ShareId shareId) =>
      const ShareLinkBuilder().buildPlain(shareId);

  Future<ShareLinkResult> buildSigned({
    required ShareId shareId,
    required String tokenId,
  }) =>
      const ShareLinkBuilder().buildSigned(
        shareId: shareId,
        codec: _TestCodec(),
        issuer: PeerId.parse('p_aaaaaaaaaaaaa'),
        tokenId: tokenId,
        now: DateTime.utc(2026, 1, 1),
      );
}

final Uri _evilUri = Uri.parse('http://192.168.1.5:47778/j/share-0001');
final ShareId _evilShareId = ShareId.parse('share-0001');

/// 极简 codec：只返回固定 token 字符串，不验签（link 层不关心签名）。
final class _TestCodec implements CapabilityCodec {
  @override
  Future<String> issue(CapabilityGrant grant) async => 'fake-token-for-${grant.tokenId}';

  @override
  Future<CapabilityClaims> verify(String token) =>
      throw UnimplementedError('link 层不需要 verify');

  @override
  Future<CapabilityClaims> verifyForSubject(String token, String subject) =>
      throw UnimplementedError('link 层不需要 verifyForSubject');
}
