// SPDX-License-Identifier: GPL-3.0-only

/// 双色主题 token：一个主色 + 一套中性灰阶，明暗各一份（docs/plan.md §7.1）。
///
/// 组件取色一律走本文件或 Theme 扩展，不在 UI 里写死颜色。
library;

import 'package:flutter/material.dart';

/// 一套主题的全部颜色。
///
/// 只有六个基础 token：背景、载体面、分隔线、前景、次级前景、主色。
/// 在线/离线/失败一律靠形状与透明度表达，不新增色相。
final class LanFileTokens extends ThemeExtension<LanFileTokens> {
  const LanFileTokens({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.line,
    required this.fg,
    required this.fgDim,
    required this.accent,
  });

  /// 这套 token 服务明色还是暗色。
  final Brightness brightness;

  /// 页面底色。
  final Color bg;

  /// 卡片 / 栏底色。
  final Color surface;

  /// 分隔线与描边。
  final Color line;

  /// 主前景（正文、标题）。
  final Color fg;

  /// 次级前景（说明、辅助信息）。
  final Color fgDim;

  /// 唯一主色；不允许出现第二个色相。
  final Color accent;

  /// 主色之上应当使用的文字色。
  Color get onAccent => isDark ? bg : surface;

  /// 是否暗色主题。
  bool get isDark => brightness == Brightness.dark;

  @override
  LanFileTokens copyWith({
    Brightness? brightness,
    Color? bg,
    Color? surface,
    Color? line,
    Color? fg,
    Color? fgDim,
    Color? accent,
  }) {
    return LanFileTokens(
      brightness: brightness ?? this.brightness,
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      line: line ?? this.line,
      fg: fg ?? this.fg,
      fgDim: fgDim ?? this.fgDim,
      accent: accent ?? this.accent,
    );
  }

  @override
  LanFileTokens lerp(covariant LanFileTokens? other, double t) {
    if (other == null) return this;
    return LanFileTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      line: Color.lerp(line, other.line, t)!,
      fg: Color.lerp(fg, other.fg, t)!,
      fgDim: Color.lerp(fgDim, other.fgDim, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LanFileTokens &&
      other.brightness == brightness &&
      other.bg == bg &&
      other.surface == surface &&
      other.line == line &&
      other.fg == fg &&
      other.fgDim == fgDim &&
      other.accent == accent;

  @override
  int get hashCode => Object.hash(
        brightness,
        bg,
        surface,
        line,
        fg,
        fgDim,
        accent,
      );
}

/// 明暗两套 token 的常量入口。
///
/// 色值逐字对应 docs/plan.md §7.1，改动必须同步决策笔记
/// .agents/notes/implemented/feature/2026-11-04-dual-tone-theme-and-identicon.md。
abstract final class LanFilePalette {
  /// 明色主题。
  static const LanFileTokens light = LanFileTokens(
    brightness: Brightness.light,
    bg: Color(0xFFF7F8FA),
    surface: Color(0xFFFFFFFF),
    line: Color(0xFFE5E7EB),
    fg: Color(0xFF16181D),
    fgDim: Color(0xFF6B7280),
    accent: Color(0xFF3B82F6),
  );

  /// 暗色主题。
  static const LanFileTokens dark = LanFileTokens(
    brightness: Brightness.dark,
    bg: Color(0xFF0E1116),
    surface: Color(0xFF161A21),
    line: Color(0xFF242A33),
    fg: Color(0xFFE6E9EF),
    fgDim: Color(0xFF8B94A3),
    accent: Color(0xFF4F8DFD),
  );

  /// 按亮度取对应 token。
  static LanFileTokens of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}
/// 视觉层次的尺寸与描边体系。
///
/// 存在的理由：只有 6 个颜色 token 时，界面会退化成「所有区域一个底色」的系统设置感。
/// QQ / 微信那种质感不是靠更多颜色，而是靠**背景分级 + 圆角 + 极轻描边 + 紧凑密度**。
/// 这里把这几件事做成常量，避免各页面各写一套魔数。
abstract final class LanFileMetrics {
  const LanFileMetrics._();

  // ---- 圆角 ----
  /// 列表行 / 小控件。
  static const double radiusRow = 8;

  /// 卡片 / 头像容器。
  static const double radiusCard = 10;

  /// 弹层 / 面板。
  static const double radiusPanel = 14;

  /// 胶囊（徽标、标签）。
  static const double radiusPill = 999;

  // ---- 密度 ----
  /// 会话列表行高（QQ 那种紧凑但不挤）。
  static const double sessionRowHeight = 64;

  /// 列表行水平内边距。
  static const double rowPaddingH = 12;

  /// 列表行垂直内边距。
  static const double rowPaddingV = 8;

  /// 窄图标栏宽度。
  static const double railWidth = 60;

  /// 会话列表栏宽度。
  static const double sessionListWidth = 272;

  /// 三栏布局生效的最小宽度。
  static const double threeColumnMinWidth = 1000;

  // ---- 头像 ----
  /// 会话列表里的头像边长。
  static const double avatarList = 42;

  /// 标题栏 / 资料卡里的大头像。
  static const double avatarLarge = 56;

  /// 在线状态点直径。
  static const double statusDot = 10;

  // ---- 层级 ----
  /// 卡片描边宽度。明色下用极轻描边代替阴影，暗色下描边本身就是主要层次手段。
  static const double hairline = 1;
}

/// 背景分级。
///
/// 同一套主题下，用**明度差**把界面分成三层，而不是新增色相：
/// 最底层是 `bg`（内容区），中栏用 `surface`，选中的行用 `accentSoft`。
/// 这正是 QQ 那种「一块压一块」的层次来源。
extension LanFileTokensLayers on LanFileTokens {
  /// 二级背景：会话列表栏、侧栏这类「比内容区更靠后」的载体。
  Color get surfaceSunken => isDark
      ? Color.alphaBlend(const Color(0x0DFFFFFF), bg)
      : Color.alphaBlend(const Color(0x04000000), bg);

  /// 主色系的极淡底：选中的行、当前会话、hover 的高亮。
  Color get accentSoft => Color.alphaBlend(accent.withValues(alpha: 0.10), surface);

  /// hover 底色：比选中更淡，但可见。
  Color get hoverSoft => isDark
      ? Color.alphaBlend(const Color(0x0AFFFFFF), surface)
      : Color.alphaBlend(const Color(0x06000000), surface);

  /// 卡片描边：明色下几乎不可见但能定形，暗色下作为主要层次。
  Color get cardLine => isDark
      ? Color.alphaBlend(const Color(0x14FFFFFF), line)
      : line;

  /// 浮层阴影色（暗色下用更强的不透明度，因为暗背景吞阴影）。
  Color get shadowColor => isDark
      ? const Color(0x66000000)
      : const Color(0x14000000);
}