// SPDX-License-Identifier: GPL-3.0-only

/// 最窄图标栏（QQ 桌面端左侧那条）：顶部本机头像，中间导航图标，底部设置齿轮。
///
/// 宽度固定在 [kRailWidth]（56–64px 区间），窄屏也保留——
/// 它是「我是谁 + 去哪」的常驻入口，收起会让用户失去身份感。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../widgets/avatar_badge.dart';
import 'design.dart';

/// 最窄栏宽度（取自 tokens，落在 56–64px 区间）。
const double kRailWidth = LanFileMetrics.railWidth;

/// 一级导航目的地。
enum ShellSection {
  /// 附近的人（会话）。
  nearby('附近的人', Icons.chat_bubble_outline, Icons.chat_bubble),

  /// 群聊。
  groups('群聊', Icons.groups_outlined, Icons.groups),

  /// 我的分享。
  shares('我的分享', Icons.folder_outlined, Icons.folder),

  /// 传输。
  transfers('传输', Icons.swap_vert_circle_outlined, Icons.swap_vert_circle),

  /// 设置。
  settings('设置', Icons.settings_outlined, Icons.settings);

  const ShellSection(this.label, this.icon, this.selectedIcon);

  /// 中文文案。
  final String label;

  /// 未选中图标。
  final IconData icon;

  /// 选中图标。
  final IconData selectedIcon;
}

/// 最窄图标栏。
class SessionRail extends StatelessWidget {
  /// [selfPeerId] 用于生成本机头像；[onOpenSettings] 由点击头像/齿轮触发。
  const SessionRail({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.selfPeerId,
    required this.onOpenSettings,
    this.selfName,
    this.selfBadgeUnread = 0,
    this.avatarBytes,
    this.sections = const [ShellSection.nearby, ShellSection.shares, ShellSection.transfers],
  });

  /// 本机昵称；显示在头像下方（QQ 那种「头像压名字」）。
  final String? selfName;
  final Uint8List? avatarBytes;
  final List<ShellSection> sections;

  /// 当前选中的目的地。
  final ShellSection selected;

  /// 切换目的地。
  final ValueChanged<ShellSection> onSelect;

  /// 本机 peerId（派生 identicon）。
  final String selfPeerId;

  /// 进入设置（头像与齿轮都走这里）。
  final VoidCallback onOpenSettings;

  /// 本机头像上的未读提示（例如待处理的 offer）。
  final int selfBadgeUnread;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;

    return Container(
      key: const ValueKey<String>('shell-rail'),
      width: kRailWidth,
      // 最"远"的一层：用页面底色，与列表的 surfaceSunken 形成明度差。
      color: surfaceOf(tokens, SurfaceTier.rail),
      child: Column(
        children: <Widget>[
          const SizedBox(height: 12),
          // 顶部：本机头像 + 昵称，点击进设置。
          //
          // 头像必须够大（40px）：36px 在 1280 宽的窗口里会被看成普通图标，
          // 失去「这是我的身份」的辨识度。昵称用 10px 显示在下方，
          // 这是 QQ 那种「头像压着名字」的观感来源。
          Tooltip(
            message: selfName == null || selfName!.isEmpty
                ? '本机 · 打开设置'
                : '${selfName!} · 打开设置',
            child: InkWell(
              key: const ValueKey<String>('rail-self-avatar'),
              onTap: onOpenSettings,
              borderRadius: BorderRadius.circular(kAvatarRadius),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    AvatarBadge(
                      peerId: selfPeerId,
                      avatarBytes: avatarBytes,
                      size: 40,
                      showStatus: true,
                      unread: selfBadgeUnread,
                    ),
                    if (selfName != null && selfName!.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      SizedBox(
                        width: kRailWidth - 8,
                        child: Text(
                          selfName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 9.5,
                            height: 1.1,
                            color: tokens.fgDim,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Divider(height: 1, indent: 14, endIndent: 14, color: tokens.line),
          const SizedBox(height: 8),
          // 中部：导航图标。
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: <Widget>[
                for (final ShellSection section in sections)
                  if (section != ShellSection.settings)
                    _RailButton(
                      section: section,
                      selected: section == selected,
                      onTap: () => onSelect(section),
                    ),
              ],
            ),
          ),
          // 底部：设置齿轮。
          Divider(height: 1, indent: 14, endIndent: 14, color: tokens.line),
          const SizedBox(height: 6),
          _RailButton(
            section: ShellSection.settings,
            selected: selected == ShellSection.settings,
            onTap: onOpenSettings,
            buttonKey: const ValueKey<String>('rail-settings'),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

/// 一个导航图标按钮：选中时 accent 图标 + 主色半透明底。
class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.section,
    required this.selected,
    required this.onTap,
    this.buttonKey,
  });

  final ShellSection section;
  final bool selected;
  final VoidCallback onTap;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
      child: Tooltip(
        message: section.label,
        child: Material(
          color: selected ? tokens.accentSoft : null,
          borderRadius: BorderRadius.circular(LanFileMetrics.radiusRow),
          child: InkWell(
            key: buttonKey ?? ValueKey<String>('rail-${section.name}'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(LanFileMetrics.radiusRow),
            child: SizedBox(
              height: 40,
              child: Icon(
                selected ? section.selectedIcon : section.icon,
                size: 22,
                color: selected ? tokens.accent : tokens.fgDim,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
