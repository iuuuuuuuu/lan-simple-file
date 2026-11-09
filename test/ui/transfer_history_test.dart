// SPDX-License-Identifier: GPL-3.0-only
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/transfer/transfer_history.dart';
import 'package:lan_simple_file/ui/pages/transfer_history_page.dart';

import 'qq_shell_test.dart' show wrapShell, setViewport;
import 'support/miuix_test_support.dart';

class TestHistory implements TransferHistorySource {
  final updates = StreamController<void>.broadcast();
  final entries = [
    TransferHistoryEntry(
      id: 'external',
      name: '项目计划.pdf',
      direction: TransferDirection.download,
      status: 'external',
      peerLabel: '好好吃饭',
      createdAt: DateTime.utc(2026),
    ),
    TransferHistoryEntry(
      id: 'sent',
      name: '旅行照片.zip',
      direction: TransferDirection.upload,
      status: 'sent',
      bytes: 2048,
      createdAt: DateTime.utc(2026),
    ),
  ];
  final removed = <String>{};
  @override
  Stream<void> get changes => updates.stream;
  @override
  Future<List<TransferHistoryEntry>> list() async => [...entries];
  @override
  Future<void> remove(Set<String> ids) async {
    removed.addAll(ids);
    entries.removeWhere((e) => ids.contains(e.id));
    updates.add(null);
  }
}

void main() {
  for (final width in [320.0, 1280.0]) {
    testWidgets('search, direction filter and bulk delete history at $width', (
      tester,
    ) async {
      await setViewport(tester, Size(width, 800));
      final source = TestHistory();
      addTearDown(source.updates.close);
      await tester.pumpWidget(
        wrapShell(AppScaffold(body: TransferHistoryPage(source: source))),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('已交给外部应用'), findsOneWidget);
      expect(find.textContaining('已完成'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('transfer-history-search')),
        '好好',
      );
      await tester.pumpAndSettle();
      expect(find.text('项目计划.pdf'), findsOneWidget);
      expect(find.text('旅行照片.zip'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('transfer-history-search')),
        '',
      );
      await tester.tap(find.text('发送').last);
      await tester.pumpAndSettle();
      expect(find.text('项目计划.pdf'), findsNothing);
      await tester.tap(findAppTooltip('管理记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(MiuixCheckbox).first);
      await tester.pumpAndSettle();
      await tester.tap(findAppTooltip('删除所选记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, '取消'));
      await tester.pumpAndSettle();
      expect(source.removed, isEmpty);
      await tester.tap(findAppTooltip('删除所选记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, '删除记录'));
      await tester.pumpAndSettle();
      expect(source.removed, {'sent'});
      expect(source.entries.single.id, 'external');
      expect(find.text('暂无传输记录'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
