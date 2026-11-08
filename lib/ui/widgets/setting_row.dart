// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';

import 'app_controls.dart';

class SettingGroup extends StatelessWidget {
  const SettingGroup({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      MiuixSmallTitle(title),
      for (var i = 0; i < children.length; i++) ...[
        children[i],
        if (i < children.length - 1) const MiuixHorizontalDivider(),
      ],
    ],
  );
}

class SettingRow extends StatelessWidget {
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
  final String label;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Widget? leading;
  final bool dense;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => MiuixBasicComponent(
    title: label,
    summary: dense ? null : subtitle,
    startAction: leading,
    onClick: onTap,
    holdDownState: highlighted,
    insideMargin: EdgeInsets.symmetric(
      horizontal: 16,
      vertical: dense ? 8 : 14,
    ),
    endActions: trailing != null
        ? [Flexible(child: trailing!)]
        : value != null
        ? [
            Flexible(
              child: SettingValue(text: value!, dense: dense),
            ),
          ]
        : null,
  );
}

class SettingValue extends StatelessWidget {
  const SettingValue({super.key, required this.text, this.dense = false});
  final String text;
  final bool dense;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 220),
    child: Text(
      text,
      textAlign: TextAlign.right,
      maxLines: dense ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        color: MiuixTheme.of(context).colors.onSurfaceVariantSummary,
      ),
    ),
  );
}
