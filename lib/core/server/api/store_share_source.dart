// SPDX-License-Identifier: GPL-3.0-only

/// 生产环境的分享来源：把 LanFileStore 里的 ShareRecord 解析成可读的 ShareTarget。
///
/// 这是网页取件（/s/）与打包下载能真正工作的最后一环：
/// 没有它，路由注册了但永远查不到分享。
library;

import 'package:path/path.dart' as p;
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/server/api/share_api.dart';

/// 由真实存储支撑的分享来源。
final class StoreShareSource implements ShareSource {
  const StoreShareSource({
    required this.store,
    required this.localFactory,
    this.safFactory,
    this.now,
  });

  final LanFileStore store;
  final FileRefFactory localFactory;
  final FileRefFactory? safFactory;

  /// 时间来源；可注入以便测试「已过期」判定。
  final DateTime Function()? now;

  DateTime get _now => (now ?? DateTime.now)();

  /// 查该 share 的归属者（不管本机能否读它）。
  ///
  /// 网关要靠它决定「302 到谁那里」。返回 null 表示本机完全没见过这条 share
  /// —— 此时网关只能给 410，绝不猜测归属。
  Future<PeerId?> ownerOf(ShareId id) async {
    final ShareRecord? record = await store.findShare(id);
    if (record == null || record.isRevoked) {
      return null;
    }
    return record.ownerPeerId;
  }

  @override
  Future<ShareTarget?> find(ShareId id) async {
    final ShareRecord? record = await store.findShare(id);
    if (record == null) {
      return null;
    }
    // 四种不可读情形一律返回 null，由路由出 404/410：
    // 停用、源失效、已撤销、已过期。
    if (!record.enabled || record.missing || record.isRevoked) {
      return null;
    }
    final DateTime? expiresAt = record.expiresAt;
    if (expiresAt != null && !expiresAt.isAfter(_now)) {
      return null;
    }

    final FileRefFactory factory;
    if (record.rootKind == 'safTree') {
      final FileRefFactory? saf = safFactory;
      if (saf == null) {
        return null;
      }
      factory = saf;
    } else {
      factory = localFactory;
    }

    final FileRef root;
    try {
      if (record.rootKind == 'localPath' && record.kind == 'file') {
        root = await factory.resolve(
          p.dirname(record.rootUri),
          ItemKey.parse(p.basename(record.rootUri)),
        );
      } else {
        root = await factory.openRoot(record.rootUri);
      }
    } on LanFileException {
      return null;
    }
    if (!await root.exists()) {
      return null;
    }
    if (record.kind == 'file' && root.isDirectory) return null;

    final DeviceRecord? owner = await store.findDevice(record.ownerPeerId);
    return ShareTarget(
      id: record.id,
      displayName: record.displayName,
      root: root,
      ownerPeerId: record.ownerPeerId,
      ownerName: owner?.name ?? record.ownerPeerId.value,
      ownerAvatar:
          '/api/v1/avatar/${record.ownerPeerId.value}'
          '?v=${Uri.encodeQueryComponent(owner?.avatarHash ?? '')}',
    );
  }
}
