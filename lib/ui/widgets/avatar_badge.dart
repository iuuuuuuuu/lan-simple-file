// SPDX-License-Identifier: GPL-3.0-only

/// 圆角头像 + 在线状态点 + 未读红点：会话列表与最窄栏共用的头像组件。
///
/// 层次靠 token 分级与圆角实现（10px 头像容器 / 8px 行），
/// 不引入第二色相：未读点、状态点都只用 accent。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../app/widgets/identicon.dart';

/// 头像容器圆角（取自 tokens 的 radiusCard，不再是本地魔数）。
const double kAvatarRadius = LanFileMetrics.radiusCard;

/// QQ 风格头像：identicon 打底，右下角状态点，右上角未读徽标。
class AvatarBadge extends StatelessWidget {
  /// [peerId] 用于生成稳定 identicon；[size] 为头像边长。
  const AvatarBadge({
    super.key,
    required this.peerId,
    this.size = LanFileMetrics.avatarList,
    this.showStatus = true,
    this.online = true,
    this.unread = 0,
    this.selected = false,
    this.avatarBytes,
  });

  /// 生成 identicon 用的稳定标识（peerId 或 groupId）。
  final String peerId;
  final Uint8List? avatarBytes;

  /// 头像直径。
  final double size;

  /// 是否显示右下角在线状态点。
  final bool showStatus;

  /// 在线与否；决定状态点实心/空心。
  final bool online;

  /// 未读数；<=0 时不显示红点。
  final int unread;

  /// 选中态：加一圈 accent 描边（QQ 里选中会话的常见反馈）。
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    // 状态点用 tokens 的标准直径，但不超过头像的 1/3（小头像时不至于糊成一团）。
    final double badgeSize = size < LanFileMetrics.avatarList
        ? size * 0.28
        : LanFileMetrics.statusDot;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          // 选中描边：用 padding + 外层装饰实现，不改 identicon 本身的圆角。
          Container(
            width: size,
            height: size,
            padding: EdgeInsets.all(selected ? 1.5 : 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kAvatarRadius),
              border: selected
                  ? Border.all(color: tokens.accent, width: 1.5)
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                selected ? kAvatarRadius - 1.5 : kAvatarRadius,
              ),
              child: PeerAvatar(
                peerId: peerId,
                avatarBytes: avatarBytes,
                size: size,
                radius: 0,
              ),
            ),
          ),
          if (showStatus)
            Positioned(
              right: -2,
              bottom: 0,
              child: _StatusDot(online: online, size: badgeSize),
            ),
          if (unread > 0)
            Positioned(right: -5, top: -2, child: UnreadPill(count: unread)),
        ],
      ),
    );
  }
}

/// 右下角状态点：在线 accent 实心，离线 accent 空心（与 PeerStatusDot 同语义）。
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.online, required this.size});

  final bool online;
  final double size;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: online ? tokens.accent : tokens.surface,
        border: Border.all(
          color: online ? tokens.accent : tokens.fgDim,
          width: 1.2,
        ),
      ),
    );
  }
}

/// 未读红点：accent 实心圆角药丸，>99 显示 99+。
///
/// 双色约束下没有红色可用，因此用主色实心 + 反差文字表达「有新消息」。
class UnreadPill extends StatelessWidget {
  /// 未读条数。
  const UnreadPill({super.key, required this.count, this.compact = false});

  /// 未读数量。
  final int count;

  /// 紧凑模式（只有数字、更小内边距），用于列表行。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(minWidth: 16),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 7,
        vertical: compact ? 1 : 2,
      ),
      decoration: BoxDecoration(
        color: tokens.accent,
        borderRadius: BorderRadius.circular(LanFileMetrics.radiusPill),
        // 与头像重叠时需要的分隔感：用页面底色描边而不是再加颜色。
        border: Border.all(color: tokens.bg, width: 1.5),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: compact ? 10 : 11,
          height: 1.26,
          fontWeight: FontWeight.w600,
          color: tokens.onAccent,
        ),
      ),
    );
  }
}
