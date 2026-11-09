// SPDX-License-Identifier: GPL-3.0-only
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/miuix_test_support.dart';

import 'package:lan_simple_file/app/branding/app_logo.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/ui/pages/settings_page.dart';
import 'package:lan_simple_file/ui/shell/qq_shell.dart';
import 'package:lan_simple_file/app/theme/tokens.dart';
import 'package:lan_simple_file/ui/widgets/avatar_badge.dart';

import 'chat_workspace_test.dart' show ChatTestService;
import 'qq_shell_test.dart' show wrapShell, setViewport;

class BadgeMessaging extends ChatTestService {
  final threads = StreamController<List<ThreadRecord>>.broadcast();
  @override
  Stream<List<ThreadRecord>> watchThreads() => threads.stream;
}

ThreadRecord thread(String id, int unread, {bool deleted = false}) =>
    ThreadRecord(
      id: id,
      kind: 'direct',
      title: 'test',
      avatarHash: '',
      unread: unread,
      muted: false,
      pinned: false,
      createdAt: DateTime.now(),
      deletedAt: deleted ? DateTime.now() : null,
    );
void main() {
  testWidgets('Logo在窄屏名称换行后仍同高，文字放大后保持一致', (tester) async {
    await setViewport(tester, const Size(320, 800));
    await tester.pumpWidget(
      wrapShell(const AppScaffold(body: SettingsPage(currentUserName: 'test'))),
    );
    await tester.pumpAndSettle();
    final rects = AppLogo.values
        .map(
          (logo) =>
              tester.getRect(find.byKey(ValueKey('logo-option-${logo.name}'))),
        )
        .toList();
    expect(rects.map((r) => r.height).toSet().length, 1);
    expect(rects.map((r) => r.top).toSet().length, 1);
    expect(tester.takeException(), isNull);
  });
  for (final mobile in [true, false]) {
    testWidgets('未读数聚合、99+及读后消失 ${mobile ? "mobile" : "desktop"}', (
      tester,
    ) async {
      await setViewport(tester, Size(mobile ? 390 : 1280, 844));
      final messaging = BadgeMessaging();
      addTearDown(messaging.threads.close);
      addTearDown(messaging.updates.close);
      await tester.pumpWidget(wrapShell(QqShell(messaging: messaging)));
      await tester.pumpAndSettle();
      final badge = find.byKey(const ValueKey('chat-unread'));
      messaging.threads.add([
        thread('a', 3),
        thread('b', 2),
        thread('c', 88, deleted: true),
      ]);
      await tester.pumpAndSettle();
      expect(tester.widget<UnreadPill>(badge).count, 5);
      expect(
        find.descendant(of: badge, matching: find.text('5')),
        findsOneWidget,
      );
      if (mobile) {
        await tester.tap(find.byKey(const ValueKey('nav-settings')));
        await tester.pumpAndSettle();
      }
      messaging.threads.add([thread('a', 99), thread('b', 2)]);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: badge, matching: find.text('99+')),
        findsOneWidget,
      );
      messaging.threads.add([thread('a', 0), thread('b', 0)]);
      await tester.pumpAndSettle();
      expect(badge, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('手机状态栏底色跟随联系人背景，切换页面后跟随内容底色', (tester) async {
    await setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(wrapShell(const QqShell()));
    await tester.pumpAndSettle();
    final element = tester.element(
      find.byKey(const ValueKey('mobile-system-background')),
    );
    final t = Theme.of(element).extension<LanFileTokens>()!;
    expect(
      tester
          .widget<ColoredBox>(
            find.byKey(const ValueKey('mobile-system-background')),
          )
          .color,
      t.surfaceSunken,
    );
    await tester.tap(find.byKey(const ValueKey('nav-settings')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ColoredBox>(
            find.byKey(const ValueKey('mobile-system-background')),
          )
          .color,
      t.bg,
    );
  });
}
