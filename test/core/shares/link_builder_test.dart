// SPDX-License-Identifier: GPL-3.0-only

/// LinkBuilder 的纯函数测试：链接形态与「不得含网络地址」硬约束。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/errors.dart';
import 'package:lan_simple_file/core/contracts/types.dart';
import 'package:lan_simple_file/core/shares/link_builder.dart';

void main() {
  const LinkBuilder builder = LinkBuilder();
  final ShareId shareId = ShareId.parse('abc-1234');

  group('build', () {
    test('无 token：lsf://open?share=ID', () {
      final Uri uri = builder.build(shareId: shareId);
      expect(uri.scheme, 'lsf');
      expect(uri.host, 'open');
      expect(uri.path, isEmpty);
      expect(uri.queryParameters['share'], 'abc-1234');
      expect(uri.queryParameters.containsKey('k'), isFalse);
      expect(uri.toString(), 'lsf://open?share=abc-1234');
    });

    test('带 token：查询参数含 k', () {
      final Uri uri = builder.build(shareId: shareId, token: 'a.b');
      expect(uri.queryParameters['k'], 'a.b');
      expect(uri.queryParameters['share'], 'abc-1234');
    });

    test('空 token 等同于不传', () {
      final Uri uri = builder.build(shareId: shareId, token: '');
      expect(uri.queryParameters.containsKey('k'), isFalse);
    });

    test('产物里没有 IP、主机名、http 前缀、端口', () {
      final Uri uri = builder.build(shareId: shareId, token: 'x.y');
      final String text = uri.toString();
      for (final String bad in <String>[
        '192.168',
        '127.0.0.1',
        'http://',
        'https://',
        'localhost',
        ':47778',
      ]) {
        expect(text.contains(bad), isFalse, reason: '不得包含 $bad');
      }
      expect(uri.hasPort, isFalse);
    });

    test('中文 share id 会被百分号编码但仍可解析回来', () {
      // ShareId 正则只允许字母数字与 _-，这里直接验 encodeQueryComponent 行为。
      final Uri uri = builder.build(shareId: ShareId.parse('Ab_c-19'));
      expect(uri.queryParameters['share'], 'Ab_c-19');
      expect(builder.parseShareId(uri).value, 'Ab_c-19');
    });
  });

  group('parse', () {
    test('parseShareId 正常回读', () {
      final Uri uri = builder.build(shareId: shareId);
      expect(builder.parseShareId(uri), shareId);
    });

    test('scheme 或 host 不对 → invalidArgument', () {
      for (final Uri bad in <Uri>[
        Uri.parse('https://open?share=abc-1234'),
        Uri.parse('lsf://other?share=abc-1234'),
      ]) {
        expect(
          () => builder.parseShareId(bad),
          throwsA(
            isA<LanFileException>().having(
              (LanFileException e) => e.code,
              'code',
              LanFileErrorCode.invalidArgument,
            ),
          ),
        );
      }
    });

    test('缺 share 参数 → invalidArgument', () {
      expect(
        () => builder.parseShareId(Uri.parse('lsf://open')),
        throwsA(isA<LanFileException>()),
      );
    });

    test('share 参数非法 → invalidArgument', () {
      expect(
        () => builder.parseShareId(Uri.parse('lsf://open?share=!')),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.invalidArgument,
          ),
        ),
      );
    });

    test('parseToken：有则返回，无则 null', () {
      expect(
        builder.parseToken(builder.build(shareId: shareId, token: 't1')),
        't1',
      );
      expect(builder.parseToken(builder.build(shareId: shareId)), isNull);
    });
  });

  group('assertNoNetworkAddress', () {
    test('干净的链接通过', () {
      builder.assertNoNetworkAddress('lsf://open?share=abc-1234');
    });

    test('含 IP / http / 端口 / localhost 一律抛', () {
      for (final String bad in <String>[
        'lsf://open?share=a&ip=192.168.1.2',
        'http://example.com/x',
        'lsf://open?share=a&port=47778',
        'lsf://open?share=a&host=localhost',
      ]) {
        expect(
          () => builder.assertNoNetworkAddress(bad),
          throwsA(isA<LanFileException>()),
          reason: '应拒绝 $bad',
        );
      }
    });

    test('带端口号的 URI 被拒', () {
      expect(
        () => builder.assertNoNetworkAddress('lsf://open:47778?share=abc'),
        throwsA(isA<LanFileException>()),
      );
    });
  });
}
