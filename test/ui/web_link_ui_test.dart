// SPDX-License-Identifier: GPL-3.0-only

/// 网页链接 UI（菜单形态）：动作收进一个下拉，复制只保留网页链接。
///
/// 用户实测两轮反馈共同决定现在的形态：
/// 1. 「我说的链接是局域网内可以用的 网页链接，可以直接下载的」
///    -> 必须有产出 http 网页链接的能力，且是主用途；
/// 2. 「这些按钮都合到这一个组件里面去，不要在这个外面显示，
///     可以有一个 menu 下拉复制各种链接，复制 app 链接不需要」
///    -> 动作收进菜单；App 深链入口取消。
///
/// 所以本文件断言的是「菜单里有什么、点了产出什么」，
/// 而不再是「卡片上并排几个按钮」。
///
/// 数据源是可记账的假实现（只假数据来源），页面与剪贴板调用全是真的。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/ui/pages/shares_page.dart';
import 'package:lan_simple_file/ui/widgets/app_toast.dart';
import 'package:lan_simple_file/ui/widgets/qr_panel.dart';

import 'support/ui_fakes.dart';

/// 装一个剪贴板探针，返回收到的调用列表。
List<MethodCall> _installClipboardProbe(WidgetTester tester) {
  final List<MethodCall> calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall call) async {
      if (call.method == 'Clipboard.setData') calls.add(call);
      return null;
    },
  );
  addTearDown(() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });
  return calls;
}

/// 从剪贴板调用里取出写入的文本。
String _clipboardText(MethodCall call) {
  final Map<Object?, Object?> map = call.arguments! as Map<Object?, Object?>;
  return map['text']! as String;
}

/// 推进 Toast 两拍。
Future<void> _settleToast(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

/// 打开某条分享的动作菜单。
Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(
    find.byKey(const ValueKey<String>('share-actions-menu')).first,
  );
  await tester.pumpAndSettle();
}

/// 打开菜单并点某一项。
Future<void> _tapMenu(WidgetTester tester, String label) async {
  await _openMenu(tester);
  final Finder item = find.text(label);
  expect(item, findsWidgets, reason: '菜单里应当有「$label」');
  await tester.tap(item.last);
  await tester.pumpAndSettle();
}

