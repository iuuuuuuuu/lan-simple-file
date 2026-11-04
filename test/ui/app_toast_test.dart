// SPDX-License-Identifier: GPL-3.0-only

/// 浮层 Toast：显示/自动消失/手动关闭/替换策略/单主色约束。
///
/// 这些用例真跑 widget test：真 pump Overlay、真推进时间、真点关闭按钮。
/// 不使用 fake async 捷径掩盖时序——自动消失靠 tester.pump(Duration) 推进真实时钟。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/theme/app_theme.dart';
import 'package:lan_simple_file/app/theme/tokens.dart';
import 'package:lan_simple_file/ui/widgets/app_toast.dart';

/// 装一个带 Overlay 的最小宿主，并暴露一个按钮触发 AppToast。
class _Host extends StatelessWidget {
  const _Host({
    required this.message,
    this.isError = false,
    this.brightness = Brightness.light,
  });

  final String message;
  final bool isError;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.of(LanFilePalette.of(brightness)),
      home: Scaffold(
        body: Builder(
          builder: (BuildContext ctx) => Center(
            child: ElevatedButton(
              key: const ValueKey<String>('trigger'),
              onPressed: () =>
                  AppToast.show(ctx, message, isError: isError),
              child: const Text('触发'),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _trigger(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('trigger')));
  await tester.pump(); // 插入 OverlayEntry
  await tester.pump(const Duration(milliseconds: 200)); // 走完淡入动画
}

void main() {
  // 每个用例后清掉静态状态，避免用例间互相污染。
  tearDown(AppToast.dismiss);

  group('显示与查找', () {
    testWidgets('show 后能在 Overlay 里找到文案', (WidgetTester tester) async {
      await tester.pumpWidget(const _Host(message: '已创建 2 个共享'));
      expect(find.text('已创建 2 个共享'), findsNothing);

      await _trigger(tester);
      expect(find.text('已创建 2 个共享'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('app-toast')), findsOneWidget);
      expect(AppToast.isShowing, isTrue);
    });

    testWidgets('Toast 浮在内容之上且不改变布局', (WidgetTester tester) async {
      await tester.pumpWidget(const _Host(message: '提示'));
      final Rect buttonBefore = tester.getRect(
        find.byKey(const ValueKey<String>('trigger')),
      );
      await _trigger(tester);
      final Rect buttonAfter = tester.getRect(
        find.byKey(const ValueKey<String>('trigger')),
      );
      // 宿主内容位置完全没动，说明是浮层而不是挤压布局。
      expect(buttonAfter, equals(buttonBefore));
    });

    testWidgets('Toast 定位在底部附近（距底约 48px）',
        (WidgetTester tester) async {
      await tester.pumpWidget(const _Host(message: '提示'));
      await _trigger(tester);

      final Rect toast = tester.getRect(
        find.byKey(const ValueKey<String>('app-toast')),
      );
      final double screenBottom = tester.view.physicalSize.height /
          tester.view.devicePixelRatio;
      final double gap = screenBottom - toast.bottom;
      // 允许一点误差：卡片内部有 padding，允许 ±20px 的窗口。
      expect(gap, closeTo(kToastBottomInset, 20));
    });
  });

  group('自动消失', () {
    testWidgets('成功提示 2.5s 后消失', (WidgetTester tester) async {
      await tester.pumpWidget(const _Host(message: '成功'));
      // _trigger 内部已经历 200ms（pump + 淡入），计时从这里累加。
      await _trigger(tester);
      expect(find.text('成功'), findsOneWidget);

      // 累计 200 + 2200 = 2400ms，仍未到 2500ms。
      await tester.pump(const Duration(milliseconds: 2200));
      expect(find.text('成功'), findsOneWidget,
          reason: '2.4s 时还不该消失');

      // 累计 200 + 2200 + 200 = 2600ms，已过 2500ms。
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.text('成功'), findsNothing);
      expect(AppToast.isShowing, isFalse);
    });

    testWidgets('失败提示 5s 后才消失（比成功更久）', (WidgetTester tester) async {
      await tester.pumpWidget(
        const _Host(message: '失败原因：路径不存在', isError: true),
      );
      // _trigger 已经历 200ms。
      await _trigger(tester);
      expect(find.text('失败原因：路径不存在'), findsOneWidget);

      // 累计 200 + 2800 = 3000ms：成功态早在 2500ms 就该没了，失败态仍在。
      await tester.pump(const Duration(milliseconds: 2800));
      expect(find.text('失败原因：路径不存在'), findsOneWidget,
          reason: '失败提示要比成功停留更久');

      // 累计 200 + 2800 + 2200 = 5200ms，已过 5000ms。
      await tester.pump(const Duration(milliseconds: 2200));
      await tester.pump();
      expect(find.text('失败原因：路径不存在'), findsNothing);
    });
  });

  group('手动关闭', () {
    testWidgets('点 × 立刻消失', (WidgetTester tester) async {
      await tester.pumpWidget(const _Host(message: '可关闭'));
      await _trigger(tester);
      expect(find.text('可关闭'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('app-toast-close')));
      await tester.pump();
      expect(find.text('可关闭'), findsNothing);
      expect(AppToast.isShowing, isFalse);
    });

    testWidgets('dismiss 幂等：没有提示时调用不抛', (WidgetTester tester) async {
      await tester.pumpWidget(const _Host(message: 'x'));
      expect(() => AppToast.dismiss(), returnsNormally);
      expect(() => AppToast.dismiss(), returnsNormally);
    });
  });

  group('连续多条：替换策略', () {
    testWidgets('第二条立刻顶掉第一条，且不会堆叠', (WidgetTester tester) async {
      await tester.pumpWidget(const _Host(message: '第一条'));
      await _trigger(tester);
      expect(find.text('第一条'), findsOneWidget);

      // 换文案再触发一次（通过同一个宿主重建不方便，直接调静态入口）。
      final BuildContext ctx = tester.element(find.byType(Scaffold));
      AppToast.show(ctx, '第二条');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('第二条'), findsOneWidget);
      expect(find.text('第一条'), findsNothing, reason: '旧提示必须被替换而不是排队');
      // 树上只有一条 Toast，没有堆叠。
      expect(find.byKey(const ValueKey<String>('app-toast')), findsOneWidget);
    });

    testWidgets('替换后旧定时器不会误删新提示', (WidgetTester tester) async {
      await tester.pumpWidget(const _Host(message: '旧'));
      await _trigger(tester);
      final BuildContext ctx = tester.element(find.byType(Scaffold));

      // 此时旧提示已过 200ms。立刻换成新的：新的从这一刻重新计时。
      AppToast.show(ctx, '新');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('新'), findsOneWidget);

      // 再过 2000ms（新提示累计 2200ms）：旧提示的 2500ms 早已到期，
      // 但新提示必须还活着——证明旧的到期逻辑不会误杀新提示。
      await tester.pump(const Duration(milliseconds: 2000));
      expect(find.text('新'), findsOneWidget,
          reason: '旧提示到期不应关掉新提示');

      // 新提示累计 2200 + 500 = 2700ms，超过自己的 2500ms，正常消失。
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.text('新'), findsNothing);
    });
  });

  group('单主色约束', () {
    testWidgets('成功与失败都不引入红/绿，图标形状不同',
        (WidgetTester tester) async {
      // 成功
      await tester.pumpWidget(const _Host(message: '成功'));
      await _trigger(tester);
      final Iterable<Icon> successIcons = tester.widgetList<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey<String>('app-toast')),
          matching: find.byType(Icon),
        ),
      );
      final Icon successMark = successIcons.firstWhere(
        (Icon i) => i.icon != Icons.close,
      );
      expect(successMark.icon, Icons.check_circle_outline);
      AppToast.dismiss();
      await tester.pump();

      // 失败
      await tester.pumpWidget(
        const _Host(message: '失败', isError: true),
      );
      await _trigger(tester);
      final Iterable<Icon> errorIcons = tester.widgetList<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey<String>('app-toast')),
          matching: find.byType(Icon),
        ),
      );
      final Icon errorMark = errorIcons.firstWhere(
        (Icon i) => i.icon != Icons.close,
      );
      expect(errorMark.icon, Icons.error_outline);
    });

    testWidgets('成功/失败的文字颜色都取自 token，不是红或绿',
        (WidgetTester tester) async {
      for (final bool isError in <bool>[false, true]) {
        await tester.pumpWidget(
          _Host(message: 'msg', isError: isError),
        );
        await _trigger(tester);

        final LanFileTokens tokens = Theme.of(
          tester.element(find.byKey(const ValueKey<String>('app-toast'))),
        ).extension<LanFileTokens>()!;

        final Text text = tester.widget<Text>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('app-toast')),
            matching: find.byType(Text),
          ).last,
        );
        // 正文用 token 的 fg；既不是纯红也不是纯绿。
        expect(text.style!.color, equals(tokens.fg));
        expect(text.style!.color, isNot(const Color(0xFFFF0000)));
        expect(text.style!.color, isNot(const Color(0xFF00FF00)));

        AppToast.dismiss();
        await tester.pump();
      }
    });

    testWidgets('失败字重比成功更重（可断言的视觉差异）',
        (WidgetTester tester) async {
      FontWeight weightOf(WidgetTester t) {
        final Text text = t.widget<Text>(
          find.descendant(
            of: find.byKey(const ValueKey<String>('app-toast')),
            matching: find.byType(Text),
          ).last,
        );
        return text.style!.fontWeight!;
      }

      await tester.pumpWidget(const _Host(message: 'm'));
      await _trigger(tester);
      final FontWeight successWeight = weightOf(tester);
      AppToast.dismiss();
      await tester.pump();

      await tester.pumpWidget(const _Host(message: 'm', isError: true));
      await _trigger(tester);
      final FontWeight errorWeight = weightOf(tester);

      expect(errorWeight.value, greaterThan(successWeight.value));
    });
  });

  group('不受界面动画影响', () {
    testWidgets('pumpAndSettle（别处动画收尾）不会顺手关掉提示',
        (WidgetTester tester) async {
      // 真实场景：用户正在读提示，页面别处一个动画结束。
      // 若自动消失由 AnimationController 驱动，pumpAndSettle 会把它一路推到结束，
      // 提示被无辜顶掉——必须用按真实时间走的 Timer 才不受影响。
      await tester.pumpWidget(const _Host(message: '别顶掉我'));
      await tester.tap(find.byKey(const ValueKey<String>('trigger')));
      await tester.pumpAndSettle();

      expect(
        find.text('别顶掉我'),
        findsOneWidget,
        reason: 'pumpAndSettle 不应关闭提示（否则用户读一半就消失）',
      );
      expect(AppToast.isShowing, isTrue);
    });

    testWidgets('pumpAndSettle 之后，提示仍按自己的时长到期',
        (WidgetTester tester) async {
      await tester.pumpWidget(const _Host(message: '按时间走'));
      await tester.tap(find.byKey(const ValueKey<String>('trigger')));
      await tester.pumpAndSettle();
      expect(find.text('按时间走'), findsOneWidget);

      // 再推进到超过 2.5s，才应该消失。
      await tester.pump(const Duration(milliseconds: 2700));
      await tester.pump();
      expect(find.text('按时间走'), findsNothing);
    });
  });

  group('明暗主题', () {
    testWidgets('Toast 底色随主题取对应 surface', (WidgetTester tester) async {
      for (final Brightness brightness in Brightness.values) {
        await tester.pumpWidget(
          _Host(message: '主题', brightness: brightness),
        );
        await _trigger(tester);

        final Container card = tester.widget<Container>(
          find
              .descendant(
                of: find.byKey(const ValueKey<String>('app-toast')),
                matching: find.byType(Container),
              )
              .first,
        );
        final LanFileTokens expected = brightness == Brightness.dark
            ? LanFilePalette.dark
            : LanFilePalette.light;
        expect((card.decoration! as BoxDecoration).color,
            equals(expected.surface));

        AppToast.dismiss();
        await tester.pump();
      }
    });
  });

  group('无 Overlay 的降级', () {
    testWidgets('context 之上没有 Overlay 时不抛，只是不显示',
        (WidgetTester tester) async {
      late BuildContext bare;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (BuildContext ctx) {
              bare = ctx;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // 没有 MaterialApp/Overlay：不能崩，也不能假装显示成功。
      expect(
        () => AppToast.show(bare, '无宿主'),
        returnsNormally,
      );
      expect(AppToast.isShowing, isFalse);
    });
  });
}