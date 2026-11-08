// SPDX-License-Identifier: GPL-3.0-only

/// QQ 三栏外壳：宽屏三栏、窄屏抽屉、null services、明暗 token、拖入开关。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/miuix_test_support.dart';

import 'package:lan_simple_file/app/theme/app_theme.dart';
import 'package:lan_simple_file/app/theme/tokens.dart';
import 'package:lan_simple_file/ui/shell/qq_shell.dart';
import 'package:lan_simple_file/ui/shell/session_list.dart';
import 'package:lan_simple_file/ui/shell/session_rail.dart';
import 'package:lan_simple_file/ui/widgets/drop_share_overlay.dart';

/// 假会话来源：按 section 返回预设行，记录被问过的 section。
final class FakeSessionSource implements ShellSessionSource {
  /// section -> 行。
  Map<ShellSection, List<SessionRowData>> rows =
      <ShellSection, List<SessionRowData>>{};

  /// 被调用过的 section（断言切换时真的重新拉取）。
  final List<ShellSection> queried = <ShellSection>[];

  @override
  Future<List<SessionRowData>> rowsFor(ShellSection section) async {
    queried.add(section);
    return rows[section] ?? const <SessionRowData>[];
  }

  @override
  String titleFor(ShellSection section) => section.label;
}

/// 记录建共享调用次数的拖入处理器。
final class FakeDropHandler implements DropShareHandler {
  /// 每次收到的路径批次。
  final List<List<String>> batches = <List<String>>[];

  @override
  Future<int> createFromPaths(List<String> paths) async {
    batches.add(paths);
    return paths.length;
  }
}

/// 只装主题，**不**注入 MediaQuery：视口尺寸一律由 tester.view 决定。
///
/// 早期版本在这里包了一层 MediaQuery(size: 1280x800)，结果把所有窄屏用例
/// 都骗成了宽屏（外壳读到 1280，看到的三栏永远存在）。测试必须只看真实视口。
Widget wrapShell(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    builder: (context, child) => AppMiuixTheme(child: child!),
    theme: AppTheme.of(LanFilePalette.of(brightness)),
    home: child,
  );
}

