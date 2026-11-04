// SPDX-License-Identifier: GPL-3.0-only

/// QQ 风格设置页的原子组件：分组卡片 + 设置行（三态 hover）。
///
/// 只从 [LanFileTokens] 与 [LanFileTokensLayers] 取色，不新增色相；
/// 层次靠**背景分级 + 圆角 + hairline 描边**表达，与 QQ / 微信设置页一致。
/// 所有尺寸取自 [LanFileMetrics]，本文件不写魔数。
library;

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';

/// 一个 QQ 风格的分组卡片：小号灰字组标题 + 浅色圆角卡片。
class SettingGroup extends StatelessWidget {
  /// [title] 是组标题（小号灰字）；[children] 通常是一组 [SettingRow]。
  const SettingGroup({
    super.key,
    required this.title,
    required this.children,
  });

  /// 组标题。
  final String title;

  /// 组内容。
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens =
        Theme.of(context).extension<LanFileTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(
            left: LanFileMetrics.rowPaddingH,
            bottom: 6,
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: tokens.fgDim,
            ),
          ),
        ),
        // 卡片本身用 surface，坐在 bg 上；暗色下靠 cardLine 描边分层。
        Container(
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(LanFileMetrics.radiusCard),
            border: Border.all(
              color: tokens.cardLine,
              width: LanFileMetrics.hairline,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < children.length; i++) ...<Widget>[
                children[i],
                if (i != children.length - 1)
                  // 分隔线缩进：QQ 设置页的线不顶到左右边缘。
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LanFileMetrics.rowPaddingH,
                    ),
                    child: Divider(
                      height: LanFileMetrics.hairline,
                      thickness: LanFileMetrics.hairline,
                      color: tokens.cardLine,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 一行设置：左侧标签（可带副标题），右侧为值 / 控件。
///
/// 三态：普通（透明）/ hover（hoverSoft）/ 有 onTap 且被按下时仍是 hoverSoft，
/// 选中态留给列表类组件（设置行没有选中概念，故不强行造）。
/// 不可点的行不显示 hover，避免「看起来能点其实不能」。
class SettingRow extends StatefulWidget {
  /// 常规构造。
  const SettingRow({
    super.key,
    required this.label,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.leading,
    this.dense = false,
    this.highlighted = false,
  });

  /// 左侧主文案。
  final String label;

  /// 主文案下方的小字说明。
  final String? subtitle;

  /// 右侧的值文本（与 [trailing] 二选一，优先 [trailing]）。
  final String? value;

  /// 右侧任意控件（开关、按钮）。
  final Widget? trailing;

  /// 整行点击。
  final VoidCallback? onTap;

  /// 左侧图标。
  final Widget? leading;

  /// 紧凑模式：省略副标题、行高降低，用于「最近丢弃原因」这类列表。
  final bool dense;

  /// 强调态：用 accentSoft 底 + accent 文字（当前会话那种观感）。
  final bool highlighted;

  @override
  State<SettingRow> createState() => _SettingRowState();
}

class _SettingRowState extends State<SettingRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens =
        Theme.of(context).extension<LanFileTokens>()!;
    final bool interactive = widget.onTap != null;
    final bool highlight = interactive && _hovered;

    final Color? background = widget.highlighted
        ? tokens.accentSoft
        : highlight
            ? tokens.hoverSoft
            : null;
    final Color labelColor =
        widget.highlighted ? tokens.accent : (widget.dense ? tokens.fgDim : tokens.fg);

    final Widget content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: LanFileMetrics.rowPaddingH,
        vertical: widget.dense ? 5 : LanFileMetrics.rowPaddingV,
      ),
      child: Row(
        children: <Widget>[
          if (widget.leading != null) ...<Widget>[
            widget.leading!,
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  widget.label,
                  maxLines: widget.dense ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: widget.dense ? 12 : 13,
                    height: 1.35,
                    fontWeight: widget.highlighted
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: labelColor,
                  ),
                ),
                if (!widget.dense &&
                    widget.subtitle != null &&
                    widget.subtitle!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: tokens.fgDim,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (widget.trailing != null)
            widget.trailing!
          else if (widget.value != null)
            SettingValue(text: widget.value!, dense: widget.dense),
        ],
      ),
    );

    final Widget row = AnimatedContainer(
      duration: const Duration(milliseconds: 110),
      constraints: const BoxConstraints(
        minHeight: LanFileMetrics.sessionRowHeight - 20,
      ),
      color: background,
      child: content,
    );

    if (!interactive) {
      return row;
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: row,
      ),
    );
  }
}

/// 设置行右侧的值文本（灰色，过长截断）。
class SettingValue extends StatelessWidget {
  /// [text] 为展示内容；过长时截断。
  const SettingValue({super.key, required this.text, this.dense = false});

  /// 值文本。
  final String text;

  /// 紧凑模式。
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens =
        Theme.of(context).extension<LanFileTokens>()!;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Text(
        text,
        textAlign: TextAlign.right,
        maxLines: dense ? 1 : 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: dense ? 12 : 12.5,
          color: tokens.fgDim,
        ),
      ),
    );
  }
}
