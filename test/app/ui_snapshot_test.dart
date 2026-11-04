// SPDX-License-Identifier: GPL-3.0-only

/// 界面快照：用 Flutter 真实光栅化导出外壳的明/暗两套图，作为视觉证据。
///
/// 运行方式（会写出 PNG，不参与常规断言）：
///   flutter test test/app/ui_snapshot_test.dart --update-goldens
/// 产物在 test/app/goldens/ 下，可直接打开查看。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/app.dart';
import 'package:lan_simple_file/app/theme/app_theme.dart';

import '../ui/support/golden_fonts.dart';

Future<void> _pump(WidgetTester tester, AppThemeMode mode) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final ProviderContainer c = ProviderContainer();
  addTearDown(c.dispose);
  await c.read(themeModeProvider.notifier).setMode(mode);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: c, child: const LanFileApp()),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadGoldenFonts);
  testWidgets('明色外壳快照', (WidgetTester tester) async {
    await _pump(tester, AppThemeMode.light);
    await expectLater(
      find.byType(LanFileApp),
      matchesGoldenFile('goldens/home_light.png'),
    );
  });

  testWidgets('暗色外壳快照', (WidgetTester tester) async {
    await _pump(tester, AppThemeMode.dark);
    await expectLater(
      find.byType(LanFileApp),
      matchesGoldenFile('goldens/home_dark.png'),
    );
  });
}
