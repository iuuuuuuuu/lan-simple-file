// SPDX-License-Identifier: GPL-3.0-only

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/shares/share_organization.dart';
import 'package:lan_simple_file/ui/pages/shares_page.dart';
import 'package:lan_simple_file/ui/widgets/app_toast.dart';
import 'package:lan_simple_file/ui/widgets/qr_panel.dart';
import 'package:lan_simple_file/ui/widgets/share_organization_dialog.dart';
import 'package:lan_simple_file/ui/widgets/share_row.dart';

import 'support/miuix_test_support.dart';
import 'support/ui_fakes.dart';

class TestOrganizationSource implements ShareOrganizationSource {
  ShareOrganization value = const ShareOrganization();
  bool failSave = false;
  @override
  Future<ShareOrganization> load() async => value;
  @override
  Future<void> save(ShareOrganization organization) async {
    if (failSave) throw StateError('test save failure');
    value = organization;
  }
}

Future<void> choose(WidgetTester tester, String tooltip, String label) async {
  await tester.tap(findAppTooltip(tooltip));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  tearDown(AppToast.dismiss);
  for (final width in [390.0, 1280.0]) {
    testWidgets('create group, batch move, save and share group at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final source = FakeMySharesSource()
        ..shares = [
          shareRecord(id: 'folder', displayName: 'Photos'),
          shareRecord(id: 'file', displayName: 'notes.txt', kind: 'file'),
        ];
      final organization = TestOrganizationSource();
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        wrapWithTheme(
          SharesPage(
            source: source,
            organizationSource: organization,
            homeLink: () async =>
                Uri.parse('http://alice--p-aaaaaaaaaaaaa.local:47778/'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(findAppTooltip('分组与排序'));
      await tester.pumpAndSettle();
      await tester.tap(findAppTooltip('新建分享分组').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('share-group-name')),
        'Work',
      );
      await tester.tap(find.widgetWithText(AppButton, '保存').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('select-share-file')));
      await tester.tap(find.byKey(const ValueKey('select-share-folder')));
      await tester.pumpAndSettle();
      await choose(tester, '移动所选分享', 'Work');
      await tester.tap(find.widgetWithText(AppButton, '保存'));
      await tester.pumpAndSettle();
      final group = organization.value.names.keys.single;
      expect(organization.value.groupOf('file'), group);
      expect(organization.value.groupOf('folder'), group);
      await choose(tester, '筛选分享分组', 'Work');
      await tester.tap(findAppTooltip('复制分组链接'));
      await tester.pumpAndSettle();
      expect(Uri.parse(copied.single).queryParameters, {'group': group});
      expect(Uri.parse(copied.single).host, 'alice--p-aaaaaaaaaaaaa.local');
      await tester.tap(findAppTooltip('分组二维码'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<QrPanel>(find.byType(QrPanel)).linkText,
        copied.single,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'dragging changes share and group order, deleting a group keeps its shares',
    (tester) async {
      final source = FakeMySharesSource()
        ..shares = [
          shareRecord(id: 'folder', displayName: 'Folder'),
          shareRecord(id: 'file', displayName: 'File', kind: 'file'),
        ];
      final organization = TestOrganizationSource()
        ..value = const ShareOrganization(
          names: {'work': 'Work'},
          assignments: {'folder': 'work', 'file': 'work'},
        );
      await tester.pumpWidget(
        wrapWithTheme(
          SharesPage(source: source, organizationSource: organization),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(findAppTooltip('分组与排序'));
      await tester.pumpAndSettle();
      final from = tester.getCenter(
        find.byKey(const ValueKey('share-order-handle-file')),
      );
      final to = tester.getCenter(
        find.byKey(const ValueKey('share-order-handle-folder')),
      );
      final shareDrag = await tester.startGesture(from);
      await shareDrag.moveBy(const Offset(0, -24));
      await tester.pump(const Duration(milliseconds: 300));
      await shareDrag.moveTo(to);
      await tester.pump(const Duration(milliseconds: 500));
      await shareDrag.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('分组').last);
      await tester.pumpAndSettle();
      final groupFrom = tester.getCenter(
        find.byKey(const ValueKey('share-order-handle-group-work')),
      );
      final groupTo = tester.getCenter(
        find.byKey(const ValueKey('share-order-handle-group-')),
      );
      final groupDrag = await tester.startGesture(groupFrom);
      await groupDrag.moveBy(const Offset(0, -24));
      await tester.pump(const Duration(milliseconds: 300));
      await groupDrag.moveTo(groupTo);
      await tester.pump(const Duration(milliseconds: 500));
      await groupDrag.up();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, '保存'));
      await tester.pumpAndSettle();
      expect(organization.value.order.take(2), ['file', 'folder']);
      expect(organization.value.groups, ['work', '']);
      expect(
        tester
            .widgetList<ShareRow>(find.byType(ShareRow))
            .map((r) => r.share.id.value),
        ['file', 'folder'],
      );
      await tester.tap(findAppTooltip('分组与排序'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('分组').last);
      await tester.pumpAndSettle();
      await choose(tester, '管理分组 Work', '删除分组');
      await tester.tap(find.widgetWithText(AppButton, '删除分组'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, '保存'));
      await tester.pumpAndSettle();
      expect(organization.value.names, isEmpty);
      expect(find.byType(ShareRow), findsNWidgets(2));
      expect(source.deleted, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed save retains edits and cancel never writes them', (
    tester,
  ) async {
    final organization = TestOrganizationSource()..failSave = true;
    await tester.pumpWidget(
      wrapWithTheme(
        SharesPage(
          source: FakeMySharesSource(),
          organizationSource: organization,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(findAppTooltip('分组与排序'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(find.byType(ShareOrganizationDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(AppButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.byType(ShareOrganizationDialog), findsNothing);
    expect(organization.value.names, isEmpty);
  });
}
