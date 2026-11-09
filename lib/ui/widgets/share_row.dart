// SPDX-License-Identifier: GPL-3.0-only

/// 我的分享里的一行：名称 + 状态 + 权限档位 + 复制链接 / 停止共享。
///
/// 状态判定顺序有讲究（见 [shareStatusOf]）：撤销 > 源失效 > 已停止 > 有效期 > 有效。
/// 顺序错了会出现「已撤销的分享显示为有效」这种误导性文案。
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'app_controls.dart';

import 'package:path/path.dart' as p;

import '../../app/theme/tokens.dart';
import '../../core/contracts/contracts.dart';

/// 本机分享的位置独立于可编辑的分享名称。
String shareLocationLabel(ShareRecord share) {
  if (share.rootKind != 'localPath') return share.rootUri;
  final bool windows =
      share.rootUri.startsWith(r'\') ||
      p.windows.rootPrefix(share.rootUri).length > 1;
  final p.Context paths = windows
      ? p.Context(style: p.Style.windows)
      : p.Context(style: p.Style.posix);
  return paths.normalize(share.rootUri);
}

/// 一条分享在界面上的状态。
enum ShareStatus {
  /// 可用。
  active,

  /// 已撤销（链接一律 410）。
  revoked,

  /// 源文件失效（被移动或删除），需要重新定位。
  missing,

  /// 手动停止共享。
  stopped,

  /// 过了有效期。
  expired,
}

/// 判定一条分享的界面状态。
///
/// 优先级：撤销 > 源失效 > 已停止 > 过期 > 有效。
/// 撤销最优先，因为它是终态且对外承诺过「链接 410」。
ShareStatus shareStatusOf(ShareRecord share, {DateTime? now}) {
  if (share.isRevoked) return ShareStatus.revoked;
  if (share.missing) return ShareStatus.missing;
  if (!share.enabled) return ShareStatus.stopped;
  final DateTime? expiresAt = share.expiresAt;
  if (expiresAt != null && expiresAt.isBefore(now ?? DateTime.now())) {
    return ShareStatus.expired;
  }
  return ShareStatus.active;
}

/// 状态的中文文案。
String shareStatusLabel(ShareStatus status) => switch (status) {
  ShareStatus.active => '有效',
  ShareStatus.revoked => '已撤销',
  ShareStatus.missing => '源已失效',
  ShareStatus.stopped => '已停止',
  ShareStatus.expired => '已过期',
};

/// 权限档位的中文文案（对应契约 ShareMode）。
String shareModeLabel(ShareMode mode) => switch (mode) {
  ShareMode.lan => '同网段可读',
  ShareMode.token => '需链接凭证',
  ShareMode.password => '需口令',
  ShareMode.people => '仅指定人',
  ShareMode.group => '仅群成员',
  ShareMode.offer => '一次性',
  ShareMode.session => '随会话失效',
};

/// 一条分享的界面行。
class ShareRow extends StatelessWidget {
  /// [onCopyLink] / [onStop] 为 null 时对应按钮禁用。
  const ShareRow({
    super.key,
    required this.share,
    this.onCopyLink,
    this.onStop,
    this.trailing,
    this.now,
    this.compact = false,
  });

  /// 分享记录。
  final ShareRecord share;

  /// 复制链接回调。
  final VoidCallback? onCopyLink;

  /// 行尾自定义动作区（当前用于「更多操作」菜单）。
  ///
  /// 存在理由：把复制/停止/展开/删除这些动作收进一个下拉，
  /// 而不是让它们平铺在卡片上占满一行——卡片上出现七个按钮时，
  /// 用户既看不清主次，又会看到三个语义重复的「复制链接」。
  final Widget? trailing;

  /// 停止共享回调。
  final VoidCallback? onStop;

  /// 判定「过期」用的时间，测试可注入。
  final DateTime? now;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    final ShareStatus status = shareStatusOf(share, now: now);
    final bool active = status == ShareStatus.active;
    final String location = shareLocationLabel(share);
    final String title = share.displayName.trim().isEmpty
        ? location
        : share.displayName;

    return MiuixCard(
      child: Padding(
        padding: compact
            ? const EdgeInsets.fromLTRB(12, 8, 8, 8)
            : const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  share.kind == 'file' ? LucideIcons.file : LucideIcons.folder,
                  size: 18,
                  color: tokens.fgDim,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppTooltip(
                    message: title,
                    child: Text(
                      title,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: tokens.fg,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ShareStatusChip(status: status),
                if (compact && trailing != null) ...[
                  const SizedBox(width: 6),
                  trailing!,
                ],
              ],
            ),
            SizedBox(height: compact ? 2 : 6),
            AppTooltip(
              message: location,
              child: Text(
                location,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: tokens.fgDim),
              ),
            ),
            SizedBox(height: compact ? 2 : 4),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    shareModeLabel(share.mode),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: tokens.fgDim),
                  ),
                ),
                // 传 null 表示「这一行不提供该动作」，此时**整颗按钮不渲染**。
                // 之前是渲染出禁用态按钮：菜单化之后，卡片上不该再出现
                // 一排灰按钮占位置（那正是用户要求收进菜单的原因）。
                if (onCopyLink != null)
                  AppButton.icon(
                    onPressed: active ? onCopyLink : null,
                    icon: const Icon(LucideIcons.link, size: 16),
                    label: const Text('复制链接'),
                  ),
                if (onStop != null)
                  AppButton.icon(
                    onPressed: active ? onStop : null,
                    icon: const Icon(LucideIcons.circleStop, size: 16),
                    label: const Text('停止共享'),
                  ),
                if (!compact && trailing != null) trailing!,
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 状态标签：不用第二色相区分，靠密度与透明度。
///
/// 有效时用 accent 描边，其余状态用中性描边 + 降透明，符合双色约束。
class ShareStatusChip extends StatelessWidget {
  /// 展示哪个状态。
  const ShareStatusChip({super.key, required this.status});

  /// 分享状态。
  final ShareStatus status;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    final bool active = status == ShareStatus.active;
    final Color color = active ? tokens.accent : tokens.fgDim;
    return MiuixBadge(
      containerColor: active ? tokens.accent.withValues(alpha: .10) : tokens.bg,
      contentColor: color,
      child: Text(shareStatusLabel(status)),
    );
  }
}