void main() {
  tearDown(AppToast.dismiss);

  group('菜单形态：复制只走网页链接', () {
    testWidgets('菜单里点「复制网页链接」-> 剪贴板是 http:// 且含 /s/ 与端口', (
      WidgetTester tester,
    ) async {
      final List<MethodCall> calls = _installClipboardProbe(tester);
      final FakeMySharesSource source = FakeMySharesSource()
        ..shares = <ShareRecord>[shareRecord(id: 'sh01')]
        ..webLink = Uri.parse('http://10.168.1.115:47778/s/sh01?k=abc');

      await tester.pumpWidget(wrapWithTheme(SharesPage(source: source)));
      await tester.pumpAndSettle();

      // 卡片上不该再有平铺的复制按钮（用户要求收进菜单）。
      expect(find.text('复制网页链接'), findsNothing, reason: '未开菜单时按钮不该占卡片位置');

      await _tapMenu(tester, '复制网页链接');
      await _settleToast(tester);

      expect(calls, hasLength(1));
      final String text = _clipboardText(calls.single);
      expect(text.startsWith('http://'), isTrue, reason: '必须是浏览器能打开的网页链接');
      expect(text.contains('/s/'), isTrue, reason: '必须是网页取件路径');
      expect(text.contains(':47778'), isTrue, reason: '必须带端口');
      expect(text.contains('10.168.1.115'), isTrue);
      expect(find.textContaining('已复制网页链接'), findsOneWidget);
    });

    testWidgets('菜单里**不再**有 App 深链入口（用户明确不要）', (WidgetTester tester) async {
      final FakeMySharesSource source = FakeMySharesSource()
        ..shares = <ShareRecord>[shareRecord(id: 'sh01')]
        ..webLink = Uri.parse('http://10.168.1.115:47778/s/sh01?k=abc');

      await tester.pumpWidget(wrapWithTheme(SharesPage(source: source)));
      await tester.pumpAndSettle();

      await _openMenu(tester);
      expect(
        find.textContaining('App 链接'),
        findsNothing,
        reason: '用户说「复制 app 链接不需要」',
      );
      expect(find.textContaining('lsf://'), findsNothing);
      // 菜单里复制项只应有一个。
      expect(find.text('复制网页链接'), findsWidgets);
    });
  });

  group('webLink 为 null：入口禁用 + 可读原因', () {
    testWidgets('菜单项禁用，点击不写入剪贴板', (WidgetTester tester) async {
      final List<MethodCall> calls = _installClipboardProbe(tester);
      final FakeMySharesSource source = FakeMySharesSource()
        ..shares = <ShareRecord>[shareRecord(id: 'sh01')]
        ..webLink = null;

      await tester.pumpWidget(wrapWithTheme(SharesPage(source: source)));
      await tester.pumpAndSettle();

      await _openMenu(tester);
      // 不可用时文案要标明，且该项 enabled=false（点了不会触发回调）。
      expect(
        find.textContaining('不可用'),
        findsWidgets,
        reason: '不可用时必须说明，而不是藏起来',
      );
      await tester.tap(find.textContaining('复制网页链接').last);
      await tester.pumpAndSettle();
      expect(calls, isEmpty, reason: '不可用时不得写入剪贴板');
    });

    testWidgets('卡片上常驻可读原因，不静默', (WidgetTester tester) async {
      final FakeMySharesSource source = FakeMySharesSource()
        ..shares = <ShareRecord>[shareRecord(id: 'sh01')]
        ..webLink = null;

      await tester.pumpWidget(wrapWithTheme(SharesPage(source: source)));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('未检测到局域网地址'),
        findsWidgets,
        reason: '必须给出为什么没有网页链接',
      );
    });
  });

  group('二维码必须编码网页链接', () {
    testWidgets('有 webLink 时 QrPanel.linkText 是 http 开头', (
      WidgetTester tester,
    ) async {
      final FakeMySharesSource source = FakeMySharesSource()
        ..shares = <ShareRecord>[shareRecord(id: 'sh01')]
        ..webLink = Uri.parse('http://10.168.1.115:47778/s/sh01?k=abc');

      await tester.pumpWidget(wrapWithTheme(SharesPage(source: source)));
      await tester.pumpAndSettle();

      // 二维码只在展开状态下渲染（收起时不该用大块区域挤占卡片）。
      await _tapMenu(tester, '展开查看文件');
      final Finder qr = find.byType(QrPanel);
      expect(qr, findsWidgets, reason: '应当渲染二维码');
      final QrPanel panel = tester.widget<QrPanel>(qr.first);
      expect(
        panel.linkText.startsWith('http://'),
        isTrue,
        reason: '扫码的人多半没装 App，必须编码网页链接',
      );
      expect(panel.linkText.contains('/s/'), isTrue);
    });

    testWidgets('webLink 为 null 时不画二维码，给替换文案', (WidgetTester tester) async {
      final FakeMySharesSource source = FakeMySharesSource()
        ..shares = <ShareRecord>[shareRecord(id: 'sh01')]
        ..webLink = null;

      await tester.pumpWidget(wrapWithTheme(SharesPage(source: source)));
      await tester.pumpAndSettle();

      await _tapMenu(tester, '展开查看文件');
      expect(find.byType(QrPanel), findsNothing, reason: '没有可用链接时不能画一个假的码');
      expect(find.textContaining('无可用网页链接'), findsWidgets);
    });
  });

  group('既有能力不退化', () {
    testWidgets('删除 / 重新启用 / 展开 三项仍在菜单里', (WidgetTester tester) async {
      final FakeMySharesSource source = FakeMySharesSource()
        ..shares = <ShareRecord>[shareRecord(id: 'sh01', enabled: false)]
        ..webLink = Uri.parse('http://10.168.1.115:47778/s/sh01?k=abc')
        ..entriesByPath = <String, List<TreeEntryView>>{'': <TreeEntryView>[]};

      await tester.pumpWidget(wrapWithTheme(SharesPage(source: source)));
      await tester.pumpAndSettle();

      await _openMenu(tester);
      expect(find.text('删除'), findsWidgets);
      expect(find.text('重新启用'), findsWidgets);
      expect(find.text('展开查看文件'), findsWidgets);
    });
  });
}
