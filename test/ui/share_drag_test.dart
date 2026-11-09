// SPDX-License-Identifier: GPL-3.0-only
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/shares/share_organization.dart';
import 'package:lan_simple_file/ui/pages/shares_page.dart';
import 'package:lan_simple_file/ui/widgets/app_toast.dart';
import 'package:lan_simple_file/ui/widgets/share_drag_grid.dart';
import 'package:lan_simple_file/ui/widgets/share_row.dart';

import 'share_organization_test.dart' show TestOrganizationSource;
import 'support/miuix_test_support.dart';
import 'support/ui_fakes.dart';

List<String> visibleOrder(WidgetTester tester) => tester
    .widgetList<ShareRow>(find.byType(ShareRow))
    .map((row) => row.share.id.value)
    .toList();

Future<void> dragShare(
  WidgetTester tester,
  String id,
  Offset target, {
  Offset? start,
}) async {
  final from = tester.getRect(find.byKey(ValueKey('share-drag-$id')));
  final gesture = await tester.startGesture(start ?? from.center);
  await tester.pump(const Duration(milliseconds: 400));
  await gesture.moveTo(target);
  await tester.pump(const Duration(milliseconds: 100));
  await gesture.up();
  await tester.pumpAndSettle();
}

class SlowOrganization extends TestOrganizationSource {
  final pending = Completer<void>();
  @override
  Future<void> save(ShareOrganization organization) async {
    await pending.future;
    await super.save(organization);
  }
}

