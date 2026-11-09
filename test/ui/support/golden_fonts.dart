// SPDX-License-Identifier: GPL-3.0-only
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settleGoldenImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    for (final widget in tester.widgetList<Image>(find.byType(Image))) {
      await precacheImage(
        widget.image,
        tester.element(find.byType(Image).first),
      );
    }
  });
  await tester.pumpAndSettle();
}

/// 在离屏截图中加载中文和图标字体，不影响产品使用的主题。
Future<void> loadGoldenFonts() async {
  final cjk = File(r'C:\Windows\Fonts\simhei.ttf');
  if (!cjk.existsSync()) {
    throw StateError('缺少截图所需的中文字体：${cjk.path}');
  }
  Future<void> load(String family, File file) async {
    final bytes = await file.readAsBytes();
    await (FontLoader(
      family,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  }

  // Windows Material 主题使用 Segoe UI；显式截图主题使用 TestCJK。
  for (final family in ['TestCJK', 'Segoe UI', 'Roboto']) {
    await load(family, cjk);
  }
  final configFile = File('.dart_tool/package_config.json').absolute;
  final config = jsonDecode(await configFile.readAsString()) as Map;
  Uri packageRoot(String name) {
    final package = (config['packages'] as List).cast<Map>().firstWhere(
      (package) => package['name'] == name,
    );
    final root = configFile.uri.resolve(package['rootUri'] as String);
    return Uri.parse('${root.toString().replaceFirst(RegExp(r'/$'), '')}/');
  }

  await load(
    'MaterialIcons',
    File.fromUri(
      packageRoot('flutter').resolve(
        '../../bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    ),
  );
  await load(
    'packages/lucide_icons_flutter/Lucide',
    File.fromUri(
      packageRoot('lucide_icons_flutter').resolve('assets/lucide.ttf'),
    ),
  );
}

ThemeData withCjkFont(ThemeData base) => base.copyWith(
  textTheme: base.textTheme.apply(fontFamily: 'TestCJK'),
  primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'TestCJK'),
);
