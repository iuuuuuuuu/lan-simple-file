// SPDX-License-Identifier: GPL-3.0-only

/// 代码与 UI 分离层：由 token 构造 ThemeData，并提供三态主题模式的控制器。
///
/// 双色约束在此落地：ColorScheme 的每个槽位都只从 [LanFileTokens] 派生，
/// 不引入计划之外的第二个色相。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tokens.dart';

/// 主题模式三态：跟随系统 / 强制明色 / 强制暗色。
enum AppThemeMode {
  /// 跟随系统亮度。
  system,

  /// 强制明色。
  light,

  /// 强制暗色。
  dark,
}

/// 三态与 Material 类型、设置项字符串之间的映射。
extension AppThemeModeX on AppThemeMode {
  /// 传给 MaterialApp 的 ThemeMode。
  ThemeMode get themeMode => switch (this) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };

  /// 用于设置项的稳定字符串。
  String get storageKey => name;

  /// 界面上的短标签。
  String get label => switch (this) {
        AppThemeMode.system => '跟随系统',
        AppThemeMode.light => '明色',
        AppThemeMode.dark => '暗色',
      };

  /// 从设置项字符串解析；无法识别时回落到跟随系统。
  static AppThemeMode parse(String? raw) {
    for (final AppThemeMode mode in AppThemeMode.values) {
      if (mode.name == raw) return mode;
    }
    return AppThemeMode.system;
  }
}

/// 明暗两套 [ThemeData] 的装配入口。
abstract final class AppTheme {
  /// 明色主题。
  static ThemeData get light => _build(LanFilePalette.light);

  /// 暗色主题。
  static ThemeData get dark => _build(LanFilePalette.dark);

  /// 按 token 取对应 ThemeData。
  static ThemeData of(LanFileTokens tokens) => _build(tokens);

  static ThemeData _build(LanFileTokens t) {
    final bool isDark = t.isDark;
    final Color onAccent = t.onAccent;
    final ColorScheme scheme = ColorScheme(
      brightness: t.brightness,
      primary: t.accent,
      onPrimary: onAccent,
      primaryContainer: t.accent,
      onPrimaryContainer: onAccent,
      secondary: t.fgDim,
      onSecondary: isDark ? t.bg : t.surface,
      tertiary: t.accent,
      onTertiary: onAccent,
      error: t.fg,
      onError: isDark ? t.bg : t.surface,
      surface: t.surface,
      onSurface: t.fg,
      surfaceContainerLowest: t.bg,
      surfaceContainerLow: t.surface,
      surfaceContainer: t.surface,
      surfaceContainerHigh: t.surface,
      surfaceContainerHighest: t.line,
      onSurfaceVariant: t.fgDim,
      outline: t.line,
      outlineVariant: t.line,
    );

    final TextTheme base = Typography.material2021(
      platform: TargetPlatform.windows,
      colorScheme: scheme,
    ).black;
    final TextTheme textTheme = base.apply(
      bodyColor: t.fg,
      displayColor: t.fg,
    );

    return ThemeData(
      brightness: t.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: t.bg,
      canvasColor: t.bg,
      dividerColor: t.line,
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[t],
      appBarTheme: AppBarTheme(
        backgroundColor: t.bg,
        foregroundColor: t.fg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        shadowColor: t.line,
        titleTextStyle: TextStyle(
          color: t.fg,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: DividerThemeData(color: t.line, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: t.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: t.line),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: t.fgDim,
        textColor: t.fg,
        selectedColor: t.accent,
        selectedTileColor: t.accent.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: t.accent.withValues(alpha: 0.14),
        elevation: 0,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          final bool selected = states.contains(WidgetState.selected);
          return IconThemeData(size: 22, color: selected ? t.accent : t.fgDim);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((
          Set<WidgetState> states,
        ) {
          final bool selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? t.accent : t.fgDim,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: t.bg,
        indicatorColor: t.accent.withValues(alpha: 0.14),
        selectedIconTheme: IconThemeData(color: t.accent, size: 22),
        unselectedIconTheme: IconThemeData(color: t.fgDim, size: 22),
        selectedLabelTextStyle: TextStyle(
          color: t.accent,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(color: t.fgDim, fontSize: 12),
      ),
      iconTheme: IconThemeData(color: t.fgDim, size: 20),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: t.accent,
          foregroundColor: onAccent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: t.accent),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.fg,
          side: BorderSide(color: t.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: t.bg,
        hintStyle: TextStyle(color: t.fgDim),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: t.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: t.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: t.accent, width: 1.5),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: t.accent,
        linearTrackColor: t.line,
        circularTrackColor: t.line,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: t.fg,
        contentTextStyle: TextStyle(color: isDark ? t.bg : t.surface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: t.fg,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: TextStyle(color: isDark ? t.bg : t.surface, fontSize: 12),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll<Color>(
          t.fgDim.withValues(alpha: 0.5),
        ),
        radius: const Radius.circular(4),
        thickness: const WidgetStatePropertyAll<double>(6),
      ),
    );
  }
}

/// 主题模式的持久化接口；接 store 时实现 settings 表即可。
abstract interface class ThemeModeStore {
  /// 读取已保存的模式；没有则 null。
  Future<String?> read();

  /// 保存模式。
  Future<void> write(String value);
}

/// 内存实现，供测试与早期骨架使用。
final class InMemoryThemeModeStore implements ThemeModeStore {
  /// 可选初始值。
  InMemoryThemeModeStore([String? initial]) : _value = initial;

  String? _value;

  /// 当前值，便于测试断言落盘结果。
  String? get value => _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String value) async {
    _value = value;
  }
}

/// 三态主题模式的当前值；切换立即重建界面，落盘异步进行。
final class ThemeModeController extends Notifier<AppThemeMode> {
  ThemeModeStore? _store;

  @override
  AppThemeMode build() => AppThemeMode.system;

  /// 绑定持久化实现并载入已保存的值。
  Future<void> hydrate(ThemeModeStore store) async {
    _store = store;
    final String? saved = await store.read();
    if (saved != null) {
      state = AppThemeModeX.parse(saved);
    }
  }

  /// 切换模式：先改内存态让界面立刻重建，再异步落盘。
  Future<void> setMode(AppThemeMode mode) async {
    if (state == mode) return;
    state = mode;
    final ThemeModeStore? store = _store;
    if (store != null) {
      await store.write(mode.storageKey);
    }
  }

  /// system → dark → light → system 轮换，供外壳按钮使用。
  Future<void> cycle() async {
    final AppThemeMode next = switch (state) {
      AppThemeMode.system => AppThemeMode.dark,
      AppThemeMode.dark => AppThemeMode.light,
      AppThemeMode.light => AppThemeMode.system,
    };
    await setMode(next);
  }
}

/// 全局主题模式。
final NotifierProvider<ThemeModeController, AppThemeMode> themeModeProvider =
    NotifierProvider<ThemeModeController, AppThemeMode>(
  ThemeModeController.new,
);

/// 主题模式持久化实现；接入 store 时在 ProviderScope 里覆盖它。
///
/// 早期骨架用内存实现，重启即回到跟随系统，因此不产生虚假的「已记住」预期。
final Provider<ThemeModeStore> themeModeStoreProvider =
    Provider<ThemeModeStore>((Ref ref) => InMemoryThemeModeStore());
