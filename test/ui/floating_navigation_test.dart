// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/ui/shell/qq_shell.dart';
import 'package:lan_simple_file/ui/shell/session_rail.dart';
import 'package:lan_simple_file/ui/widgets/app_controls.dart';
import 'package:lan_simple_file/ui/widgets/floating_navigation.dart';
import 'package:lan_simple_file/ui/pages/shares_page.dart';
import 'package:lan_simple_file/ui/widgets/share_drag_grid.dart';
import 'package:lan_simple_file/ui/widgets/share_row.dart';

import 'qq_shell_test.dart' show setViewport, wrapShell;
import 'support/ui_fakes.dart' show FakeMySharesSource, shareRecord;

Finder indicator() => find.descendant(
  of: find.byType(MiuixGlassNavigationBar),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is AnimatedContainer &&
        widget.decoration is ShapeDecoration &&
        (widget.decoration! as ShapeDecoration).shape is StadiumBorder,
  ),
);

void main() {
  for (final width in [320.0, 600.0, 1280.0]) {
    testWidgets('share action and final card clear the floating bar $width', (
      tester,
    ) async {
      await setViewport(tester, Size(width, 800));
      final source = FakeMySharesSource()
        ..shares = [
          for (var i = 0; i < 30; i++)
            shareRecord(
              id: 'share$i',
              displayName: 'Share ${i.toString().padLeft(2, '0')}',
            ),
        ];
      await tester.pumpWidget(
        wrapShell(
          AppScaffold(
            extendBody: true,
            bottomNavigationBar: FloatingNavigation(
              selected: ShellSection.shares,
              onSelect: (_) {},
            ),
            body: FloatingNavigationInsets(
              bottom: 68,
              child: SharesPage(source: source, onCreateShare: () async {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bar = tester.getRect(find.byKey(const ValueKey('app-navigation')));
      final action = tester.getRect(
        find.byKey(const ValueKey('share-create-fab')),
      );
      expect(action.overlaps(bar.inflate(8)), isFalse);
      if (width >= 600) expect(action.bottom, 784);
      final scrollable = find.descendant(
        of: find.byType(ShareDragGrid),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      final last = find.ancestor(
        of: find.text('Share 29'),
        matching: find.byType(ShareRow),
      );
      expect(tester.getRect(last).bottom, lessThan(bar.top));
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in [320.0, 1280.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'glass selection follows drag and springs into place $width $brightness',
        (tester) async {
          await setViewport(tester, Size(width, 800));
          var selected = ShellSection.nearby;
          await tester.pumpWidget(
            wrapShell(
              StatefulBuilder(
                builder: (context, setState) => AppScaffold(
                  extendBody: true,
                  body: const SizedBox.expand(),
                  bottomNavigationBar: FloatingNavigation(
                    selected: selected,
                    unread: 101,
                    onSelect: (value) => setState(() => selected = value),
                  ),
                ),
              ),
              brightness: brightness,
            ),
          );
          await tester.pumpAndSettle();
          final bar = tester.getRect(
            find.byKey(const ValueKey('app-navigation')),
          );
          final before = tester.getRect(indicator());
          expect(
            before.contains(
              tester.getCenter(find.byKey(const ValueKey('nav-nearby'))),
            ),
            isTrue,
          );
          final decoration =
              tester.widget<AnimatedContainer>(indicator()).decoration!
                  as ShapeDecoration;
          expect(decoration.color!.a, greaterThan(.05));
          expect(bar.bottom, 788);
          expect(bar.left, greaterThanOrEqualTo(12));
          final target = tester.getCenter(
            find.byKey(const ValueKey('nav-settings')),
          );
          final gesture = await tester.startGesture(before.center);
          await gesture.moveTo(Offset(bar.center.dx, target.dy));
          await tester.pump(const Duration(milliseconds: 40));
          final moving = tester.getRect(indicator());
          expect(moving.center.dx, greaterThan(before.center.dx));
          expect(moving.center.dx, lessThan(target.dx));
          await gesture.moveTo(target);
          await gesture.up();
          await tester.pumpAndSettle();
          expect(selected, ShellSection.settings);
          expect(tester.getRect(indicator()).contains(target), isTrue);
          final cancelled = await tester.startGesture(target);
          await cancelled.moveTo(before.center);
          await cancelled.cancel();
          await tester.pumpAndSettle();
          expect(selected, ShellSection.settings);
          expect(tester.getRect(indicator()).contains(target), isTrue);
          final shares = find.byKey(const ValueKey('nav-shares'));
          Focus.of(tester.element(shares)).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(selected, ShellSection.shares);
          expect(
            tester.getRect(indicator()).contains(tester.getCenter(shares)),
            isTrue,
          );
          expect(find.text('99+'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('mobile safe area is applied once and keyboard hides the bar', (
    tester,
  ) async {
    await setViewport(tester, const Size(390, 844));
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    tester.view.padding = const FakeViewPadding(bottom: 24);
    await tester.pumpWidget(wrapShell(const QqShell()));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const ValueKey('app-navigation'))).bottom,
      808,
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('shell-list'))).bottom,
      844,
    );
    await tester.tap(find.byKey(const ValueKey('nav-transfers')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<MiuixGlassNavigationBar>(find.byType(MiuixGlassNavigationBar))
          .selectedIndex,
      2,
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(find.byType(MiuixGlassNavigationBar), findsNothing);
    expect(
      tester
          .widget<FloatingNavigationInsets>(
            find.byType(FloatingNavigationInsets),
          )
          .bottom,
      0,
    );
    expect(tester.takeException(), isNull);
  });
}
