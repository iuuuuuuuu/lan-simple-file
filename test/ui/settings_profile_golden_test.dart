// SPDX-License-Identifier: GPL-3.0-only
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/theme/app_theme.dart';
import 'package:lan_simple_file/ui/pages/settings_page.dart';
import 'package:lan_simple_file/ui/widgets/app_controls.dart';

import 'requested_features_test.dart' show png;
import 'settings_page_test.dart' show FakeSettingsSource, snapshotOf;
import 'support/golden_fonts.dart';

void main() {
  setUpAll(loadGoldenFonts);
  testWidgets('compact profile actions on mobile at 150 percent text', (
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
          body: SettingsPage(
            source: FakeSettingsSource(snapshotOf()),
            avatarPicker: () async => png,
            saveAvatar: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-avatar-button')));
    await tester.pumpAndSettle();
    await settleGoldenImages(tester);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(Navigator),
      matchesGoldenFile('goldens/settings_profile_mobile.png'),
    );
  });
}
