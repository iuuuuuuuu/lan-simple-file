// SPDX-License-Identifier: GPL-3.0-only

/// 主题 token 测试：明暗两套色值逐字对齐 docs/plan.md §7.1，
/// 且 ThemeData 通过 ThemeExtension 正确暴露、不引入第二个色相。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:lan_simple_file/app/app.dart';
import 'package:lan_simple_file/app/theme/app_theme.dart';
import 'package:lan_simple_file/app/theme/tokens.dart';

void main() {
  testWidgets(
    'Miuix and page text share font family and regular/medium weights',
    (tester) async {
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            builder: (_, child) => AppMiuixTheme(child: child!),
            home: Builder(
              builder: (context) {
                final text = Theme.of(context).textTheme;
                final miuix = MiuixTheme.of(context).textStyles;
                expect(text.bodyMedium!.fontWeight, FontWeight.w400);
                expect(text.labelLarge!.fontWeight, FontWeight.w400);
                expect(text.titleMedium!.fontWeight, FontWeight.w500);
                expect(miuix.body2.fontFamily, text.bodyMedium!.fontFamily);
                expect(miuix.body2.fontWeight, FontWeight.w400);
                expect(miuix.button.fontWeight, FontWeight.w400);
                expect(miuix.subtitle.fontWeight, FontWeight.w500);
                expect(miuix.title4.fontWeight, FontWeight.w500);
                expect(miuix.body2.letterSpacing, 0);
                return const SizedBox();
              },
            ),
          ),
        );
      }
    },
  );
  group('LanFilePalette 色值', () {
    test('明色六个 token 与 Miuix 一致', () {
      const LanFileTokens t = LanFilePalette.light;
      final colors = MiuixThemeData.of(Brightness.light).colors;
      expect(t.brightness, Brightness.light);
      expect(t.bg, colors.surface);
      expect(t.surface, colors.background);
      expect(t.line, colors.dividerLine);
      expect(t.fg, colors.onSurface);
      expect(t.fgDim, colors.onSurfaceVariantSummary);
      expect(t.accent, colors.primary);
    });

    test('暗色六个 token 与 Miuix 一致', () {
      const LanFileTokens t = LanFilePalette.dark;
      final colors = MiuixThemeData.of(Brightness.dark).colors;
      expect(t.brightness, Brightness.dark);
      expect(t.bg, colors.surface);
      expect(t.surface, colors.background);
      expect(t.line, colors.dividerLine);
      expect(t.fg, colors.onSurface);
      expect(t.fgDim, colors.onSurfaceVariantSummary);
      expect(t.accent, colors.primary);
    });

    test('of() 按亮度返回对应 token', () {
      expect(
        identical(LanFilePalette.of(Brightness.light), LanFilePalette.light),
        isTrue,
      );
      expect(
        identical(LanFilePalette.of(Brightness.dark), LanFilePalette.dark),
        isTrue,
      );
    });

    test('两套 token 的六个槽位全部互不相同', () {
      const LanFileTokens l = LanFilePalette.light;
      const LanFileTokens d = LanFilePalette.dark;
      expect(l.bg, isNot(d.bg));
      expect(l.surface, isNot(d.surface));
      expect(l.line, isNot(d.line));
      expect(l.fg, isNot(d.fg));
      expect(l.fgDim, isNot(d.fgDim));
      expect(l.accent, isNot(d.accent));
    });

    test('全部 token 落在同一色相带内（单一色相约束）', () {
      // 计划 §7.1 的「中性灰」实测都带极轻微的冷调：明色 220°/223°，
      // 暗色 216°–220°，与主色 217°/219° 属于同一色相带。
      // 这里锁的是「不存在第二个色相」，而不是「灰必须 R=G=B」。
      for (final LanFileTokens t in <LanFileTokens>[
        LanFilePalette.light,
        LanFilePalette.dark,
      ]) {
        final List<Color> greys = <Color>[
          t.bg,
          t.surface,
          t.line,
          t.fg,
          t.fgDim,
        ];
        for (final Color c in greys) {
          if (_isNeutral(c)) continue; // 纯白 surface 无色相
          expect(
            (_hueOf(c) - _hueOf(t.accent)).abs(),
            lessThanOrEqualTo(10),
            reason: '$c 的色相应贴近主色色相，不能引入第二个色相',
          );
          expect(
            _saturationOf(c),
            lessThanOrEqualTo(40.0),
            reason: '$c 应是低饱和的灰阶，不抢主色',
          );
        }
        expect(
          _saturationOf(t.accent),
          greaterThanOrEqualTo(60.0),
          reason: '主色必须是高饱和的唯一强调色',
        );
      }
    });

    test('主色在对应底色上有足够对比度（正文不低于 3:1）', () {
      for (final LanFileTokens t in <LanFileTokens>[
        LanFilePalette.light,
        LanFilePalette.dark,
      ]) {
        expect(
          _contrast(t.fg, t.bg),
          greaterThanOrEqualTo(7.0),
          reason: '正文对底色应达到 AAA',
        );
        expect(
          _contrast(t.fgDim, t.bg),
          greaterThanOrEqualTo(3.0),
          reason: '次级前景对底色至少 AA 大字号',
        );
        expect(
          _contrast(t.accent, t.bg),
          greaterThanOrEqualTo(3.0),
          reason: '主色对底色至少 3:1，保证状态点可辨',
        );
      }
    });
  });

  group('LanFileTokens 扩展行为', () {
    test('copyWith 只改指定槽位', () {
      final LanFileTokens t = LanFilePalette.light.copyWith(
        accent: const Color(0xFF123456),
      );
      expect(t.accent, const Color(0xFF123456));
      expect(t.bg, LanFilePalette.light.bg);
      expect(t.brightness, Brightness.light);
    });

    test('lerp 在 t=0 与 t=1 时取到两端', () {
      const LanFileTokens l = LanFilePalette.light;
      const LanFileTokens d = LanFilePalette.dark;
      expect(l.lerp(d, 0).bg, l.bg);
      expect(l.lerp(d, 1).bg, d.bg);
      expect(l.lerp(null, 0.5).bg, l.bg);
    });

    test('值相等语义可用于 provider 去重', () {
      expect(LanFilePalette.light, equals(LanFilePalette.light.copyWith()));
      expect(
        LanFilePalette.light.hashCode,
        equals(LanFilePalette.light.copyWith().hashCode),
      );
      expect(LanFilePalette.light, isNot(equals(LanFilePalette.dark)));
    });
  });

  group('AppTheme 装配', () {
    test('明暗 ThemeData 都携带 token 扩展', () {
      expect(
        AppTheme.light.extension<LanFileTokens>(),
        equals(LanFilePalette.light),
      );
      expect(
        AppTheme.dark.extension<LanFileTokens>(),
        equals(LanFilePalette.dark),
      );
    });

    test('主题关键槽位全部来自 token', () {
      for (final ThemeData theme in <ThemeData>[
        AppTheme.light,
        AppTheme.dark,
      ]) {
        final LanFileTokens t = theme.extension<LanFileTokens>()!;
        expect(theme.brightness, t.brightness);
        expect(theme.scaffoldBackgroundColor, t.bg);
        expect(theme.colorScheme.primary, t.accent);
        expect(theme.colorScheme.onPrimary, t.onAccent);
        expect(theme.colorScheme.surface, t.surface);
        expect(theme.colorScheme.onSurface, t.fg);
        expect(theme.colorScheme.outline, t.line);
        expect(theme.colorScheme.onSurfaceVariant, t.fgDim);
        expect(theme.dividerColor, t.line);
        expect(theme.appBarTheme.backgroundColor, t.bg);
        expect(theme.inputDecorationTheme.filled, isFalse);
      }
    });

    test('ColorScheme 里不出现第三个色相（error/secondary 也收敛到 token）', () {
      for (final ThemeData theme in <ThemeData>[
        AppTheme.light,
        AppTheme.dark,
      ]) {
        final LanFileTokens t = theme.extension<LanFileTokens>()!;
        final ColorScheme s = theme.colorScheme;
        expect(s.error, t.fg);
        expect(s.secondary, t.fgDim);
        expect(s.tertiary, t.accent);
        // 所有非纯灰槽位必须与主色同色相带（±10°），不允许出现第二色相。
        final int accentHue = _hueOf(s.primary);
        for (final Color c in <Color>[
          s.primary,
          s.secondary,
          s.tertiary,
          s.error,
          s.surface,
          s.onSurface,
          s.outline,
        ]) {
          if (_isNeutral(c)) continue;
          expect(
            (_hueOf(c) - accentHue).abs(),
            lessThanOrEqualTo(10),
            reason: '$c 引入了与主色不同的色相',
          );
        }
      }
    });

    test('of() 接受任意 token 并如实反映', () {
      final LanFileTokens custom = LanFilePalette.light.copyWith(
        accent: const Color(0xFF00FF88),
      );
      final ThemeData theme = AppTheme.of(custom);
      expect(theme.colorScheme.primary, const Color(0xFF00FF88));
      expect(theme.extension<LanFileTokens>(), equals(custom));
    });
  });

  group('AppThemeMode 三态', () {
    test('映射到 ThemeMode 正确', () {
      expect(AppThemeMode.system.themeMode, ThemeMode.system);
      expect(AppThemeMode.light.themeMode, ThemeMode.light);
      expect(AppThemeMode.dark.themeMode, ThemeMode.dark);
    });

    test('storageKey 可往返解析，未知串回落 system', () {
      for (final AppThemeMode m in AppThemeMode.values) {
        expect(AppThemeModeX.parse(m.storageKey), m);
      }
      expect(AppThemeModeX.parse(null), AppThemeMode.system);
      expect(AppThemeModeX.parse(''), AppThemeMode.system);
      expect(AppThemeModeX.parse('sepia'), AppThemeMode.system);
    });

    test('三个状态都有中文标签', () {
      expect(AppThemeMode.system.label, '跟随系统');
      expect(AppThemeMode.light.label, '明色');
      expect(AppThemeMode.dark.label, '暗色');
    });
  });

  group('tokensOf 回落行为', () {
    testWidgets('context 上的扩展缺失时按亮度回落，不抛异常', (WidgetTester tester) async {
      late LanFileTokens resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.light),
          home: Builder(
            builder: (BuildContext context) {
              resolved = tokensOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(resolved, equals(LanFilePalette.light));
    });
  });
}

