// SPDX-License-Identifier: GPL-3.0-only
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/ui/widgets/network_diagnostics_setting.dart';

import 'app_controls_test.dart' show harness;

void main() {
  testWidgets('settings entry opens diagnostics only on demand', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness(
        NetworkDiagnosticsEntry(exportLog: ({required save}) async => true),
        scale: 1.5,
      ),
    );
    expect(find.byKey(const ValueKey('share-network-log')), findsNothing);
    expect(find.byKey(const ValueKey('save-network-log')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('open-network-diagnostics')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-network-log')));
    await tester.pumpAndSettle();
    expect(find.text('日志已保存'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('diagnostics-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('save-network-log')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('diagnostic export controls fit a narrow phone with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness(
        RepaintBoundary(
          key: const ValueKey('diagnostic-panel'),
          child: NetworkDiagnosticsSetting(
            exportLog: ({required save}) async => true,
          ),
        ),
        scale: 1.5,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'mobile share/save prevents duplicate requests and handles cancellation',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final calls = <bool>[];
      final pending = Completer<bool>();
      await tester.pumpWidget(
        harness(
          NetworkDiagnosticsSetting(
            exportLog: ({required save}) {
              calls.add(save);
              return calls.length == 1 ? pending.future : Future.value(false);
            },
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('share-network-log')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save-network-log')));
      expect(calls, [false]);
      pending.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('已打开系统分享'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('save-network-log')));
      await tester.pumpAndSettle();
      expect(calls, [false, true]);
      expect(find.text('已取消保存'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('failed export stays visible and permits retry', (tester) async {
    var count = 0;
    await tester.pumpWidget(
      harness(
        NetworkDiagnosticsSetting(
          exportLog: ({required save}) async {
            if (++count == 1) throw StateError('disk unavailable');
            return true;
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('save-network-log')));
    await tester.pumpAndSettle();
    expect(find.textContaining('导出失败'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save-network-log')));
    await tester.pumpAndSettle();
    expect(find.text('日志已保存'), findsOneWidget);
  });
}
