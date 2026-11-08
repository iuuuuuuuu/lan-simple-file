// SPDX-License-Identifier: GPL-3.0-only

@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/miuix_test_support.dart';

import 'package:lan_simple_file/app/branding/app_logo.dart';
import 'package:lan_simple_file/app/theme/app_theme.dart';
import 'package:lan_simple_file/app/theme/tokens.dart';
import 'package:lan_simple_file/ui/pages/settings_page.dart';
import 'package:lan_simple_file/ui/pages/shares_page.dart';
import 'package:lan_simple_file/ui/shell/custom_title_bar.dart';

import 'support/golden_fonts.dart';
import 'support/ui_fakes.dart';

void main() {
  setUpAll(loadGoldenFonts);
  for (final brightness in Brightness.values) {
    for (final page in ['shares', 'logos']) {
      for (final mobile in [false, true]) {
        testWidgets('$page ${brightness.name} mobile=$mobile 视觉快照', (
          tester,
        ) async {
          tester.view.physicalSize = mobile
              ? const Size(360, 800)
              : const Size(1280, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final logo = LogoController();
          addTearDown(logo.dispose);
          final shares = FakeMySharesSource()
            ..webLink = Uri.parse('http://10.168.1.115:47778/s/example')
            ..shares = [
              shareRecord(
                id: 'docs001',
                displayName: '项目资料',
                rootUri: r'D:\工作资料\项目',
              ),
              shareRecord(
                id: 'photos01',
                displayName: '周末旅行照片',
                rootUri: r'D:\照片\2026\秋天',
              ),
              shareRecord(
                id: 'notes001',
                displayName: '会议笔记.pdf',
                rootUri: r'D:\工作资料\会议笔记.pdf',
                kind: 'file',
              ),
              shareRecord(
                id: 'music001',
                displayName: '音乐收藏',
                rootUri: r'D:\媒体\音乐',
                enabled: false,
              ),
              shareRecord(
                id: 'video001',
                displayName: '剪辑素材',
                rootUri: r'D:\视频\素材',
              ),
              shareRecord(
                id: 'archive1',
                displayName: '旧项目归档.zip',
                rootUri: r'D:\备份\旧项目归档.zip',
                kind: 'file',
                missing: true,
              ),
            ];
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => AppMiuixTheme(child: child!),
              theme: withCjkFont(AppTheme.of(LanFilePalette.of(brightness))),
              home: LogoScope(
                controller: logo,
                child: AppScaffold(
                  body: Column(
                    children: [
                      if (!mobile) const CustomTitleBar(),
                      Expanded(
                        child: page == 'shares'
                            ? SharesPage(source: shares)
                            : const SettingsPage(currentUserName: 'Alex'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (page == 'logos') await settleGoldenImages(tester);
          await expectLater(
            find.byType(AppScaffold),
            matchesGoldenFile(
              'goldens/${page}_${brightness.name}${mobile ? '_mobile' : ''}_new.png',
            ),
          );
        });
      }
    }
  }
}