/// 是否为中性灰（三通道相等）。
bool _isNeutral(Color c) {
  final int r = (c.r * 255).round();
  final int g = (c.g * 255).round();
  final int b = (c.b * 255).round();
  return r == g && g == b;
}

/// 饱和度百分比（HSV 的 S）。
double _saturationOf(Color c) {
  final double max = <double>[
    c.r,
    c.g,
    c.b,
  ].reduce((double a, double v) => a > v ? a : v);
  final double min = <double>[
    c.r,
    c.g,
    c.b,
  ].reduce((double a, double v) => a < v ? a : v);
  if (max == 0) return 0;
  return (max - min) / max * 100;
}

/// 粗略色相（度），只用于判断「是不是同一个色相」。
int _hueOf(Color c) {
  final double r = c.r;
  final double g = c.g;
  final double b = c.b;
  final double max = <double>[
    r,
    g,
    b,
  ].reduce((double a, double v) => a > v ? a : v);
  final double min = <double>[
    r,
    g,
    b,
  ].reduce((double a, double v) => a < v ? a : v);
  final double delta = max - min;
  if (delta == 0) return 0;
  double h;
  if (max == r) {
    h = 60 * (((g - b) / delta) % 6);
  } else if (max == g) {
    h = 60 * ((b - r) / delta + 2);
  } else {
    h = 60 * ((r - g) / delta + 4);
  }
  return ((h.round() % 360) + 360) % 360;
}

/// WCAG 相对亮度与对比度。
double _relativeLuminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : _pow((v + 0.055) / 1.055, 2.4);
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _pow(double base, double exp) {
  // dart:math 的 pow 返回 num，这里包一层以保持强类型。
  double result = 1;
  // 仅用于指数 2.4 的定值计算，直接展开足够精确的场景。
  result = _expApprox(exp * _lnApprox(base));
  return result;
}

double _lnApprox(double x) {
  // 自然对数：通过 atanh 级数，x ∈ (0,1] 时收敛良好。
  // y = (x-1)/(x+1)，ln x = 2 * (y + y³/3 + y⁵/5 + ...)
  final double y = (x - 1) / (x + 1);
  double term = y;
  double sum = 0;
  double y2 = y * y;
  for (int n = 1; n <= 41; n += 2) {
    sum += term / n;
    term *= y2;
  }
  return 2 * sum;
}

double _expApprox(double x) {
  double term = 1;
  double sum = 1;
  for (int n = 1; n <= 60; n++) {
    term *= x / n;
    sum += term;
  }
  return sum;
}

double _contrast(Color a, Color b) {
  final double la = _relativeLuminance(Color.alphaBlend(a, b));
  final double lb = _relativeLuminance(b);
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
