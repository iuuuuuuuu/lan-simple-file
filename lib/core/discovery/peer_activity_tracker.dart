// SPDX-License-Identifier: GPL-3.0-only

/// 上下线状态机：把「多久没听到公告」翻译成 online / offline / removed。
///
/// 三个状态对应契约里的两条阈值（[LanFileConstants.peerOfflineAfter] 与
/// [LanFileConstants.peerForgetAfter]）：
///
/// ```
/// online  --(30s 无公告)-->  offline  --(5min 无公告)-->  removed
///    ^                          |
///    +------(再次收到公告)-------+
/// ```
///
/// 时间来源通过 [now] 注入，绝不在内部读 DateTime.now()——
/// 否则 30 秒、5 分钟的用例只能靠 sleep，既慢又不稳。
library;

import 'package:lan_simple_file/core/contracts/contracts.dart';

/// 一名对端在追踪器里的存活状态。
enum PeerLiveness {
  /// 最近 [LanFileConstants.peerOfflineAfter] 内收到过公告。
  online,

  /// 超过 offline 阈值但未到 forget 阈值；UI 置灰。
  offline,

  /// 超过 forget 阈值，应从列表移除。
  removed,
}

/// 追踪器对单个 peer 的记录。
final class TrackedPeer {
  const TrackedPeer({
    required this.packet,
    required this.lastSeen,
    required this.firstSeen,
    required this.liveness,
  });

  /// 最近一次验签通过的公告。
  final AnnouncePacket packet;

  /// 最近一次收到公告的时刻（注入时钟的读数）。
  final DateTime lastSeen;

  /// 首次看到该 peer 的时刻。
  final DateTime firstSeen;

  final PeerLiveness liveness;

  /// 转为展示投影。
  PeerView toPeerView({String? os}) => PeerView(
    peerId: packet.peerId,
    name: packet.name,
    avatarHash: packet.avatarHash,
    online: liveness == PeerLiveness.online,
    shareCount: packet.shareCount,
    lastSeen: lastSeen,
    os: os ?? packet.operatingSystem,
  );

  TrackedPeer copyWith({
    AnnouncePacket? packet,
    DateTime? lastSeen,
    DateTime? firstSeen,
    PeerLiveness? liveness,
  }) => TrackedPeer(
    packet: packet ?? this.packet,
    lastSeen: lastSeen ?? this.lastSeen,
    firstSeen: firstSeen ?? this.firstSeen,
    liveness: liveness ?? this.liveness,
  );
}

/// 上下线状态机。
///
/// 纯内存、无 IO、无线程；只由 [now] 注入的时钟驱动，因此完全可测。
final class PeerActivityTracker {
  PeerActivityTracker({
    required this.clock,
    this.offlineAfter = LanFileConstants.peerOfflineAfter,
    this.forgetAfter = LanFileConstants.peerForgetAfter,
  });

  /// 时钟注入点，测试可任意推进。
  ///
  /// 公开而非私有：端到端测试要能把时间拨到 31 秒、5 分 1 秒之后。
  final DateTime Function() clock;

  /// 超过该时长未收到公告即 offline。
  final Duration offlineAfter;

  /// 超过该时长未收到公告即移除。
  final Duration forgetAfter;

  /// peerId → 记录。用 Map 而非 List，是为了「收到公告即原地更新」不清空顺序。
  final Map<String, TrackedPeer> _peers = <String, TrackedPeer>{};

  /// 当前仍然记得的所有 peer（含 offline，不含 removed）。
  List<TrackedPeer> get peers => _peers.values.toList(growable: false);

  /// 当前 online 的 peer 数量。
  int get onlineCount => _peers.values
      .where((TrackedPeer p) => p.liveness == PeerLiveness.online)
      .length;

  /// 是否记得某个 peer。
  bool contains(PeerId peerId) => _peers.containsKey(peerId.value);

  /// 读取某个 peer 的记录。
  TrackedPeer? operator [](PeerId peerId) => _peers[peerId.value];

  /// 收到一条**已验签通过**的公告。
  ///
  /// 返回该 peer 更新后的记录；同时把因超时而被移除的 peer 一并返回，
  /// 供上层决定是否要广播「离开」。
  ///
  /// 注意：验签失败的包**不得**走到这里——那是调用方的责任，
  /// 本方法假定入参已经通过验签。
  PeerTouchResult touch(AnnouncePacket packet) {
    final DateTime now = clock();
    final String key = packet.peerId.value;
    final TrackedPeer? existing = _peers[key];
    final TrackedPeer updated;
    if (existing == null) {
      updated = TrackedPeer(
        packet: packet,
        lastSeen: now,
        firstSeen: now,
        liveness: PeerLiveness.online,
      );
    } else {
      updated = existing.copyWith(
        packet: packet,
        lastSeen: now,
        liveness: PeerLiveness.online,
      );
    }
    _peers[key] = updated;
    final List<TrackedPeer> removed = _sweep();
    return PeerTouchResult(peer: updated, removed: removed);
  }

  /// 按当前时刻重新计算所有 peer 的存活状态，并移除超时的。
  ///
  /// 返回本轮由「未移除」变为「removed」的 peer；已经移除过的不重复返回。
  List<TrackedPeer> sweep() => _sweep();

  List<TrackedPeer> _sweep() {
    final DateTime now = clock();
    final List<TrackedPeer> removed = <TrackedPeer>[];
    final List<String> toDelete = <String>[];
    for (final MapEntry<String, TrackedPeer> entry in _peers.entries) {
      final TrackedPeer peer = entry.value;
      final Duration idle = now.difference(peer.lastSeen);
      final PeerLiveness next;
      if (idle >= forgetAfter) {
        next = PeerLiveness.removed;
      } else if (idle >= offlineAfter) {
        next = PeerLiveness.offline;
      } else {
        next = PeerLiveness.online;
      }
      if (next == peer.liveness) {
        continue;
      }
      if (next == PeerLiveness.removed) {
        toDelete.add(entry.key);
        removed.add(peer.copyWith(liveness: PeerLiveness.removed));
      } else {
        _peers[entry.key] = peer.copyWith(liveness: next);
      }
    }
    for (final String key in toDelete) {
      _peers.remove(key);
    }
    return removed;
  }

  /// 清空全部记录（stop 时用）。
  void clear() => _peers.clear();
}

/// [PeerActivityTracker.touch] 的结果。
final class PeerTouchResult {
  const PeerTouchResult({required this.peer, required this.removed});

  /// 刚更新过的那个 peer。
  final TrackedPeer peer;

  /// 本轮因超时被移除的 peer。
  final List<TrackedPeer> removed;
}
