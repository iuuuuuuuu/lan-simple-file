// SPDX-License-Identifier: GPL-3.0-only

/// 临时分享工厂：把 offer 变成「只对接收方、只在 ttl 内可读」的 ShareRecord。
///
/// 三条硬约束在这里落地：
/// 1. **接受前零字节**：本工厂只在 accept 之后被调用；accept 之前
///    库里根本不存在这条 share，也就不存在任何可读入口。
/// 2. **仅接收方可读**：mode=offer + 签发的凭证 sub=接收方 peerId，
///    别的主体拿到链接也过不了 verifyForSubject。
/// 3. **过期即不可读**：expiresAt = accept 时刻 + offerShareTtl；
///    可读性判定同时看 revokedAt 与 expiresAt（见 [isReadableAt]），
///    不是只看「有没有被显式撤销」。
library;

import 'dart:math';

import '../contracts/contracts.dart';
import 'offer_codec.dart';

/// 判定一条临时 share 在某时刻是否可读。
///
/// 抽成纯函数是为了让「过期」与「撤销」两条路径都能被单独断言，
/// 不依赖任何 IO 或时钟副作用。
bool isReadableAt(ShareRecord record, DateTime at) {
  if (record.isRevoked) return false;
  if (!record.enabled) return false;
  if (record.missing) return false;
  final DateTime? expiresAt = record.expiresAt;
  if (expiresAt != null && !at.toUtc().isBefore(expiresAt.toUtc())) {
    return false;
  }
  return true;
}

/// 临时分享的唯一性 id 生成器。
typedef OfferShareIdGenerator = String Function();

/// 把 [OfferFile] 列表落成一条 mode=offer 的临时 ShareRecord。
///
/// 注意 rootKind/rootUri 的来源：offer 的内容仍在**发起方**磁盘上，
/// 接收方只是拿到「可去拉」的凭证。因此这里的 rootUri 记的是发起方的
/// 逻辑根（形如 `offer:<offerId>`），不是接收方的本地路径。
/// 接收方不经由 ShareService.browse 读它，而是走传输管道按 itemKey 拉取。
final class TempShareFactory {
  TempShareFactory({
    required this.ownerPeerId,
    DateTime Function()? clock,
    OfferShareIdGenerator? shareIdGenerator,
  })  : _clock = clock ?? DateTime.now,
        _shareIdGenerator = shareIdGenerator ?? _defaultShareId;

  /// 临时分享的 owner：发起方（内容所在方）。
  final PeerId ownerPeerId;

  final DateTime Function() _clock;
  final OfferShareIdGenerator _shareIdGenerator;

  /// 由 offer 生成临时分享。
  ///
  /// [acceptedBy] 是接收方；它会被写进凭证的 sub，保证只有此人能读。
  ShareRecord create({
    required String offerId,
    required List<OfferFile> files,
    required PeerId acceptedBy,
    String? displayName,
  }) {
    final DateTime now = _clock().toUtc();
    final DateTime expiresAt =
        now.add(LanFileConstants.offerShareTtl);
    return ShareRecord(
      id: ShareId.parse(_shareIdGenerator()),
      kind: 'folder',
      rootKind: ShareRootKind.localPath.name,
      // 逻辑根：内容在发起方侧，接收方按 itemKey 经传输管道拉取。
      rootUri: 'offer:$offerId',
      displayName: displayName ?? '来自 ${acceptedBy.value} 的临时分享',
      ownerPeerId: ownerPeerId,
      createdAt: now,
      mode: ShareMode.offer,
      enabled: true,
      missing: false,
      isEphemeral: true,
      expiresAt: expiresAt,
      passwordHash: null,
      groupId: null,
      maxSpeedKbps: null,
      revokedAt: null,
      sessionId: offerId,
    );
  }

  /// 生成只允许 [subject] 读取的凭证授权事实。
  ///
  /// 权限用 read：临时 offer 只用于「拉走」，不给写权限。
  CapabilityGrant grantFor({
    required ShareRecord share,
    required PeerId subject,
    required PeerId issuer,
    String? tokenId,
  }) {
    final DateTime now = _clock().toUtc();
    return CapabilityGrant(
      shareId: share.id,
      issuer: issuer,
      // sub 精确到人：即便链接外泄，别的主体也过不了 verifyForSubject。
      subject: subject.value,
      permissions: const <String>{'read'},
      notBefore: now,
      expiresAt: share.expiresAt ?? now.add(LanFileConstants.offerShareTtl),
      tokenId: tokenId ?? 'o_${_randomSuffix()}',
    );
  }

  static String _defaultShareId() => 'O${_randomSuffix()}';

  static String _randomSuffix() {
    final String stamp =
        DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36);
    return '$stamp${Random().nextInt(1 << 31).toRadixString(36)}';
  }
}