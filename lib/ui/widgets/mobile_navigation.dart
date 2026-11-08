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
    required this.onUpload,
    this.uploading = false,
    this.unread = 0,
  });
  final ShellSection selected;
  final ValueChanged<ShellSection> onSelect;
  final VoidCallback onUpload;
  final bool uploading;
  final int unread;

  @override
  Widget build(BuildContext context) {
    Widget destination(ShellSection section, String label) =>
        MiuixNavigationBarItem(
          key: ValueKey('mobile-nav-${section.name}'),
          selected: selected == section,
          onPressed: () => onSelect(section),
          icon: Icon(selected == section ? section.selectedIcon : section.icon),
          label: label,
          badge: section == ShellSection.nearby && unread > 0
              ? UnreadPill(
                  key: const ValueKey('mobile-chat-unread'),
                  count: unread,
                  compact: true,
                )
              : null,
        );
    return MiuixNavigationBar(
      key: const ValueKey('mobile-navigation'),
      children: [
        destination(ShellSection.nearby, '聊天'),
        destination(ShellSection.shares, '分享'),
        Center(
          child: AppIconButton(
            key: const ValueKey('mobile-upload'),
            tooltip: '上传文件',
            selected: true,
            onPressed: uploading ? null : onUpload,
            icon: SizedBox.square(
              dimension: 28,
              child: uploading
                  ? const MiuixCircularProgressIndicator()
                  : const Icon(Icons.add_rounded, size: 28),
            ),
          ),
        ),
        destination(ShellSection.transfers, '传输'),
        destination(ShellSection.settings, '设置'),
      ],
    );
  }
}
