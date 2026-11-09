// SPDX-License-Identifier: GPL-3.0-only
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/theme/app_theme.dart';
import 'package:lan_simple_file/core/shares/share_organization.dart';
import 'package:lan_simple_file/ui/pages/shares_page.dart';
import 'package:lan_simple_file/ui/widgets/app_controls.dart';

import 'share_organization_test.dart' show TestOrganizationSource;
import 'support/ui_fakes.dart';
import 'support/golden_fonts.dart';
import 'support/miuix_test_support.dart' show findAppTooltip;

void main() {
  setUpAll(loadGoldenFonts);
  for (final mobile in [true, false]) {
    testWidgets('share organization ${mobile ? 'mobile' : 'desktop'}', (
      tester,
    ) async {
      tester.view.physicalSize = mobile
          ? const Size(390, 844)
          : const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final source = FakeMySharesSource()
        ..shares = [
          shareRecord(id: 'work', displayName: '工作资料'),
          shareRecord(id: 'photos', displayName: '旅行照片与视频'),
          shareRecord(id: 'readme', displayName: '项目计划.pdf', kind: 'file'),
        ];
      final groups = TestOrganizationSource()
        ..value = const ShareOrganization(
          names: {'work': '工作', 'photos': '生活'},
          assignments: {'work': 'work', 'readme': 'work', 'photos': 'photos'},
          groupOrder: ['work', 'photos', ''],
          order: ['readme', 'work', 'photos'],
        );
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: withCjkFont(mobile ? AppTheme.light : AppTheme.dark),
          builder: (context, child) => AppMiuixTheme(
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(mobile ? 1.3 : 1)),
              child: child!,
            ),
          ),
          home: AppScaffold(
            body: SharesPage(
              source: source,
              onCreateShare: () async {},
              organizationSource: groups,
              homeLink: () async =>
                  Uri.parse('http://haohaochifan.p-aaaaaaaaaaaaa.local:47778/'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await settleGoldenImages(tester);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Navigator),
        matchesGoldenFile(
          'goldens/share_groups_${mobile ? 'mobile' : 'desktop'}.png',
        ),
      );
      await tester.tap(findAppTooltip('分组与排序'));
      await tester.pumpAndSettle();
      await settleGoldenImages(tester);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Navigator),
        matchesGoldenFile(
          'goldens/share_order_${mobile ? 'mobile' : 'desktop'}.png',
        ),
      );
    });
  }
}