/// 用真实 MediaQuery 控制视口宽度（tester.view 更贴近真实布局）。
Future<void> setViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('宽屏三栏', () {
    testWidgets('>=1000px 时 rail / list / content 同时存在', (
      WidgetTester tester,
    ) async {
      await setViewport(tester, const Size(1280, 800));
      await tester.pumpWidget(
        wrapShell(QqShell(sessionSource: FakeSessionSource())),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('shell-rail')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('shell-list')), findsOneWidget);
      expect(find.byKey(kShellContentKey), findsOneWidget);

      // 三栏真实并排：rail 在 list 左侧，list 在 content 左侧。
      final Rect rail = tester.getRect(
        find.byKey(const ValueKey<String>('shell-rail')),
      );
      final Rect list = tester.getRect(
        find.byKey(const ValueKey<String>('shell-list')),
      );
      final Rect content = tester.getRect(find.byKey(kShellContentKey));
      expect(rail.right, lessThanOrEqualTo(list.left));
      expect(list.right, lessThanOrEqualTo(content.left));
    });

    testWidgets('rail 宽度落在 56-64px，list 宽度落在 260-300px', (
      WidgetTester tester,
    ) async {
      await setViewport(tester, const Size(1280, 800));
      await tester.pumpWidget(
        wrapShell(QqShell(sessionSource: FakeSessionSource())),
      );
      await tester.pumpAndSettle();

      final double railWidth = tester
          .getRect(find.byKey(const ValueKey<String>('shell-rail')))
          .width;
      final double listWidth = tester
          .getRect(find.byKey(const ValueKey<String>('shell-list')))
          .width;
      expect(railWidth, inInclusiveRange(56, 64));
      expect(listWidth, inInclusiveRange(260, 300));
    });

    testWidgets('宽屏不提供抽屉（避免两个入口）', (WidgetTester tester) async {
      await setViewport(tester, const Size(1280, 800));
      await tester.pumpWidget(
        wrapShell(QqShell(sessionSource: FakeSessionSource())),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('shell-open-drawer')),
        findsNothing,
      );
    });
  });

  group('窄屏抽屉', () {
    testWidgets('900px 时仍显示左侧分组，删除抽屉入口', (WidgetTester tester) async {
      await setViewport(tester, const Size(900, 800));
      await tester.pumpWidget(
        wrapShell(QqShell(sessionSource: FakeSessionSource())),
      );
      await tester.pumpAndSettle();

      // 三栏里的 list 不应直接渲染在页面上。
      expect(find.byKey(const ValueKey<String>('shell-list')), findsOneWidget);
      // 抽屉入口存在。
      expect(
        find.byKey(const ValueKey<String>('shell-open-drawer')),
        findsNothing,
      );
      // rail 与 content 仍在。
      expect(find.byKey(const ValueKey<String>('shell-rail')), findsOneWidget);
      expect(find.byKey(kShellContentKey), findsOneWidget);
    });

    testWidgets('任何页面都没有打开会话列表入口或抽屉', (WidgetTester tester) async {
      await setViewport(tester, const Size(900, 800));
      await tester.pumpWidget(
        wrapShell(QqShell(sessionSource: FakeSessionSource())),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('shell-open-drawer')),
        findsNothing,
      );
      expect(find.byType(Drawer), findsNothing);
      expect(find.byKey(const ValueKey<String>('shell-list')), findsOneWidget);
    });
  });

  group('图标栏', () {
    testWidgets('顶部是本机头像，底部是设置齿轮，两者都能进设置', (WidgetTester tester) async {
      await setViewport(tester, const Size(1280, 800));
      await tester.pumpWidget(
        wrapShell(QqShell(sessionSource: FakeSessionSource())),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('rail-self-avatar')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('rail-settings')),
        findsOneWidget,
      );

      // 点头像 -> 设置 section。
      //
      // 断言改成真实设置页的标志性内容（GPL 声明在「关于」分组，永远在页面里），
      // 而不是旧占位文案——占位已被真实页面取代，此处保留的强度是
      // 「确实进到了设置页」而不是「进到了一个空壳」。
      await tester.tap(find.byKey(const ValueKey<String>('rail-self-avatar')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('GPL-3.0-only'),
        findsWidgets,
        reason: '设置页的「关于」分组必须出现许可声明',
      );

      // 齿轮同样进设置（先切走再点）。
      await tester.tap(find.byKey(const ValueKey<String>('rail-nearby')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('rail-settings')));
      await tester.pumpAndSettle();
      expect(find.textContaining('GPL-3.0-only'), findsWidgets);
    });

    testWidgets('点导航图标切换 section 并重新拉取列表', (WidgetTester tester) async {
      await setViewport(tester, const Size(1280, 800));
      final FakeSessionSource source = FakeSessionSource();
      await tester.pumpWidget(wrapShell(QqShell(sessionSource: source)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('rail-shares')));
      await tester.pumpAndSettle();
      expect(source.queried, contains(ShellSection.shares));
      expect(find.byKey(const ValueKey<String>('shell-list')), findsNothing);
    });
  });

  group('services 为 null', () {
    testWidgets('三栏骨架仍在，内容区显示未连接服务，不崩溃', (WidgetTester tester) async {
      await setViewport(tester, const Size(1280, 800));
      await tester.pumpWidget(wrapShell(const QqShell(services: null)));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('shell-rail')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('shell-list')), findsOneWidget);
      expect(find.byKey(kShellContentKey), findsOneWidget);
      expect(find.text('选择联系人或群聊'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('明暗主题', () {
    testWidgets('rail 背景随主题在明暗两套 token 间切换', (WidgetTester tester) async {
      for (final Brightness brightness in Brightness.values) {
        await setViewport(tester, const Size(1280, 800));
        await tester.pumpWidget(
          wrapShell(
            QqShell(sessionSource: FakeSessionSource()),
            brightness: brightness,
          ),
        );
        await tester.pumpAndSettle();

        final LanFileTokens expected = brightness == Brightness.dark
            ? LanFilePalette.dark
            : LanFilePalette.light;

        final railContext = tester.element(
          find.byKey(const ValueKey('shell-rail')),
        );
        final railColor = MiuixNavigationRailDefaults.colors(railContext)
            .background;
        // 最远层：页面底色。
        expect(railColor, equals(expected.bg));

        final Container list = tester.widget<Container>(
          find.byKey(const ValueKey<String>('shell-list')),
        );
        // 中间层：surfaceSunken，必须与 rail 有明显明度差。
        expect(list.color, equals(expected.surfaceSunken));
        expect(list.color, isNot(equals(railColor)), reason: '三块背景必须有可见层次差');
      }
    });
  });

  group('拖入建共享', () {
    testWidgets('enableDragDrop=true 时 DropTarget 生效', (
      WidgetTester tester,
    ) async {
      await setViewport(tester, const Size(1280, 800));
      final FakeDropHandler handler = FakeDropHandler();
      await tester.pumpWidget(
        wrapShell(
          QqShell(
            sessionSource: FakeSessionSource(),
            enableDragDrop: true,
            dropHandler: handler,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 启用时页面里应有 DropTarget 包裹层。
      expect(find.byType(DropShareOverlay), findsOneWidget);
    });

    testWidgets('enableDragDrop=false（模拟 Android）时没有 DropTarget 包裹', (
      WidgetTester tester,
    ) async {
      await setViewport(tester, const Size(1280, 800));
      await tester.pumpWidget(
        wrapShell(
          QqShell(sessionSource: FakeSessionSource(), enableDragDrop: false),
        ),
      );
      await tester.pumpAndSettle();
      // 组件仍在树上，但内部不注册监听、不渲染遮罩。
      expect(
        find.byKey(const ValueKey<String>('drop-share-mask')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
