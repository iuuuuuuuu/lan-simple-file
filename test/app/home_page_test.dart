// SPDX-License-Identifier: GPL-3.0-only

/// 应用外壳测试：五 tab 导航、三态主题切换即时生效、默认头像回落。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/app.dart';
import 'package:lan_simple_file/app/theme/app_theme.dart';
import 'package:lan_simple_file/app/theme/tokens.dart';
import 'package:lan_simple_file/app/widgets/identicon.dart';
import 'package:lan_simple_file/ui/pages/home_page.dart';
import 'package:lan_simple_file/ui/shell/qq_shell.dart' show kShellContentKey;

import '../ui/support/miuix_test_support.dart';

/// 用固定尺寸 + 指定主题模式装配被测树。
Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  AppThemeMode? mode,
  HomeTab tab = HomeTab.nearby,
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final ProviderContainer container = ProviderContainer();
  addTearDown(container.dispose);
  if (mode != null) {
    container.read(themeModeProvider.notifier).setMode(mode);
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: LanFileApp(initialTab: tab),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('外壳骨架', () {
    testWidgets('保留旧群组路由枚举，传输入口改为记录', (WidgetTester tester) async {
      await _pumpApp(tester);
      expect(HomeTab.values, hasLength(5));
      expect(HomeTab.values.map((HomeTab t) => t.label).toList(), <String>[
        '附近',
        '我的分享',
        '群组',
        '传输记录',
        '设置',
      ]);
      // 外壳已改为三栏：最窄图标栏 + 会话列表 + 内容区，用 Key 断言结构存在。
      expect(find.byKey(const ValueKey<String>('app-navigation')), findsOneWidget);
    });

    testWidgets('默认落在「附近」并渲染真实页面（无服务时给未连接提示）', (WidgetTester tester) async {
      await _pumpApp(tester);
      // 占位文案已被真实页面取代；未注入服务时应显示可读提示而不是空白/崩溃。
      expect(find.text('选择联系人或群聊'), findsOneWidget);
      expect(find.textContaining('M1 实现'), findsNothing, reason: '占位文案不应再出现');
    });

    testWidgets('宽屏是三栏（图标栏 + 会话列表 + 内容区），不是旧的两栏', (WidgetTester tester) async {
      await _pumpApp(tester, size: const Size(1280, 800));
      // 旧实现的两种导航都必须消失（它们正是「工具型两栏」的形态）。
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(ListTile), findsNothing);
      // 新结构的三个锚点都在。
      expect(find.byKey(const ValueKey<String>('app-navigation')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('shell-list')), findsOneWidget);
      expect(find.byKey(kShellContentKey), findsOneWidget);
    });

    testWidgets('手机使用底部悬浮导航，不显示桌面左侧图标栏', (WidgetTester tester) async {
      await _pumpApp(tester, size: const Size(420, 900));
      expect(find.byType(NavigationBar), findsNothing, reason: '窄屏不该退回旧底部导航');
      expect(find.byKey(const ValueKey<String>('shell-rail')), findsNothing);
      expect(find.byKey(const ValueKey('app-navigation')), findsOneWidget);
    });

    testWidgets('点图标栏进入可搜索的传输记录页', (WidgetTester tester) async {
      await _pumpApp(tester, size: const Size(1280, 800));
      await tester.tap(find.byKey(const ValueKey<String>('nav-transfers')));
      await tester.pumpAndSettle();
      expect(find.text('传输记录'), findsWidgets);
      expect(
        find.byKey(const ValueKey('transfer-history-search')),
        findsOneWidget,
      );
    });

    testWidgets('点本机头像进入设置页，设置页有许可声明', (WidgetTester tester) async {
      await _pumpApp(tester, size: const Size(1280, 800));
      await tester.tap(find.byKey(const ValueKey<String>('shell-self-avatar')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('GPL-3.0-only'),
        findsWidgets,
        reason: '设置页必须是真实页面而不是占位',
      );
    });
  });

  group('三态主题切换', () {
    testWidgets('手机搜索键盘只扣减一次高度并隐藏底部导航', (tester) async {
      await _pumpApp(tester, size: const Size(360, 640));
      await tester.showKeyboard(find.byKey(const ValueKey('session-search')));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('app-navigation')), findsNothing);
      final search = tester.getRect(
        find.byKey(const ValueKey('session-search')),
      );
      expect(search.bottom, lessThanOrEqualTo(340));
      final list = tester.getRect(find.byKey(const ValueKey('shell-list')));
      expect(list.bottom, closeTo(340, 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('默认跟随系统', (WidgetTester tester) async {
      final ProviderContainer c = await _pumpApp(tester);
      expect(c.read(themeModeProvider), AppThemeMode.system);
      final MaterialApp app = tester.widget<MaterialApp>(
        find.byType(MaterialApp),
      );
      expect(app.themeMode, ThemeMode.system);
    });

    testWidgets('点击按钮轮换 system → dark → light → system 且立即生效', (
      WidgetTester tester,
    ) async {
      final ProviderContainer c = await _pumpApp(tester);

      Future<void> tapCycle() async {
        await tester.tap(findAppTooltip(RegExp('^主题：')));
        await tester.pumpAndSettle();
      }

      await tapCycle();
      expect(c.read(themeModeProvider), AppThemeMode.dark);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );

      await tapCycle();
      expect(c.read(themeModeProvider), AppThemeMode.light);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light,
      );

      await tapCycle();
      expect(c.read(themeModeProvider), AppThemeMode.system);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );
    });

    testWidgets('切到暗色后，界面取到的 token 变成暗色那套', (WidgetTester tester) async {
      final ProviderContainer c = await _pumpApp(
        tester,
        mode: AppThemeMode.dark,
      );
      expect(c.read(themeModeProvider), AppThemeMode.dark);
      final BuildContext ctx = tester.element(find.byType(AppScaffold).first);
      expect(tokensOf(ctx), equals(LanFilePalette.dark));
      expect(Theme.of(ctx).scaffoldBackgroundColor, LanFilePalette.dark.bg);
    });

    testWidgets('强制明色时 token 是明色那套', (WidgetTester tester) async {
      await _pumpApp(tester, mode: AppThemeMode.light);
      final BuildContext ctx = tester.element(find.byType(AppScaffold).first);
      expect(tokensOf(ctx), equals(LanFilePalette.light));
    });

    testWidgets('主题切换不会改变默认头像的设备标识', (WidgetTester tester) async {
      final c = await _pumpApp(tester, mode: AppThemeMode.light);
      final first = tester.widget<Identicon>(find.byType(Identicon).first);

      await c.read(themeModeProvider.notifier).setMode(AppThemeMode.dark);
      await tester.pumpAndSettle();

      expect(c.read(themeModeProvider), AppThemeMode.dark);
      expect(
        tester.widget<Identicon>(find.byType(Identicon).first).peerId,
        first.peerId,
      );
    });
  });

  group('主题模式持久化', () {
    test('hydrate 读取已保存模式', () async {
      final InMemoryThemeModeStore store = InMemoryThemeModeStore(
        AppThemeMode.dark.storageKey,
      );
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(themeModeProvider), AppThemeMode.system);
      await c.read(themeModeProvider.notifier).hydrate(store);
      expect(c.read(themeModeProvider), AppThemeMode.dark);
    });

    test('setMode 落盘，重复设同值不重复写', () async {
      final _CountingStore store = _CountingStore();
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(themeModeProvider.notifier).hydrate(store);

      await c.read(themeModeProvider.notifier).setMode(AppThemeMode.light);
      expect(store.value, AppThemeMode.light.storageKey);
      expect(store.writes, 1);

      await c.read(themeModeProvider.notifier).setMode(AppThemeMode.light);
      expect(store.writes, 1, reason: '同值不应重复落盘');
    });

    test('setMode 后立刻可读，落盘异步不阻塞状态', () async {
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);
      final Future<void> pending = c
          .read(themeModeProvider.notifier)
          .setMode(AppThemeMode.dark);
      expect(c.read(themeModeProvider), AppThemeMode.dark);
      await pending;
    });
  });

  group('PeerAvatar 回落', () {
    Widget wrap(Widget child, {Brightness brightness = Brightness.light}) {
      return MaterialApp(
        theme: AppTheme.of(LanFilePalette.of(brightness)),
        home: Scaffold(body: Center(child: child)),
      );
    }

    testWidgets('没有自定义头像时永远显示 identicon', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(const PeerAvatar(peerId: 'p_aaa111bbb222z')),
      );
      expect(find.byType(Identicon), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('avatarBytes 为空数组时同样回落到 identicon', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(PeerAvatar(peerId: 'p_aaa111bbb222z', avatarBytes: Uint8List(0))),
      );
      expect(find.byType(Identicon), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('有自定义头像时显示图片而不是 identicon', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(PeerAvatar(peerId: 'p_aaa111bbb222z', avatarBytes: _onePixelPng)),
      );
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(Identicon), findsNothing);
    });
  });
}

/// 记录写入次数的测试用存储。
final class _CountingStore implements ThemeModeStore {
  String? value;
  int writes = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String v) async {
    value = v;
    writes++;
  }
}

/// 1×1 透明 PNG。
final Uint8List _onePixelPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);
