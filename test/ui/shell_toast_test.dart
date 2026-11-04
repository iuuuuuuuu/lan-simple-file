// SPDX-License-Identifier: GPL-3.0-only

/// 外壳不再用顶部提示条：拖入结果必须走 AppToast 浮层。
///
/// 用户原话：「报错还是等等提示，弹一个 message 或者 toast 就行了，
/// 不要上面显示个内个啥」——本用例把「顶部条不许再出现提示文本」钉死。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/theme/app_theme.dart';
import 'package:lan_simple_file/app/theme/tokens.dart';
import 'package:lan_simple_file/ui/shell/qq_shell.dart';
import 'package:lan_simple_file/ui/shell/session_list.dart';
import 'package:lan_simple_file/ui/shell/session_rail.dart';
import 'package:lan_simple_file/ui/widgets/app_toast.dart';

/// 空会话来源。
final class EmptySource implements ShellSessionSource {
  @override
  Future<List<SessionRowData>> rowsFor(ShellSection section) async =>
      const <SessionRowData>[];

  @override
  String titleFor(ShellSection section) => section.label;
}

Widget wrapShell({Brightness brightness = Brightness.light}) => MaterialApp(
      theme: AppTheme.of(LanFilePalette.of(brightness)),
      home: QqShell(
        sessionSource: EmptySource(),
        enableDragDrop: false, // 拖拽关闭，避免注册平台监听
      ),
    );

void main() {
  tearDown(AppToast.dismiss);

  group('顶部不再有提示条', () {
    testWidgets('外壳里没有承载提示文本的顶部区域', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrapShell());
      await tester.pumpAndSettle();

      // 顶部条还在（放抽屉入口与标题），但只剩标题与菜单，没有提示区。
      final Finder topBar =
          find.byKey(const ValueKey<String>('shell-top-bar'));
      expect(topBar, findsOneWidget);

      // 顶部条内不应有「关闭提示」按钮——那是旧实现留下的痕迹。
      expect(
        find.descendant(
          of: topBar,
          matching: find.byTooltip('关闭提示'),
        ),
        findsNothing,
      );
      // 顶部条内也不该出现 AppToast。
      expect(
        find.descendant(
          of: topBar,
          matching: find.byKey(const ValueKey<String>('app-toast')),
        ),
        findsNothing,
      );
    });

    testWidgets('拖入结果是浮层 Toast，而不是顶部条文本',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrapShell());
      await tester.pumpAndSettle();

      // 直接验证浮层入口：外壳里的 onResult 调的就是它。
      final BuildContext ctx = tester.element(
        find.byKey(const ValueKey<String>('shell-top-bar')),
      );
      AppToast.show(ctx, '已创建 2 个共享', isError: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Toast 出现在 Overlay（浮层），文案可读。
      expect(find.text('已创建 2 个共享'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('app-toast')), findsOneWidget);

      // 顶部条里**没有**这段文本：证明提示不再落在顶部。
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('shell-top-bar')),
          matching: find.text('已创建 2 个共享'),
        ),
        findsNothing,
      );

      // 浮层不挤压布局：顶部条高度不变。
      final Rect barRect = tester.getRect(
        find.byKey(const ValueKey<String>('shell-top-bar')),
      );
      expect(barRect.height, 44);
    });

    testWidgets('失败提示同样走浮层且带原因', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrapShell());
      await tester.pumpAndSettle();

      final BuildContext ctx = tester.element(
        find.byKey(const ValueKey<String>('shell-top-bar')),
      );
      AppToast.show(
        ctx,
        '已创建 1 个共享，1 个失败：照片.jpg — 路径不存在',
        isError: true,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 失败文案必须带具体原因，不能只说「失败」。
      expect(
        find.textContaining('照片.jpg — 路径不存在'),
        findsOneWidget,
      );
      // 且不在顶部条。
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('shell-top-bar')),
          matching: find.textContaining('路径不存在'),
        ),
        findsNothing,
      );
    });
  });

  group('外壳骨架未受影响', () {
    testWidgets('三栏仍在，services=null 也不崩', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.of(LanFilePalette.light),
        home: const QqShell(services: null, enableDragDrop: false),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('shell-rail')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('shell-list')), findsOneWidget);
      expect(find.byKey(kShellContentKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}