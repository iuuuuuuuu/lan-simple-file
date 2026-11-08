// SPDX-License-Identifier: GPL-3.0-only
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/theme/app_theme.dart';
import 'package:lan_simple_file/ui/widgets/app_controls.dart';

import 'peer_shares_dialog_test.dart' show sharesDialog;
import 'support/golden_fonts.dart';

void main() {
  setUpAll(loadGoldenFonts);
  for (final mobile in [true, false]) {
    testWidgets('peer shares ${mobile ? 'mobile' : 'desktop'}', (tester) async {
      tester.view.physicalSize = mobile
          ? const Size(360, 640)
          : const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: withCjkFont(mobile ? AppTheme.light : AppTheme.dark),
          builder: (context, child) => AppMiuixTheme(
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(mobile ? 1.5 : 1)),
              child: child!,
            ),
          ),
          home: AppScaffold(
            body: Builder(
              builder: (context) => AppButton(
                onPressed: () => showAppDialog<void>(
                  context: context,
                  builder: (_) => sharesDialog(),
                ),
                child: const Text('show'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('show'));
      await tester.pumpAndSettle();
      await settleGoldenImages(tester);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Navigator),
        matchesGoldenFile(
          'goldens/peer_shares_${mobile ? 'mobile' : 'desktop'}.png',
        ),
      );
    });
  }
}
