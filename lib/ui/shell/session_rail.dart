// SPDX-License-Identifier: GPL-3.0-only
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../widgets/app_controls.dart';
import '../widgets/avatar_badge.dart';

const double kRailWidth = LanFileMetrics.railWidth;

enum ShellSection {
  nearby('附近的人', Icons.chat_bubble_outline, Icons.chat_bubble),
  groups('群聊', Icons.groups_outlined, Icons.groups),
  shares('我的分享', Icons.folder_outlined, Icons.folder),
  transfers('传输', Icons.swap_vert_circle_outlined, Icons.swap_vert_circle),
  settings('设置', Icons.settings_outlined, Icons.settings);

  const ShellSection(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class SessionRail extends StatelessWidget {
  const SessionRail({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.selfPeerId,
    required this.onOpenSettings,
    this.selfName,
    this.selfBadgeUnread = 0,
    this.avatarBytes,
    this.sections = const [
      ShellSection.nearby,
      ShellSection.shares,
      ShellSection.transfers,
    ],
    this.chatUnread = 0,
  });
  final ShellSection selected;
  final ValueChanged<ShellSection> onSelect;
  final String selfPeerId;
  final VoidCallback onOpenSettings;
  final String? selfName;
  final int selfBadgeUnread;
  final Uint8List? avatarBytes;
  final List<ShellSection> sections;
  final int chatUnread;

  @override
  Widget build(BuildContext context) => MiuixNavigationRail(
    key: const ValueKey('shell-rail'),
    minWidth: kRailWidth,
    showDivider: false,
    defaultWindowInsetsPadding: false,
    labelFontSize: 10,
    header: AppTooltip(
      message: '${selfName ?? '本机'} · 打开设置',
      child: MiuixPressable(
        key: const ValueKey('rail-self-avatar'),
        onPressed: onOpenSettings,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AvatarBadge(
                peerId: selfPeerId,
                avatarBytes: avatarBytes,
                size: 40,
                showStatus: true,
                unread: selfBadgeUnread,
              ),
              if (selfName?.isNotEmpty == true) ...[
                const SizedBox(height: 6),
                SizedBox(
                  width: kRailWidth - 8,
                  child: Text(
                    selfName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    children: [
      for (final section in [
        ...sections.where((s) => s != ShellSection.settings),
        ShellSection.settings,
      ])
        MiuixNavigationRailItem(
          key: ValueKey('rail-${section.name}'),
          selected: section == selected,
          onPressed: section == ShellSection.settings
              ? onOpenSettings
              : () => onSelect(section),
          icon: Icon(section == selected ? section.selectedIcon : section.icon),
          label: section.label,
          badge: section == ShellSection.nearby && chatUnread > 0
              ? UnreadPill(
                  key: const ValueKey('desktop-chat-unread'),
                  count: chatUnread,
                  compact: true,
                )
              : null,
        ),
    ],
  );
}
