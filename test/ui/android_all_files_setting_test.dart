// SPDX-License-Identifier: GPL-3.0-only

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/miuix_test_support.dart';

import 'package:lan_simple_file/platform/android/permission_flow.dart';
import 'package:lan_simple_file/ui/widgets/android_all_files_setting.dart';

import 'qq_shell_test.dart' show setViewport, wrapShell;

void main() {
  const channel = MethodChannel(kPermissionChannelName);
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('打开设置不修改授权状态，返回前台后重新读取授权及撤销', (tester) async {
    await setViewport(tester, const Size(360, 616));
    var state = 'denied';
    var requests = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'queryStates') return {'allFilesAccess': state};
      requests++;
      return null;
    });
    await tester.pumpWidget(
      wrapShell(const AppScaffold(body: AndroidAllFilesSetting())),
    );
    await tester.pumpAndSettle();
    expect(find.text('未授权'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('all-files-settings')));
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.text('未授权'), findsOneWidget);
    state = 'granted';
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('已授权'), findsOneWidget);
    state = 'denied';
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('未授权'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('请求期间禁用重复操作，失败显示真实错误', (tester) async {
    final request = Completer<Object?>();
    var requests = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'queryStates') return {'allFilesAccess': 'denied'};
      requests++;
      return request.future;
    });
    await tester.pumpWidget(
      wrapShell(const AppScaffold(body: AndroidAllFilesSetting())),
    );
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('all-files-settings'));
    await tester.tap(button);
    await tester.pump();
    expect(tester.widget<AppIconButton>(button).onPressed, isNull);
    await tester.tap(button);
    expect(requests, 1);
    request.completeError(
      PlatformException(code: 'settingsUnavailable', message: '系统没有提供设置页'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('系统没有提供设置页'), findsOneWidget);
    expect(find.text('未授权'), findsOneWidget);
    expect(tester.widget<AppIconButton>(button).onPressed, isNotNull);
  });

  testWidgets('旧版系统不可发起请求，通道未知不显示已授权', (tester) async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => {'allFilesAccess': 'notRequired'},
    );
    await tester.pumpWidget(
      wrapShell(const AppScaffold(body: AndroidAllFilesSetting())),
    );
    await tester.pumpAndSettle();
    expect(find.text('不适用'), findsOneWidget);
    expect(
      tester
          .widget<AppIconButton>(
            find.byKey(const ValueKey('all-files-settings')),
          )
          .onPressed,
      isNull,
    );
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => throw MissingPluginException(),
    );
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('状态未知'), findsOneWidget);
    expect(find.text('已授权'), findsNothing);
  });
}