void main() {
  tearDown(AppToast.dismiss);
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'long press sorts both directions and moves to empty group $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final source = FakeMySharesSource()
          ..shares = [
            shareRecord(id: 'alpha', displayName: 'Alpha'),
            shareRecord(id: 'bravo', displayName: 'Bravo'),
            shareRecord(id: 'charlie', displayName: 'Charlie'),
          ];
        final layout = TestOrganizationSource()
          ..value = const ShareOrganization(names: {'work': 'Work'});
        Widget page() => wrapWithTheme(
          SharesPage(
            source: source,
            organizationSource: layout,
            homeLink: () async =>
                Uri.parse('http://test.p-alphaalphaalphaalphaa.local:47778/'),
          ),
        );
        await tester.pumpWidget(page());
        await tester.pumpAndSettle();
        final first = tester.getRect(
          find.byKey(const ValueKey('share-drag-alpha')),
        );
        await dragShare(
          tester,
          'charlie',
          first.topLeft + const Offset(15, 15),
          start: tester.getCenter(find.text('Charlie')),
        );
        expect(visibleOrder(tester), ['charlie', 'alpha', 'bravo']);
        expect(layout.value.order, ['charlie', 'alpha', 'bravo']);
        final last = tester.getRect(
          find.byKey(const ValueKey('share-drag-bravo')),
        );
        await dragShare(
          tester,
          'charlie',
          last.bottomRight - const Offset(15, 15),
        );
        expect(visibleOrder(tester), ['alpha', 'bravo', 'charlie']);
        await dragShare(
          tester,
          'alpha',
          tester.getCenter(
            find.byKey(const ValueKey('share-group-target-work')),
          ),
        );
        expect(layout.value.groupOf('alpha'), 'work');
        await tester.tap(find.byKey(const ValueKey('share-group-target-work')));
        await tester.pumpAndSettle();
        expect(visibleOrder(tester), ['alpha']);
        await dragShare(
          tester,
          'alpha',
          tester.getCenter(find.byKey(const ValueKey('share-group-target-'))),
        );
        expect(layout.value.groupOf('alpha'), '');
        expect(find.text('这个分组还没有分享'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(page());
        await tester.pumpAndSettle();
        expect(visibleOrder(tester), ['alpha', 'bravo', 'charlie']);
        expect(source.deleted, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'search reordering retains hidden shares and failed save rolls back',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final source = FakeMySharesSource()
        ..shares = [
          shareRecord(id: 'alpha', displayName: 'Keep A'),
          shareRecord(id: 'bravo', displayName: 'Hidden'),
          shareRecord(id: 'charlie', displayName: 'Keep C'),
        ];
      final layout = TestOrganizationSource()
        ..value = const ShareOrganization(order: ['alpha', 'bravo', 'charlie']);
      await tester.pumpWidget(
        wrapWithTheme(SharesPage(source: source, organizationSource: layout)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('my-shares-search')),
        'Keep',
      );
      await tester.pumpAndSettle();
      final first = tester.getRect(
        find.byKey(const ValueKey('share-drag-alpha')),
      );
      await dragShare(tester, 'charlie', first.topLeft + const Offset(20, 20));
      expect(layout.value.order, ['charlie', 'alpha', 'bravo']);
      await tester.enterText(
        find.byKey(const ValueKey('my-shares-search')),
        '',
      );
      await tester.pumpAndSettle();
      expect(visibleOrder(tester), ['charlie', 'alpha', 'bravo']);
      layout.failSave = true;
      await dragShare(tester, 'bravo', first.topLeft + const Offset(20, 20));
      expect(visibleOrder(tester), ['charlie', 'alpha', 'bravo']);
      expect(layout.value.order, ['charlie', 'alpha', 'bravo']);
      expect(find.textContaining('保存分组与排序失败'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancel outside targets does not save and drag scrolls long lists',
    (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final layout = TestOrganizationSource();
      final source = FakeMySharesSource()
        ..shares = List.generate(
          30,
          (i) => shareRecord(
            id: 'item$i',
            displayName: 'Item ${i.toString().padLeft(2, '0')}',
          ),
        );
      await tester.pumpWidget(
        wrapWithTheme(SharesPage(source: source, organizationSource: layout)),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('share-drag-item0'))),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.moveTo(const Offset(190, 690));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final position = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byKey(const ValueKey('my-shares-grid')),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      expect(position.pixels, greaterThan(500));
      await gesture.moveTo(const Offset(390, 10));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(layout.value.order, isEmpty);
      final stopped = position.pixels;
      await tester.pump(const Duration(seconds: 1));
      expect(position.pixels, stopped);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('slow save disables further drags until persistence completes', (
    tester,
  ) async {
    final layout = SlowOrganization();
    final source = FakeMySharesSource()
      ..shares = [
        shareRecord(id: 'alpha', displayName: 'Alpha'),
        shareRecord(id: 'bravo', displayName: 'Bravo'),
      ];
    await tester.pumpWidget(
      wrapWithTheme(SharesPage(source: source, organizationSource: layout)),
    );
    await tester.pumpAndSettle();
    await dragShare(
      tester,
      'bravo',
      tester.getTopLeft(find.byKey(const ValueKey('share-drag-alpha'))) +
          const Offset(20, 20),
    );
    expect(visibleOrder(tester), ['bravo', 'alpha']);
    expect(
      tester.widget<ShareDragGrid>(find.byType(ShareDragGrid)).enabled,
      false,
    );
    layout.pending.complete();
    await tester.pumpAndSettle();
    expect(layout.value.order, ['bravo', 'alpha']);
    expect(
      tester.widget<ShareDragGrid>(find.byType(ShareDragGrid)).enabled,
      true,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging at the group strip edge reveals offscreen groups', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final layout = TestOrganizationSource()
      ..value = ShareOrganization(
        names: {for (var i = 0; i < 8; i++) 'group$i': 'Group $i'},
      );
    await tester.pumpWidget(
      wrapWithTheme(
        SharesPage(
          source: FakeMySharesSource()
            ..shares = [shareRecord(id: 'alpha', displayName: 'Alpha')],
          organizationSource: layout,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final strip = find.ancestor(
      of: find.byKey(const ValueKey('share-group-target-*')),
      matching: find.byType(SingleChildScrollView),
    );
    final bounds = tester.getRect(strip);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Alpha')),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.moveTo(Offset(bounds.right - 2, bounds.center.dy));
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: strip, matching: find.byType(Scrollable)),
        )
        .position;
    expect(position.pixels, greaterThan(250));
    await gesture.moveTo(const Offset(389, 5));
    await gesture.up();
    await tester.pumpAndSettle();
    final stopped = position.pixels;
    await tester.pump(const Duration(seconds: 1));
    expect(position.pixels, stopped);
    expect(layout.value.assignments, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('create a group directly from page and reject duplicate names', (
    tester,
  ) async {
    final layout = TestOrganizationSource();
    await tester.pumpWidget(
      wrapWithTheme(
        SharesPage(source: FakeMySharesSource(), organizationSource: layout),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.tap(findAppTooltip('新建分享分组'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('share-group-name')),
        'Work',
      );
      await tester.tap(find.widgetWithText(AppButton, '保存'));
      await tester.pumpAndSettle();
      expect(layout.value.names.values, ['Work']);
    }
    expect(find.text('已存在同名分组'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
