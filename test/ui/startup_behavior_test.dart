// SPDX-License-Identifier: GPL-3.0-only
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/theme/app_theme.dart';
import 'package:lan_simple_file/core/store/store_impl.dart';
import 'package:lan_simple_file/ui/shell/startup_behavior.dart';
import 'package:lan_simple_file/ui/widgets/silent_startup_setting.dart';

void main() {
  for (final saved in [null, 'false', 'invalid']) {
    test('normal startup shows after tray initialization: $saved', () async {
      final events = <String>[];
      final behavior = StartupBehavior(
        read: () async => saved,
        write: (_) async {},
      );
      addTearDown(behavior.dispose);
      await behavior.launch(
        arguments: [],
        initializeTray: () async {
          events.add('tray');
          return true;
        },
        show: () async => events.add('show'),
      );
      expect(events, ['tray', 'show']);
    });
  }

  test('saved silent preference survives reopening SQLite', () async {
    final dir = await Directory.systemTemp.createTemp('silent-startup-');
    final file = File('${dir.path}/settings.sqlite');
    var store = await LanFileStoreImpl.open(dbFile: file);
    StartupBehavior create() => StartupBehavior(
      read: () => store.getSetting(StartupBehavior.settingKey),
      write: (value) => store.setSetting(StartupBehavior.settingKey, value),
    );
    addTearDown(() async {
      await store.close();
      await dir.delete(recursive: true);
    });
    var behavior = create();
    await behavior.setEnabled(true);
    behavior.dispose();
    await store.close();
    store = await LanFileStoreImpl.open(dbFile: file);
    behavior = create();
    addTearDown(behavior.dispose);
    var shown = false;
    var initialized = false;
    await behavior.launch(
      arguments: [],
      initializeTray: () async => initialized = true,
      show: () async => shown = true,
    );
    expect(initialized, isTrue);
    expect(shown, isFalse);
    expect(behavior.value, isTrue);
    await behavior.setEnabled(false);
    expect(await store.getSetting(StartupBehavior.settingKey), 'false');
    await behavior.launch(
      arguments: [],
      initializeTray: () async => true,
      show: () async => shown = true,
    );
    expect(shown, isTrue);
  });

  for (final args in [
    ['--silent'],
    ['--show'],
    ['--silent', '--show'],
    ['--show', '--silent'],
  ]) {
    test('temporary startup override $args never changes storage', () async {
      var shown = false;
      final behavior = StartupBehavior(
        read: () async => 'true',
        write: (_) async => fail('Launch must not write settings'),
      );
      addTearDown(behavior.dispose);
      await behavior.launch(
        arguments: args,
        initializeTray: () async => true,
        show: () async => shown = true,
      );
      expect(shown, args.contains('--show'));
      expect(behavior.value, isTrue);
    });
  }

  test('--silent works on first launch and waits for tray readiness', () async {
    final tray = Completer<bool>();
    var shown = false;
    final behavior = StartupBehavior(
      read: () async => null,
      write: (_) async {},
    );
    addTearDown(behavior.dispose);
    final pending = behavior.launch(
      arguments: ['--silent'],
      initializeTray: () => tray.future,
      show: () async => shown = true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(shown, isFalse);
    tray.complete(true);
    await pending;
    expect(shown, isFalse);
    expect(behavior.value, isFalse);
  });

  test('failed tray registration reveals silent window', () async {
    var shown = false;
    final behavior = StartupBehavior(
      read: () async => 'true',
      write: (_) async {},
    );
    addTearDown(behavior.dispose);
    await behavior.launch(
      arguments: ['--silent'],
      initializeTray: () async => false,
      show: () async => shown = true,
    );
    expect(shown, isTrue);
  });

  for (final failRead in [true, false]) {
    test(
      'initialization error reveals window before reporting: $failRead',
      () async {
        var shown = false;
        final behavior = StartupBehavior(
          read: () async => failRead ? throw StateError('read') : 'true',
          write: (_) async {},
        );
        addTearDown(behavior.dispose);
        await expectLater(
          behavior.launch(
            arguments: ['--silent'],
            initializeTray: () async => throw StateError('tray'),
            show: () async => shown = true,
          ),
          throwsStateError,
        );
        expect(shown, isTrue);
      },
    );
  }

  testWidgets('setting saves before updating and locks pending writes', (
    tester,
  ) async {
    final saved = Completer<void>();
    final writes = <String>[];
    final behavior = StartupBehavior(
      read: () async => null,
      write: (value) {
        writes.add(value);
        return saved.future;
      },
    );
    addTearDown(behavior.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: SilentStartupSetting(behavior: behavior)),
      ),
    );
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(writes, ['true']);
    expect(behavior.value, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    saved.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets('save failure keeps preference and shows error', (tester) async {
    final behavior = StartupBehavior(
      read: () async => null,
      write: (_) async => throw StateError('disk full'),
    );
    addTearDown(behavior.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: SilentStartupSetting(behavior: behavior)),
      ),
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(behavior.value, isFalse);
    expect(find.textContaining('disk full'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
  });
}
