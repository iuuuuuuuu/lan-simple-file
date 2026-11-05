// SPDX-License-Identifier: GPL-3.0-only

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/assembly.dart';
import 'package:lan_simple_file/ui/shell/qq_shell.dart';
import 'package:lan_simple_file/ui/shell/session_rail.dart';
import 'package:lan_simple_file/ui/widgets/app_toast.dart';
import 'package:lan_simple_file/ui/widgets/share_row.dart';
import 'package:path/path.dart' as p;

import 'qq_shell_test.dart' show setViewport, wrapShell;

Future<void> settleIo(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> dropPaths(WidgetTester tester, List<String> paths) async {
  final position = tester.getCenter(find.byKey(kShellContentKey));
  // Exercise the plugin's platform-message path, not just onDragDone.
  for (final call in [
    MethodCall('entered', [position.dx, position.dy]),
    MethodCall('updated', [position.dx, position.dy]),
    MethodCall('performOperation', paths),
  ]) {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'desktop_drop',
      const StandardMethodCodec().encodeMethodCall(call),
      (_) {},
    );
    await tester.pump();
  }
  await settleIo(tester);
}

void main() {
  testWidgets('桌面拖入文件和目录立即显示，坏路径不阻断且原文件不变', (tester) async {
    await setViewport(tester, const Size(1280, 800));
    final sandbox = Directory.systemTemp.createTempSync('lsf_drop_ui_');
    final services = (await tester.runAsync(
      () => AppAssembler.assemble(
        dataDir: Directory(p.join(sandbox.path, 'data')),
        httpPortOverride: 0,
        udpPortOverride: 0,
        enableDiscovery: false,
      ),
    ))!;
    addTearDown(() async {
      AppToast.dismiss();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(services.stop);
      final target = sandbox.absolute.path;
      expect(p.isWithin(Directory.systemTemp.absolute.path, target), isTrue);
      sandbox.deleteSync(recursive: true);
    });
    final file = File(p.join(sandbox.path, 'report.txt'))
      ..writeAsStringSync('keep-original');
    final folder = Directory(p.join(sandbox.path, '中文目录'))..createSync();
    final nested = File(p.join(folder.path, 'inside.txt'))
      ..writeAsStringSync('keep-nested');
    await tester.pumpWidget(
      wrapShell(
        QqShell(
          services: services,
          initialSection: ShellSection.shares,
        ),
      ),
    );
    await settleIo(tester);
    expect(find.text('还没有分享'), findsOneWidget);

    await dropPaths(tester, [
      file.path,
      p.join(sandbox.path, 'missing.txt'),
      folder.path,
    ]);
    final shares = (await tester.runAsync(services.shares.listMine))!;
    expect(shares, hasLength(2));
    expect(shares.map((s) => s.rootUri), containsAll([file.path, folder.path]));
    expect(find.byType(ShareRow), findsNWidgets(2));
    expect(find.text('共 2 项'), findsOneWidget);
    expect(find.text('report.txt'), findsOneWidget);
    expect(find.text('中文目录'), findsOneWidget);
    expect(file.readAsStringSync(), 'keep-original');
    expect(nested.readAsStringSync(), 'keep-nested');

    await tester.enterText(
      find.byKey(const ValueKey('my-shares-search')),
      'report',
    );
    await tester.pump();
    final second = File(p.join(sandbox.path, 'report-two.txt'))
      ..writeAsStringSync('second-original');
    await dropPaths(tester, [second.path]);
    expect(find.text('共 3 项'), findsOneWidget);
    expect(find.byType(ShareRow), findsNWidgets(2));
    expect(find.text('report-two.txt'), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const ValueKey('my-shares-search')),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      'report',
    );
    expect(tester.takeException(), isNull);
  });
}
