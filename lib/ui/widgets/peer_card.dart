// SPDX-License-Identifier: GPL-3.0-only

/// 附近的人列表中的一张卡片：identicon 头像 + 名字 + 在线状态 + 分享数。
///
/// 在线/离线只用双色主题的 accent 实心圆与空心圆表达（计划 §7.1），
/// 不引入第二色相；离线时整卡降透明度，而不是换成红色。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../app/widgets/identicon.dart';
import '../../core/contracts/contracts.dart';
import 'device_platform_label.dart';
import 'device_id_label.dart';

/// 在线状态点的两种形态。
enum PeerDotStyle {
  /// 在线：accent 实心圆。
  filled,

  /// 离线：accent 空心圆（描边，不填充）。
  hollow,
}

/// 一名 peer 的展示卡片。
class PeerCard extends StatelessWidget {
  /// [peer] 来自发现层的 PeerView。
  ///
  /// [onTap] 为空时卡片不可点（例如服务未连接）。
  const PeerCard({
    super.key,
    required this.peer,
    this.onTap,
    this.hasAvatarBytes = false,
    this.avatarBytes,
    this.trailing,
  });

  /// 展示数据。
  final PeerView peer;

  /// 点击回调；为 null 时显示为不可点。
  final VoidCallback? onTap;

  /// 是否已经有自定义头像字节。
  ///
  /// 为 false 时永远显示 identicon（计划 §7.2 的默认头像要求）。
  final bool hasAvatarBytes;
  final Uint8List? avatarBytes;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    final bool online = peer.online;

    // 离线不是换颜色，而是降透明度 + 空心点；明暗两套 token 都成立。
    final double opacity = online ? 1.0 : 0.55;

    return Opacity(
      opacity: opacity,
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: <Widget>[
                PeerAvatar(
                  peerId: peer.peerId.value,
                  size: 40,
                  avatarBytes: avatarBytes,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              peer.name.isEmpty ? peer.peerId.value : peer.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: tokens.fg,
                              ),
                            ),
                          ),
                          if (peer.os?.isNotEmpty == true) ...[
                            const SizedBox(width: 6),
                            DevicePlatformLabel(os: peer.os!),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      DeviceIdLabel(id: peer.peerId.value),
                      Text(
                        _subtitle(peer),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: tokens.fgDim),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                PeerStatusDot(online: online),
                const SizedBox(width: 6),
                Text(
                  online ? '在线' : '离线',
                  style: TextStyle(
                    fontSize: 12,
                    color: online ? tokens.accent : tokens.fgDim,
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _subtitle(PeerView peer) {
    final List<String> parts = <String>[];
    if (peer.shareCount > 0) {
      parts.add('${peer.shareCount} 项共享');
    } else {
      parts.add('暂无共享');
    }
    return parts.join(' · ');
  }
}

/// 在线/离线状态点：accent 实心圆 vs 空心圆。
class PeerStatusDot extends StatelessWidget {
  /// [online] 决定实心还是空心。
  const PeerStatusDot({super.key, required this.online, this.size = 10});

  /// 在线与否。
  final bool online;

  /// 直径（逻辑像素）。
  final double size;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // 实心：accent 填充；空心：透明填充 + accent 描边。
          color: online ? tokens.accent : Colors.transparent,
          border: online ? null : Border.all(color: tokens.accent, width: 1.5),
        ),
      ),
    );
  }
}

/// 当前样式对应的语义名，供测试断言使用。
PeerDotStyle peerDotStyleOf(bool online) =>
    online ? PeerDotStyle.filled : PeerDotStyle.hollow;
