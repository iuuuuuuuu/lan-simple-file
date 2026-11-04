// SPDX-License-Identifier: GPL-3.0-only

/// 悬浮自动下拉菜单的交互回归。
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/ui/pages/shares_page.dart';

import 'support/ui_fakes.dart';

void main() {
  testWidgets('鼠标悬浮在更多操作图标上会自动展开菜单（不用点）', (WidgetTester tester) async {
    final FakeMySharesSource source = FakeMySharesSource()
      ..shares = <ShareRecord>[shareRecord(id: 'sh01', displayName: 'dist')]
      ..webLink = Uri.parse('http://10.168.1.115:47778/s/sh01?k=abc');
    await tester.pumpWidget(wrapWithTheme(SharesPage(source: source)));
    await tester.pumpAndSettle();

    final Finder icon = find.byKey(
      const ValueKey<String>('share-actions-menu'),
    );
    expect(icon, findsOneWidget);

    // 悬浮前：菜单项不可见。
    expect(find.text('复制网页链接'), findsNothing);

    // 模拟鼠标进入图标区域（不点击）。
    final TestGesture gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    await gesture.addPointer(location: tester.getCenter(icon));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    // 自动展开：菜单项出现。
    expect(find.text('复制网页链接'), findsWidgets, reason: '用户要求「悬浮自动下拉」，不需要点击');

    // 每帧都检查持续悬浮，防止遮罩触发退出/进入而反复开关。
    for (int frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text('复制网页链接'),
        findsOneWidget,
        reason: '鼠标不动时菜单不能闪烁（第 $frame 帧）',
      );
    }
    await gesture.moveTo(tester.getCenter(find.text('设置分享名称')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('复制网页链接'), findsOneWidget);
    await gesture.moveTo(tester.getCenter(icon));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('复制网页链接'), findsOneWidget);

    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    expect(find.text('复制网页链接'), findsNothing, reason: '点击菜单外应立即关闭');
    await gesture.moveTo(const Offset(5, 5));
    await gesture.moveTo(tester.getCenter(icon));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('复制网页链接'), findsOneWidget);

    // 移开鼠标后应缓冲关闭。
    await gesture.moveTo(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('复制网页链接'), findsNothing);
    await gesture.removePointer();
  });
}
