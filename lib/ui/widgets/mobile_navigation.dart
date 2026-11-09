// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';

import '../shell/session_rail.dart';
import 'app_controls.dart';
import 'avatar_badge.dart' show UnreadPill;

class MobileNavigation extends StatelessWidget {
  const MobileNavigation({
    super.key,
    required this.selected,
    required this.onSelect,
    this.unread = 0,
  });
  final ShellSection selected;
  final ValueChanged<ShellSection> onSelect;
  final int unread;

  @override
  Widget build(BuildContext context) {
    Widget destination(ShellSection section, String label) => AppTooltip(
      message: label,
      child: MiuixFloatingNavigationBarItem(
        key: ValueKey('mobile-nav-${section.name}'),
        selected: selected == section,
        onPressed: () => onSelect(section),
        icon: Stack(
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
                    key: const ValueKey('mobile-chat-unread'),
                    count: unread,
                    compact: true,
                  ),
                ),
              ),
          ],
        ),
        label: section == ShellSection.nearby && unread > 0
            ? '$label，$unread 条未读'
            : label,
      ),
    );
    return SizedBox(
      height: 88 + MediaQuery.viewPaddingOf(context).bottom,
      child: MiuixFloatingNavigationBar(
        key: const ValueKey('mobile-navigation'),
        children: [
          destination(ShellSection.nearby, '聊天'),
          destination(ShellSection.shares, '分享'),
          destination(ShellSection.transfers, '传输记录'),
          destination(ShellSection.settings, '设置'),
        ],
      ),
    );
  }
}
