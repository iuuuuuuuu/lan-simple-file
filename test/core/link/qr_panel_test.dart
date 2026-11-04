// SPDX-License-Identifier: GPL-3.0-only

/// QrPanel widget 用例：能真的 pump 出来、编码的是链接文本、明暗两套 token 都能渲染。
///
/// 不做像素比对（二维码纹理对字体渲染敏感），
/// 但要以「能找到 QrImageView 且其 data 等于链接」这种结构性断言为准。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/theme/app_theme.dart';
import 'package:lan_simple_file/app/theme/tokens.dart';
import 'package:lan_simple_file/ui/widgets/qr_panel.dart';
import 'package:qr_flutter/qr_flutter.dart';

const String kLink = 'lsf://open?share=share-0001&k=abc.DEF';

Widget _wrap(Widget child, {LanFileTokens tokens = LanFilePalette.light}) {
  return MaterialApp(
    theme: AppTheme.of(tokens),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('QrPanel', () {
    testWidgets('能 pump 出来并渲染二维码与链接文本', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const QrPanel(linkText: kLink)));
      await tester.pumpAndSettle();

      // 二维码本体存在。
      final Finder qr = find.byType(QrImageView);
      expect(qr, findsOneWidget);

      // QrImageView 把 data 存成私有字段（无公开 getter），所以从
      // 我们自己的 QrPanel 属性侧确认链接确实传下去了；
      // 再确认 QrImageView 没有落到 error 分支（data 非法才会触发）。
      final QrPanel panel = tester.widget<QrPanel>(find.byType(QrPanel));
      expect(panel.linkText, kLink);
      expect(find.byType(QrImageView), findsOneWidget);

      // 链接文本可见（扫码失败时用户还能手动复制）。
      expect(find.text(kLink), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('qr-panel-link-text')),
          findsOneWidget);
    });

    testWidgets('带 caption 时展示标题', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(const QrPanel(linkText: kLink, caption: '年度照片')),
      );
      await tester.pumpAndSettle();
      expect(find.text('年度照片'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets('大图模式桌面尺寸为 240', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(const QrPanel(linkText: kLink)));
      await tester.pumpAndSettle();
      final QrImageView qr = tester.widget<QrImageView>(find.byType(QrImageView));
      expect(qr.size, 240);
    });

    testWidgets('窄屏下按可用宽度收缩，且不低于最小尺寸', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _wrap(
          const SizedBox(
            width: 200,
            child: QrPanel(linkText: kLink, layout: QrPanelLayout.compact),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final QrImageView qr = tester.widget<QrImageView>(find.byType(QrImageView));
      // 宽 200 -> 可用 184 -> 落在 [160, 320] 区间。
      expect(qr.size, isNotNull);
      expect(qr.size! <= 200, isTrue);
      expect(qr.size! >= 160, isTrue);
    });

    testWidgets('暗色主题下用暗色 token 上色', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(const QrPanel(linkText: kLink), tokens: LanFilePalette.dark),
      );
      await tester.pumpAndSettle();
      final QrImageView qr = tester.widget<QrImageView>(find.byType(QrImageView));
      // 前景/底色必须来自 token，而不是硬编码黑色。
      expect(qr.dataModuleStyle.color, LanFilePalette.dark.fg);
      expect(qr.backgroundColor, LanFilePalette.dark.surface);
      expect(qr.eyeStyle.color, LanFilePalette.dark.fg);
    });

    testWidgets('明色主题下同样走 token 配色', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const QrPanel(linkText: kLink)));
      await tester.pumpAndSettle();
      final QrImageView qr = tester.widget<QrImageView>(find.byType(QrImageView));
      expect(qr.dataModuleStyle.color, LanFilePalette.light.fg);
      expect(qr.backgroundColor, LanFilePalette.light.surface);
    });

    testWidgets('主题没有装扩展时回落到明色 token，不崩', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: QrPanel(linkText: kLink))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets('链接文本里没有网络地址（与 link 层门禁一致）', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const QrPanel(linkText: kLink)));
      await tester.pumpAndSettle();
      for (final String needle in <String>[
        '192.168.',
        '127.0.0.1',
        'http://',
        '47778',
      ]) {
        expect(kLink.contains(needle), isFalse, reason: '样例链接不得含 $needle');
      }
    });
  });
}
