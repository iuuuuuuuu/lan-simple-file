// SPDX-License-Identifier: GPL-3.0-only

/// 设计语言的**用法层**：把 LanFileMetrics 与 LanFileTokensLayers 组合成
/// 可直接套在 Widget 上的样式（装饰、文字层级、三态反馈）。
///
/// 分工：
/// - lib/app/theme/tokens.dart 定义「是什么」（尺寸常量 + 分层色）；
/// - 本文件定义「怎么用」（哪些场景取哪一档、组合成什么 BoxDecoration/TextStyle）。
///
/// 三条硬规则：
/// 1. **不新增色相**：所有层次都由 tokens 的分层色派生；
/// 2. **暗色靠描边、明色靠shadow**：暗底吞阴影，改用 cardLine 定形；
/// 3. **圆角/密度只从 LanFileMetrics 取**，不在业务代码里写魔数。
library;

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';

// ------------------------------------------------------------ 背景层级

/// 三块背景的语义位置，对应「近-中-远」。
enum SurfaceTier {
  /// 最远：图标栏。用页面底色。
  rail,

  /// 中间：会话列表栏。用 surfaceSunken（比内容区更深一层）。
  list,

  /// 最近：内容区底色。
  content,

  /// 抬起：卡片。用 surface。
  card,
}

/// 取分层底色。
Color surfaceOf(LanFileTokens t, SurfaceTier tier) => switch (tier) {
  SurfaceTier.rail => t.bg,
  SurfaceTier.list => t.surfaceSunken,
  SurfaceTier.content => t.bg,
  SurfaceTier.card => t.surface,
};

// -------------------------------------------------------------- 卡片

/// 卡片装饰：hairline 描边定形 + 明色极轻阴影。
///
/// 阴影只在明色加：暗色下黑影会被背景吞掉，反而让卡片边缘发脏；
/// 暗色改用 cardLine 描边（tokens 里已按亮度调过强度）。
BoxDecoration cardDecoration(LanFileTokens t) => BoxDecoration(
  color: t.surface,
  borderRadius: BorderRadius.circular(LanFileMetrics.radiusCard),
  border: Border.all(color: t.cardLine, width: LanFileMetrics.hairline),
  boxShadow: t.isDark
      ? null
      : <BoxShadow>[
          // 只做「贴纸浮起 1mm」的暗示，多了会变廉价投影堆叠。
          BoxShadow(
            color: t.shadowColor,
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
);

/// 浮层（遮罩内的提示框）装饰。
BoxDecoration overlayDecoration(LanFileTokens t) => BoxDecoration(
  color: t.surface,
  borderRadius: BorderRadius.circular(LanFileMetrics.radiusPanel),
  border: Border.all(color: t.accent, width: 1.5),
  boxShadow: <BoxShadow>[
    BoxShadow(color: t.shadowColor, blurRadius: 18, offset: const Offset(0, 6)),
  ],
);

// -------------------------------------------------------- 行三态反馈

/// 列表行的三种交互态。
enum RowState { idle, hovered, selected, pressed }

/// 由悬停/选中/按下算出唯一状态（优先级：按下 > 选中 > 悬停）。
RowState resolveRowState({
  required bool hovered,
  required bool selected,
  required bool pressed,
}) {
  if (pressed) return RowState.pressed;
  if (selected) return RowState.selected;
  if (hovered) return RowState.hovered;
  return RowState.idle;
}

/// 行装饰：三态共用同一个圆角，只换底色，切换时不抖动。
BoxDecoration rowDecoration(LanFileTokens t, RowState state) {
  final Color? fill = switch (state) {
    RowState.idle => null,
    RowState.hovered => t.hoverSoft,
    RowState.selected => t.accentSoft,
    RowState.pressed => Color.alphaBlend(
      t.accent.withValues(alpha: 0.16),
      t.surface,
    ),
  };
  return BoxDecoration(
    color: fill,
    borderRadius: BorderRadius.circular(LanFileMetrics.radiusRow),
    // 选中时加一圈极淡主色描边，让「当前会话」在密集列表里也一眼看到。
    border: state == RowState.selected
        ? Border.all(color: t.accent.withValues(alpha: 0.40), width: 1)
        : null,
  );
}

/// 行内前景色：选中时主要文字用主色，其余用常规前景。
Color rowTitleColor(LanFileTokens t, RowState state) =>
    state == RowState.selected ? t.accent : t.fg;

// ------------------------------------------------------------ 文字层级

/// 名字：中字重 + 主前景。中文加一点字距让层级更清楚。
TextStyle nameStyle(LanFileTokens t, {bool selected = false}) => TextStyle(
  fontSize: 13.5,
  fontWeight: FontWeight.w500,
  height: 1.25,
  letterSpacing: 0,
  color: selected ? t.accent : t.fg,
);

/// 摘要：更小字号 + 次级前景。
TextStyle subtitleStyle(LanFileTokens t) => TextStyle(
  fontSize: 11.5,
  fontWeight: FontWeight.w400,
  height: 1.3,
  letterSpacing: 0,
  color: t.fgDim,
);

/// 时间：最小号；靠字号弱化，不引入新颜色。
TextStyle timeStyle(LanFileTokens t) => TextStyle(
  fontSize: 10,
  fontWeight: FontWeight.w400,
  height: 1.2,
  color: Color.alphaBlend(const Color(0x22000000), t.fgDim),
);

/// 栏标题。
TextStyle sectionTitleStyle(LanFileTokens t) => TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w500,
  letterSpacing: 0,
  color: t.fg,
);

/// 空态标题。
TextStyle emptyTitleStyle(LanFileTokens t) =>
    TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: t.fg);

/// 空态说明。
TextStyle emptyBodyStyle(LanFileTokens t) =>
    TextStyle(fontSize: 11.5, height: 1.65, color: t.fgDim);
