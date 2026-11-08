// SPDX-License-Identifier: GPL-3.0-only
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/theme/app_theme.dart';
import 'package:lan_simple_file/ui/widgets/app_controls.dart';
import 'package:lan_simple_file/ui/widgets/network_diagnostics_setting.dart';

import 'support/golden_fonts.dart';

void main() {
  setUpAll(loadGoldenFonts);
  testWidgets('network diagnostics mobile at 150 percent text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: withCjkFont(AppTheme.light),
        builder: (context, child) => AppMiuixTheme(
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
        ),
        home: AppScaffold(
          body: NetworkDiagnosticsEntry(
            exportLog: ({required save}) async => true,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-network-diagnostics')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(Navigator),
      matchesGoldenFile('goldens/network_diagnostics_mobile.png'),
    );
  });
}
