// SPDX-License-Identifier: GPL-3.0-only
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/theme/app_theme.dart';
import 'package:lan_simple_file/core/messaging/chat_search.dart';
import 'package:lan_simple_file/ui/pages/transfer_history_page.dart';
import 'package:lan_simple_file/ui/shell/session_rail.dart';
import 'package:lan_simple_file/ui/widgets/app_controls.dart';
import 'package:lan_simple_file/ui/widgets/chat_search_dialog.dart';
import 'package:lan_simple_file/ui/widgets/floating_navigation.dart';

import '../core/messaging/chat_search_test.dart'
    show searchThread, searchMessage;
import 'chat_search_test.dart' show TestChatSearch;
import 'transfer_history_test.dart' show TestHistory;
import 'support/golden_fonts.dart';

void main() {
  setUpAll(loadGoldenFonts);
  for (final mobile in [true, false]) {
    testWidgets(
      'navigation, transfer history and search ${mobile ? 'mobile' : 'desktop'}',
      (tester) async {
        tester.view.physicalSize = mobile
            ? const Size(390, 844)
            : const Size(1280, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final history = TestHistory();
        addTearDown(history.updates.close);
        final search = TestChatSearch()
          ..respond = (_) async => [
            ChatSearchHit(
              searchThread('工作群'),
              searchMessage('one', body: '项目计划已经更新，文件在我的分享里。'),
            ),
          ];
        Widget wrap(Widget body) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: withCjkFont(AppTheme.light),
          builder: (context, child) => AppMiuixTheme(child: child!),
          home: AppScaffold(
            extendBody: true,
            body: FloatingNavigationInsets(bottom: 68, child: body),
            bottomNavigationBar: FloatingNavigation(
              selected: ShellSection.transfers,
              unread: 101,
              onSelect: (_) {},
            ),
          ),
        );
        await tester.pumpWidget(wrap(TransferHistoryPage(source: history)));
        await tester.pumpAndSettle();
        await settleGoldenImages(tester);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(Navigator),
          matchesGoldenFile(
            'goldens/transfer_history_${mobile ? 'mobile' : 'desktop'}.png',
          ),
        );
        await tester.pumpWidget(wrap(ChatSearchDialog(source: search)));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('chat-history-search')),
          '项目',
        );
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pumpAndSettle();
        await settleGoldenImages(tester);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(Navigator),
          matchesGoldenFile(
            'goldens/chat_search_${mobile ? 'mobile' : 'desktop'}.png',
          ),
        );
      },
    );
  }
}
