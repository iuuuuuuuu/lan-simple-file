// SPDX-License-Identifier: GPL-3.0-only
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:lan_simple_file/core/files/imported_files.dart';
import 'package:lan_simple_file/ui/shell/qq_shell.dart';

import 'qq_shell_test.dart' show wrapShell, setViewport;

void main() {
  testWidgets('手机底部悬浮导航，全宽联系人页面，支持切换设置和分享', (tester) async {
    await setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(wrapShell(const QqShell()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shell-rail')), findsNothing);
    expect(find.byKey(const ValueKey('mobile-navigation')), findsOneWidget);
    expect(tester.getRect(find.byKey(const ValueKey('shell-list'))).width, 390);
    expect(
      tester.getRect(find.byKey(const ValueKey('mobile-navigation'))).top,
      greaterThan(700),
    );
    await tester.tap(find.byKey(const ValueKey('mobile-nav-settings')));
    await tester.pumpAndSettle();
    expect(find.text('本机信息'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('上传文件使用流保存、清理失败临时文件，文件名不能逃逸应用目录', () async {
    final temp = await Directory.systemTemp.createTemp('lsf_import_test_');
    addTearDown(() => temp.delete(recursive: true));
    final file = await persistImportedFile(
      directory: temp,
      name: '../文件.txt',
      content: Stream.fromIterable([
        [1, 2],
        [3, 4],
      ]),
    );
    expect(await file.readAsBytes(), [1, 2, 3, 4]);
    expect(file.path.startsWith(temp.path), true);
    final before = await temp.list().length;
    await expectLater(
      persistImportedFile(
        directory: temp,
        name: 'bad.txt',
        content: Stream.error(StateError('failed')),
      ),
      throwsStateError,
    );
    expect(await temp.list().length, before);
  });
}
