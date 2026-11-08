// SPDX-License-Identifier: GPL-3.0-only
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/miuix_test_support.dart';

import 'package:lan_simple_file/ui/shell/close_behavior.dart';
import 'package:lan_simple_file/ui/pages/settings_page.dart';
import 'package:lan_simple_file/app/theme/app_theme.dart';

void main() {
  late Map<String, String> settings;
  late int prompts;
  late int hides;
  late int exits;
  late List<Object> errors;
  late CloseAction? selected;
  late CloseBehavior behavior;

  setUp(() {
    settings = {};
    prompts = hides = exits = 0;
    errors = [];
    selected = CloseAction.tray;
    behavior = CloseBehavior(
      read: () async => settings[CloseBehavior.settingKey],
      write: (value) async => settings[CloseBehavior.settingKey] = value,
      choose: () async {
        prompts++;
        return selected;
      },
      hide: () async => hides++,
      exit: () async => exits++,
      reportError: errors.add,
    )..trayReady = true;
  });

  test('首次选择托盘落库，恢复设置后不再询问', () async {
    await behavior.hydrate();
    await behavior.requestClose();
    expect(prompts, 1);
    expect(hides, 1);
    expect(settings[CloseBehavior.settingKey], 'tray');
    behavior.value = CloseAction.ask;
    await behavior.hydrate();
    await behavior.requestClose();
    expect(prompts, 1);
    expect(hides, 2);
    expect(exits, 0);
  });

  test('取消不保存、不隐藏；首次彻底退出保存并只执行一次', () async {
    selected = null;
    await behavior.requestClose();
    expect(settings, isEmpty);
    expect(hides + exits, 0);
    selected = CloseAction.exit;
    await behavior.requestClose();
    await behavior.requestClose();
    expect(exits, 1);
    expect(settings[CloseBehavior.settingKey], 'exit');
  });

  test('托盘失败不隐藏、不记住不可用选择', () async {
    behavior.trayReady = false;
    await behavior.requestClose();
    expect(hides, 0);
    expect(settings, isEmpty);
    expect(errors, hasLength(1));
    await behavior.setAction(CloseAction.tray);
    await behavior.requestClose();
    expect(hides, 0);
    expect(errors, hasLength(2));
    await behavior.requestClose(forceExit: true);
    expect(exits, 1);
  });

  test('保存失败不关闭，重复关闭请求只询问一次', () async {
    final completer = Completer<CloseAction?>();
    behavior = CloseBehavior(
      read: () async => null,
      write: (_) async => throw StateError('写入失败'),
      choose: () {
        prompts++;
        return completer.future;
      },
      hide: () async => hides++,
      exit: () async => exits++,
      reportError: errors.add,
    )..trayReady = true;
    final pending = behavior.requestClose();
    await behavior.requestClose();
    completer.complete(CloseAction.tray);
    await pending;
    expect(prompts, 1);
    expect(hides + exits, 0);
    expect(behavior.value, CloseAction.ask);
    expect(errors, hasLength(1));
  });

  testWidgets('设置修改关闭策略立即落库并生效', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppMiuixTheme(child: child!),
        theme: AppTheme.light,
        home: CloseBehaviorScope(
          behavior: behavior,
          child: const AppScaffold(body: SettingsPage(currentUserName: '测试')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('关闭窗口时'));
    await tester.tap(find.byType(MiuixOverlayDropdownMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('彻底退出').last);
    await tester.pumpAndSettle();
    expect(settings[CloseBehavior.settingKey], 'exit');
    await behavior.requestClose();
    expect(exits, 1);
    expect(prompts, 0);
  });
}
