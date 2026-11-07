// SPDX-License-Identifier: GPL-3.0-only

/// 取件页资源的静态检查：读真实的 assets/web 文件，不依赖 pubspec 是否声明。
///
/// 这些用例防的是「页面改了但令牌/占位符漏了」这类静默回归：
/// 例如 CSS 少了暗色 token、HTML 少了客户端引导按钮、JS 少了必要接口。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/server/api/share_api.dart';
import 'package:lan_simple_file/core/server/api/tree_api.dart';
import 'package:lan_simple_file/core/server/static/flutter_asset_source.dart';

File asset(String name) => File('assets/web/$name');

void main() {
  group('root catalog', () {
    test(
      'root has search, share rows, owner avatar and offline-safe icons',
      () {
        final html = asset('index.html').readAsStringSync();
        expect(html, contains('id="share-search"'));
        expect(html, contains('id="shared-roots"'));
        expect(html, contains('id="owner-avatar"'));
        expect(html, contains('Lucide icons, ISC License'));
        expect(html, isNot(contains('https://cdn')));
        final js = asset('app.js').readAsStringSync();
        expect(js, contains('/api/v1/shared-roots'));
        expect(js, contains('name.textContent = entry.name'));
        expect(js, isNot(contains('innerHTML')));
      },
    );

    test('share pages link back to all shares', () {
      expect(
        asset('share.html').readAsStringSync(),
        contains('class="back-to-shares" href="/"'),
      );
    });
  });

  group('share.html', () {
    test('携带分享及分享者注入占位符，Windows 引导按平台装配', () {
      final String html = asset('share.html').readAsStringSync();
      expect(html.startsWith('<!DOCTYPE html>'), isTrue);
      expect(html, contains('<!-- SPDX-License-Identifier: GPL-3.0-only -->'));
      expect(html, contains(kShareIdPlaceholder));
      expect(html, contains(kShareNamePlaceholder));
      expect(html, contains(kSharePeerPlaceholder));
      expect(html, contains(kShareOwnerNamePlaceholder));
      expect(html, contains(kShareOwnerAvatarPlaceholder));
      expect(html, contains(kClientDownloadPlaceholder));
      expect(html, isNot(contains('id="download-client"')));
      final fragment = asset(kWindowsClientDownloadAsset).readAsStringSync();
      expect(fragment, contains('id="download-client"'));
      expect(fragment, contains('href="/client/download/windows" download'));
      expect(html, isNot(contains('id="peer-line"')));
      expect(html, contains('/web/share.js'));
      expect(html, contains('/web/style.css'));
    });

    test('占位符只出现在可替换位置，不含其它未定义模板变量', () {
      final String html = asset('share.html').readAsStringSync();
      final Iterable<RegExpMatch> holes = RegExp(r'__LSF_[A-Z_]+__')
          .allMatches(html);
      final Set<String> found = holes
          .map((RegExpMatch m) => m.group(0)!)
          .toSet();
      expect(found, <String>{
        kShareIdPlaceholder,
        kShareNamePlaceholder,
        kSharePeerPlaceholder,
        kShareOwnerNamePlaceholder,
        kShareOwnerAvatarPlaceholder,
        kClientDownloadPlaceholder,
      });
    });
  });

  group('platform client downloads', () {
    for (final enabled in [false, true]) {
      test(
        'client download markup is present only when enabled: $enabled',
        () async {
          final source = FlutterAssetSource(
            fallbackDir: 'assets/web',
            windowsClientDownload: enabled,
          );
          final html = utf8.decode((await source.load('share.html'))!);
          expect(html, isNot(contains(kClientDownloadPlaceholder)));
          expect(html.contains('id="download-client"'), enabled);
          expect(html.contains('/client/download/windows'), enabled);
          expect(
            await source.load('nested/../$kWindowsClientDownloadAsset'),
            enabled ? isNotNull : isNull,
          );
          expect(await source.load('index.html'), isNotNull);
          expect(await source.load('share.js'), isNotNull);
        },
      );
    }
  });

  group('share.js', () {
    test('调用 tree 与 f/ 路由，且做逐段编码', () {
      final String js = asset('share.js').readAsStringSync();
      expect(js.startsWith('// SPDX-License-Identifier: GPL-3.0-only'), isTrue);
      expect(js, contains('/tree?path='));
      expect(js, contains("/f/"));
      expect(js, contains('/zip?path='));
      expect(js, contains('encodeURIComponent'));
      expect(js, contains('mode === "manifest"'), reason: '包装不下时要提示清单模式');
    });
  });

  group('style.css', () {
    test('双色 token 明暗两套齐全，且无第二色相', () {
      final String css = asset('style.css').readAsStringSync();
      expect(
        css.startsWith('/* SPDX-License-Identifier: GPL-3.0-only */'),
        isTrue,
      );
      for (final String token in <String>[
        '--bg',
        '--surface',
        '--line',
        '--fg',
        '--fg-dim',
        '--accent',
      ]) {
        expect(css, contains('$token:'), reason: '缺少 $token');
      }
      expect(css, contains('prefers-color-scheme: dark'));
      expect(css, contains('[data-theme="dark"]'));
      expect(css, contains('[data-theme="light"]'));
      // 明暗两套必须都是计划里的确切色值。
      expect(css, contains('#f7f8fa'));
      expect(css, contains('#0e1116'));
      expect(css, contains('#3b82f6'));
      expect(css, contains('#4f8dfd'));
    });
  });

  group('tree 页契约一致性', () {
    test('tree 默认 limit 与契约 treePageSize 一致', () {
      expect(kTreeDefaultLimit, LanFileConstants.treePageSize);
    });

    test('parseTreeLimit：缺省取契约值，越界按上限裁剪，非法值抛错', () {
      expect(parseTreeLimit(null), LanFileConstants.treePageSize);
      expect(parseTreeLimit(''), LanFileConstants.treePageSize);
      expect(parseTreeLimit('7'), 7);
      expect(parseTreeLimit('999999'), kTreeMaxLimit);
      expect(
        () => parseTreeLimit('abc'),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.invalidArgument,
          ),
        ),
      );
      expect(() => parseTreeLimit('0'), throwsA(isA<LanFileException>()));
    });
  });
}
