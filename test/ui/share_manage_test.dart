// SPDX-License-Identifier: GPL-3.0-only

/// 分享管理新增能力：删除 / 重新启用 / 展开浏览。
///
/// 对应用户实测报的三个缺陷：
/// A.「已经创建的要支持删除」
/// B.「停止共享后 无法启动」
/// C.「共享文件夹，无法查看文件内有什么文件」
///
/// 数据源是可记账的假实现（只假数据来源），页面、对话框、面板全是真的。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/ui/pages/shares_page.dart';
import 'package:lan_simple_file/ui/widgets/app_toast.dart';
import 'package:lan_simple_file/ui/widgets/share_detail_panel.dart';

import 'support/ui_fakes.dart';

/// 造一个条目。
TreeEntryView entryOf({
  required String key,
  required String name,
  bool dir = false,
  int? size,
}) => TreeEntryView(
  itemKey: ItemKey.parse(key),
  name: name,
  isDirectory: dir,
  size: dir ? null : size,
);

/// 每拍推进：Toast 走 OverlayEntry，需要插入 + 淡入两拍。
Future<void> settleToast(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

/// 打开某条分享的「更多操作」菜单并点选一项。
///
/// 为什么需要它：动作已从卡片上的一排按钮收进下拉菜单（用户实测要求），
/// 所以任何「点某按钮」的断言都必须先开菜单。
/// 抽成一个 helper 而不是每处重复四行 pump，避免各用例写法分叉。
Future<void> tapMenuAction(WidgetTester tester, String label) async {
  final Finder menu = find.byKey(const ValueKey<String>('share-actions-menu'));
  expect(menu, findsWidgets, reason: '动作菜单必须存在');
  await tester.tap(menu.first);
  await tester.pumpAndSettle();
  final Finder item = find.text(label);
  expect(item, findsWidgets, reason: '菜单里应当有「$label」');
  await tester.tap(item.last);
  await tester.pumpAndSettle();
}

void main() {
  tearDown(AppToast.dismiss);

  group('A. 删除', () {
    testWidgets('二次确认：取消则不删', (WidgetTester tester) async {
      final FakeMySharesSource source = FakeMySharesSource()
        ..shares = <ShareRecord>[shareRecord(id: 'sh01', displayName: '要删的')];
      await tester.pumpWidget(wrapWithTheme(SharesPage(source: source)));
      await tester.pumpAndSettle();

      await tapMenuAction(tester, '删除');

      // 确认框必须出现，且说明不会动原文件。
      expect(find.text('删除这条分享？'), findsOneWidget);
      expect(find.textContaining('原始文件不会被删除'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(source.deleted, isEmpty, reason: '取消后绝不能删');
      expect(find.text(r'D:\媒体\要删的'), findsOneWidget);
    });

    testWidgets('确认后真的调 delete，并从列表消失', (WidgetTester tester) async {
      final FakeMySharesSource source = FakeMySharesSource()
        ..shares = <ShareRecord>[shareRecord(id: 'sh01', displayName: '要删的')];
      await tester.pumpWidget(wrapWithTheme(SharesPage(source: source)));
      await tester.pumpAndSettle();

      await tapMenuAction(tester, '删除');
      // 对话框里的「删除」按钮（与行内的同名，取最后出现的那个）。
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      // 先让对话框退出动画走完，再检查 Toast；否则 overlay 会被动画帧覆盖。
      await tester.pumpAndSettle();
      await settleToast(tester);
      await tester.pump();

      expect(source.deleted, <String>['sh01']);
      expect(find.textContaining('已删除'), findsOneWidget);
      // 列表重新加载后为空。
      await tester.pumpAndSettle();
      expect(find.text(r'D:\媒体\要删的'), findsNothing);
      expect(find.textContaining('共 0 项'), findsOneWidget);
    });

    testWidgets('删除失败时给出可读错误，不静默', (WidgetTester tester) async {
      final FakeMySharesSource source = FakeMySharesSource()
        ..shares = <ShareRecord>[shareRecord(id: 'sh01')]
        ..deleteError = const LanFileException(LanFileErrorCode.io, '库被占用');
      await tester.pumpWidget(wrapWithTheme(SharesPage(source: source)));
      await tester.pumpAndSettle();

      await tapMenuAction(tester, '删除');
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      await settleToast(tester);

      expect(find.textContaining('删除失败'), findsOneWidget);
      expect(find.textContaining('库被占用'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('B. 重新启用', () {
    testWidgets('已停止的行出现「重新启用」，点击后变回有效', (WidgetTester tester) async {
      final FakeMySharesSource source = FakeMySharesSource()
        ..shares = <ShareRecord>[
          shareRecord(id: 'sh01', displayName: '停过的', enabled: false),
        ];
      await tester.pumpWidget(wrapWithTheme(SharesPage(source: source)));
      await tester.pumpAndSettle();

      expect(find.text('已停止'), findsOneWidget);
      // 菜单化后「重新启用」只在菜单里：先确认菜单能打开且含该项。
      await tester.tap(
        find.byKey(const ValueKey<String>('share-actions-menu')).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('重新启用'), findsWidgets, reason: '已停止的行，菜单里必须有重新启用');
      // 关掉菜单，再走正常流程。
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();

      await tapMenuAction(tester, '重新启用');
      await settleToast(tester);

      expect(source.resumed, <String>['sh01']);
      expect(find.textContaining('已重新启用'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('有效'), findsOneWidget);
      expect(find.text('重新启用'), findsNothing);
    });

    testWidgets('有效行不显示「重新启用」（不制造无效入口）', (WidgetTester tester) async {
      final FakeMySharesSource source = FakeMySharesSource()
        ..shares = <ShareRecord>[shareRecord(id: 'sh01')];
      await tester.pumpWidget(wrapWithTheme(SharesPage(source: source)));
      await tester.pumpAndSettle();

      // 有效行：菜单里有「停止共享」、没有「重新启用」（不制造无效入口）。
      await tester.tap(
        find.byKey(const ValueKey<String>('share-actions-menu')).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('重新启用'), findsNothing, reason: '有效行不该出现重新启用');
      expect(find.text('停止共享'), findsWidgets);
    });

    testWidgets('重新启用失败时给出错误', (WidgetTester tester) async {
      final FakeMySharesSource source = FakeMySharesSource()
        ..shares = <ShareRecord>[shareRecord(id: 'sh01', enabled: false)]
        ..resumeError = const LanFileException(
          LanFileErrorCode.revoked,
          '分享已撤销',
        );
      await tester.pumpWidget(wrapWithTheme(SharesPage(source: source)));
      await tester.pumpAndSettle();

      await tapMenuAction(tester, '重新启用');
      await settleToast(tester);

      expect(find.textContaining('重新启用失败'), findsOneWidget);
      expect(find.textContaining('分享已撤销'), findsOneWidget);
    });
  });

  group('C. 展开查看文件', () {
    testWidgets('点展开 -> 看见 3 行；点目录 -> 带子路径再 browse', (
      WidgetTester tester,
    ) async {
      final FakeMySharesSource source = FakeMySharesSource()
        ..shares = <ShareRecord>[shareRecord(id: 'sh01', displayName: '资料')]
        ..entriesByPath = <String, List<TreeEntryView>>{
          '': <TreeEntryView>[
            entryOf(key: 'sub', name: '子目录', dir: true),
            entryOf(key: 'a.txt', name: 'a.txt', size: 1234),
            entryOf(key: 'b.txt', name: 'b.txt', size: 2048),
          ],
          'sub': <TreeEntryView>[
            entryOf(key: 'sub/inner.txt', name: 'inner.txt', size: 99),
          ],
        };
      await tester.pumpWidget(wrapWithTheme(SharesPage(source: source)));
      await tester.pumpAndSettle();

      // 展开前看不到内容。
      expect(find.text('a.txt'), findsNothing);

      await tapMenuAction(tester, '展开查看文件');

      expect(find.text('子目录'), findsOneWidget);
      expect(find.text('a.txt'), findsOneWidget);
      expect(find.text('b.txt'), findsOneWidget);
      // 文件显示大小。
      expect(find.text('1.2 KB'), findsOneWidget);

      // 下钻子目录：必须带子路径去 browse。
      await tester.tap(find.text('子目录'));
      await tester.pumpAndSettle();

      expect(source.browsedPaths, contains('sub'));
      expect(find.text('inner.txt'), findsOneWidget);
      expect(find.text('a.txt'), findsNothing);
    });

    testWidgets('空目录显示可读提示，不是空白', (WidgetTester tester) async {
      final FakeMySharesSource source = FakeMySharesSource()
        ..shares = <ShareRecord>[shareRecord(id: 'sh01')]
        ..entriesByPath = <String, List<TreeEntryView>>{'': <TreeEntryView>[]};
      await tester.pumpWidget(wrapWithTheme(SharesPage(source: source)));
      await tester.pumpAndSettle();

      await tapMenuAction(tester, '展开查看文件');

      expect(find.text('这个文件夹是空的'), findsOneWidget);
    });

    testWidgets('源已失效时显示「已失效，无法浏览」', (WidgetTester tester) async {
      final FakeMySharesSource source = FakeMySharesSource()
        ..shares = <ShareRecord>[shareRecord(id: 'sh01', missing: true)];
      await tester.pumpWidget(wrapWithTheme(SharesPage(source: source)));
      await tester.pumpAndSettle();

      await tapMenuAction(tester, '展开查看文件');

      expect(find.text('已失效，无法浏览'), findsOneWidget);
    });

    testWidgets('文件项有下载入口，点击把条目交给回调', (WidgetTester tester) async {
      final List<TreeEntryView> downloaded = <TreeEntryView>[];
      final FakeMySharesSource source = FakeMySharesSource()
        ..shares = <ShareRecord>[shareRecord(id: 'sh01')]
        ..entriesByPath = <String, List<TreeEntryView>>{
          '': <TreeEntryView>[entryOf(key: 'a.txt', name: 'a.txt', size: 10)],
        };
      await tester.pumpWidget(
        wrapWithTheme(
          SharesPage(
            source: source,
            onDownload: (TreeEntryView e) => downloaded.add(e),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tapMenuAction(tester, '展开查看文件');

      await tester.tap(find.byTooltip('下载'));
      await tester.pumpAndSettle();

      expect(downloaded, hasLength(1));
      expect(downloaded.single.name, 'a.txt');
    });

    testWidgets('查看文件是弹窗：关闭后内容隐藏，卡片恢复精简', (WidgetTester tester) async {
      final FakeMySharesSource source = FakeMySharesSource()
        ..shares = <ShareRecord>[shareRecord(id: 'sh01')]
        ..entriesByPath = <String, List<TreeEntryView>>{
          '': <TreeEntryView>[entryOf(key: 'a.txt', name: 'a.txt', size: 1)],
        };
      await tester.pumpWidget(wrapWithTheme(SharesPage(source: source)));
      await tester.pumpAndSettle();

      await tapMenuAction(tester, '展开查看文件');
      // 现在内容在 Dialog 里，而不是卡片内嵌。
      expect(find.byType(Dialog), findsOneWidget, reason: '用户明确要求「查看文件弹窗查看」');
      expect(find.text('a.txt'), findsOneWidget);

      // 点关闭按钮收起弹窗，内容随之消失。
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('a.txt'), findsNothing);
    });
  });

  group('ShareDetailPanel 纯逻辑', () {
    test('humanSize 分档', () {
      expect(humanSize(null), '未知大小');
      expect(humanSize(512), '512 B');
      expect(humanSize(2048), '2.0 KB');
      expect(humanSize(5 * 1024 * 1024), '5.0 MB');
      expect(humanSize(3 * 1024 * 1024 * 1024), '3.00 GB');
    });
  });
}
