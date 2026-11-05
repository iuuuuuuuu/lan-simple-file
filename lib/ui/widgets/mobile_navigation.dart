// SPDX-License-Identifier: GPL-3.0-only
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../shell/session_rail.dart';
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
    final t = Theme.of(context).extension<LanFileTokens>()!;
    Widget destination(ShellSection section, String label) => Expanded(
      child: InkWell(
        key: ValueKey('mobile-nav-${section.name}'),
        borderRadius: BorderRadius.circular(28),
        onTap: () => onSelect(section),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected == section
                ? t.accent.withValues(alpha: .12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    selected == section ? section.selectedIcon : section.icon,
                    size: 22,
                    color: selected == section ? t.accent : t.fgDim,
                  ),
                  if (section == ShellSection.nearby && unread > 0)
                    Positioned(
                      right: -15,
                      top: -7,
                      child: UnreadPill(
                        key: const ValueKey('mobile-chat-unread'),
                        count: unread,
                        compact: true,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: selected == section ? t.accent : t.fgDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(36),
          boxShadow: [
            BoxShadow(
              color: t.fg.withValues(alpha: .09),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(36),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              key: const ValueKey('mobile-navigation'),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: t.surface.withValues(alpha: .86),
                borderRadius: BorderRadius.circular(36),
                border: Border.all(color: t.line.withValues(alpha: .7)),
              ),
              child: Row(
                children: [
                  destination(ShellSection.nearby, '聊天'),
                  destination(ShellSection.shares, '分享'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: IconButton.filled(
                      key: const ValueKey('mobile-upload'),
                      tooltip: '上传文件',
                      onPressed: uploading ? null : onUpload,
                      style: IconButton.styleFrom(
                        backgroundColor: t.accent,
                        foregroundColor: t.onAccent,
                        minimumSize: const Size(48, 48),
                      ),
                      icon: uploading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_rounded, size: 28),
                    ),
                  ),
                  destination(ShellSection.transfers, '传输'),
                  destination(ShellSection.settings, '设置'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
