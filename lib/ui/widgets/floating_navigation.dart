// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';

import '../shell/session_rail.dart';
import 'app_controls.dart';
import 'avatar_badge.dart' show UnreadPill;

/// Only scroll tails and fixed controls avoid the floating bar; page backgrounds
/// and scroll viewports continue behind it.
class FloatingNavigationInsets extends InheritedWidget {
  const FloatingNavigationInsets({
    super.key,
    required this.bottom,
    required super.child,
  });

  final double bottom;

  static double bottomOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<FloatingNavigationInsets>()
          ?.bottom ??
      0;

  @override
  bool updateShouldNotify(FloatingNavigationInsets oldWidget) =>
      bottom != oldWidget.bottom;
}

class FloatingNavigation extends StatelessWidget {
  const FloatingNavigation({
    super.key,
    required this.selected,
    required this.onSelect,
    this.unread = 0,
    this.backdrop,
  });
  final ShellSection selected;
  final ValueChanged<ShellSection> onSelect;
  final int unread;
  final MiuixBackdrop? backdrop;

  static const barHeight = 56.0;
  static const bottomGap = 12.0;
  static double clearance(BuildContext context) =>
      barHeight + bottomGap + MediaQuery.viewPaddingOf(context).bottom;

  static const _sections = [
    ShellSection.nearby,
    ShellSection.shares,
    ShellSection.transfers,
    ShellSection.settings,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    MiuixGlassNavigationItem destination(ShellSection section, String label) =>
        MiuixGlassNavigationItem(
          contentDescription: section == ShellSection.nearby && unread > 0
              ? '$label，$unread 条未读'
              : label,
          icon: AppTooltip(
            message: label,
            child: Stack(
              key: ValueKey('nav-${section.name}'),
              clipBehavior: Clip.none,
              children: [
                Icon(selected == section ? section.selectedIcon : section.icon),
                if (section == ShellSection.nearby && unread > 0)
                  Positioned(
                    right: -12,
                    top: -8,
                    child: DefaultTextStyle.merge(
                      style: const TextStyle(fontSize: 11, height: 1.2),
                      child: UnreadPill(
                        key: const ValueKey('chat-unread'),
                        count: unread,
                        compact: true,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        bottomGap + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Center(
        heightFactor: 1,
        child: SizedBox(
          width: 296,
          child: MiuixGlassNavigationBar(
            key: const ValueKey('app-navigation'),
            backdrop: backdrop,
            height: barHeight,
            selectedIndex: _sections.indexOf(selected).clamp(0, 3),
            onSelect: (index) => onSelect(_sections[index]),
            selectedColor: colors.primary,
            unselectedColor: colors.onSurfaceVariantSummary,
            indicatorColor: colors.primary.withValues(alpha: .12),
            indicatorPressedColor: colors.primary.withValues(alpha: .20),
            items: [
              destination(ShellSection.nearby, '聊天'),
              destination(ShellSection.shares, '分享'),
              destination(ShellSection.transfers, '传输记录'),
              destination(ShellSection.settings, '设置'),
            ],
          ),
        ),
      ),
    );
  }
}
