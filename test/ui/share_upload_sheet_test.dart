// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/miuix_test_support.dart';

import 'package:lan_simple_file/ui/widgets/share_upload_sheet.dart';

import 'qq_shell_test.dart' show setViewport, wrapShell;

void main() {
  testWidgets('文件夹提交后忽略关闭期间的重复点击，移除遮罩后才返回', (tester) async {
    await setViewport(tester, const Size(360, 616));
    final selected = <ShareUploadKind?>[];
    await tester.pumpWidget(
      wrapShell(
        AppScaffold(
          body: Builder(
            builder: (context) => IconButton(
              key: const ValueKey('open-picker'),
              icon: const Icon(Icons.add),
              onPressed: () async {
                selected.add(await showShareUploadSheet(context));
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final barriers = find.byType(ModalBarrier).evaluate().length;
    await tester.tap(find.byKey(const ValueKey('open-picker')));
    await tester.pumpAndSettle();
    final folder = tester
        .widget<AppListTile>(find.byKey(const ValueKey('share-upload-folder')))
        .onTap!;
    final file = tester
        .widget<AppListTile>(find.byKey(const ValueKey('share-upload-file')))
        .onTap!;
    folder();
    file();
    folder();
    expect(selected, isEmpty);
    await tester.pumpAndSettle();
    expect(selected, [ShareUploadKind.folder]);
    expect(find.byType(ModalBarrier), findsNWidgets(barriers));
    expect(find.byKey(const ValueKey('open-picker')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
