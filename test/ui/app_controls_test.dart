// SPDX-License-Identifier: GPL-3.0-only

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/theme/app_theme.dart';
import 'package:lan_simple_file/ui/widgets/app_controls.dart';
import 'package:lan_simple_file/ui/widgets/edit_name_dialog.dart';

Widget harness(
  Widget child, {
  Brightness brightness = Brightness.light,
  double scale = 1,
}) => MaterialApp(
  theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
  builder: (context, child) => AppMiuixTheme(
    child: MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
  ),
  home: AppScaffold(body: child),
);

void main() {
  testWidgets(
    'menu keyboard selection skips disabled entries and long names fit mobile',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      String? selected;
      await tester.pumpWidget(
        harness(
          AppMenuButton<String>(
            onSelected: (value) => selected = value,
            itemBuilder: (_) => [
              const AppMenuItem(value: 'first', label: 'First'),
              const AppMenuItem(
                value: 'disabled',
                label: 'Disabled',
                enabled: false,
              ),
              AppMenuItem(
                value: 'last',
                label: List.filled(12, 'Long group name').join(' '),
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.byType(AppMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected, 'last');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tooltip follows theme and bounds, and unmounts with anchor', (
    tester,
  ) async {
    Widget page(Brightness brightness) => harness(
      const Align(
        alignment: Alignment.bottomRight,
        child: AppTooltip(
          message: 'A tooltip at the screen edge',
          child: SizedBox(width: 40, height: 40),
        ),
      ),
      brightness: brightness,
    );
    await tester.pumpWidget(page(Brightness.light));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.byType(AppTooltip)));
    await tester.pumpAndSettle();
    expect(find.byType(MiuixPlainTooltip), findsOneWidget);
    final rect = tester.getRect(find.byType(MiuixPlainTooltip));
    expect(rect.left, greaterThanOrEqualTo(8));
    expect(rect.right, lessThanOrEqualTo(792));
    expect(rect.bottom, lessThanOrEqualTo(592));
    await tester.pumpWidget(page(Brightness.dark));
    await tester.pumpAndSettle();
    final tooltipContext = tester.element(find.byType(MiuixPlainTooltip));
    expect(
      MiuixTheme.of(tooltipContext).colors.primary,
      MiuixThemeData.of(Brightness.dark).colors.primary,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(harness(const SizedBox.shrink()));
    await tester.pumpAndSettle();
    expect(find.byType(MiuixPlainTooltip), findsNothing);
    await mouse.removePointer();
  });

  for (final dismissible in [true, false]) {
    testWidgets('dialog Escape and outside dismissal: $dismissible', (
      tester,
    ) async {
      bool completed = false;
      await tester.pumpWidget(
        harness(
          Builder(
            builder: (context) => AppButton(
              onPressed: () async {
                await showAppDialog<void>(
                  context: context,
                  barrierDismissible: dismissible,
                  builder: (_) =>
                      const EditNameDialog(title: 'Name', label: 'Name'),
                );
                completed = true;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(completed, dismissible);
      if (!dismissible) {
        await tester.tapAt(const Offset(4, 4));
        await tester.pumpAndSettle();
        expect(completed, isFalse);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
      }
      expect(find.byType(AppDialog), findsNothing);
      expect(completed, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'mobile name dialog keeps save reachable above keyboard with large text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      String? result;
      await tester.pumpWidget(
        harness(
          Builder(
            builder: (context) => AppButton(
              onPressed: () async => result = await showAppDialog<String>(
                context: context,
                builder: (_) =>
                    const EditNameDialog(title: 'Edit name', label: 'Name'),
              ),
              child: const Text('Open'),
            ),
          ),
          scale: 1.5,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(AppTextField), 'new name');
      final save = find.widgetWithText(AppButton, '保存');
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(340));
      expect(save.hitTestable(), findsOneWidget);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(result, 'new name');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'text limit waits for IME commit and external controller survives unmount',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        harness(AppTextField(controller: controller, maxLength: 3)),
      );
      await tester.showKeyboard(find.byType(AppTextField));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'abcdef',
          selection: TextSelection.collapsed(offset: 6),
          composing: TextRange(start: 0, end: 6),
        ),
      );
      await tester.pump();
      expect(controller.text, 'abcdef');
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'abcdef',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      await tester.pump();
      expect(controller.text, 'abc');
      await tester.pumpWidget(harness(const SizedBox.shrink()));
      controller.text = 'still owned by caller';
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'icon command activates from keyboard and honors disabled state',
    (tester) async {
      var calls = 0;
      Widget page(bool enabled) => harness(
        AppIconButton(
          onPressed: enabled ? () => calls++ : null,
          icon: const Icon(Icons.copy),
        ),
      );
      await tester.pumpWidget(page(true));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.pumpWidget(page(false));
      await tester.tap(find.byType(AppIconButton));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(calls, 1);
    },
  );
}
