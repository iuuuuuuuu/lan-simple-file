// SPDX-License-Identifier: GPL-3.0-only

/// 会话回收器：把「会话已失效」翻译成「share 410 + 宽限期后删磁盘」。
///
/// 两条时序必须分清，否则会出现「链接已失效但文件还在」或
/// 「文件已删但还能下载」的半吊子状态：
///   1. 会话判定失效的**那一刻**：share 立即 revoked_at → 所有链接 410；
///   2. 再过 webShareGracePeriod（10 分钟）：磁盘上的临时文件才真正删除。
///
/// 时间全部来自注入的 [GuestClock]，测试推进时钟即可，不 sleep。
library;

import 'package:lan_simple_file/core/contracts/contracts.dart';

import 'guest_session_registry.dart';
import 'staging_area.dart';

/// 一次清扫的结果，供测试与诊断断言。
final class SweepResult {
  const SweepResult({
    required this.expiredSessions,
    required this.releasedSessions,
    required this.revokedShares,
  });

  static const SweepResult empty = SweepResult(
    expiredSessions: <String>[],
    releasedSessions: <String>[],
    revokedShares: <String>[],
  );

  /// 本次因心跳超时被判失效的会话。
  final List<String> expiredSessions;

  /// 本次真正删掉磁盘文件的会话。
  final List<String> releasedSessions;

  /// 本次被强制置 revoked 的 share。
  final List<String> revokedShares;

  bool get didAnything =>
      expiredSessions.isNotEmpty ||
      releasedSessions.isNotEmpty ||
      revokedShares.isNotEmpty;
}

/// 会话回收器。
final class SessionSweeper {
  SessionSweeper({
    required this.registry,
    required this.staging,
    required this.store,
    this.revokeSharesOf,
  });

  final GuestSessionRegistry registry;
  final StagingArea staging;
  final LanFileStore store;

  /// 会话失效时，把它名下所有 share 置为 revoked。
  ///
  /// 由 WebShareService 注入（它知道哪些 share 属于该会话）；
  /// 为 null 时只清临时文件、不动 share 表。
  final Future<List<String>> Function(String sessionId)? revokeSharesOf;

  /// 跑一轮清扫。
  ///
  /// 幂等：重复调用不会重复删同一批文件（registry 会记 releasedAt）。
  Future<SweepResult> sweep() async {
    final List<String> expiredIds = <String>[];
    final List<String> revoked = <String>[];

    // 阶段 1：心跳超时 → 会话失效 → share 立即 410。
    for (final GuestSession session in registry.reapExpired()) {
      expiredIds.add(session.sessionId);
      registry.endSession(
        session.sessionId,
        SessionEndReason.heartbeatTimeout,
      );
      final Future<List<String>> Function(String)? revoke = revokeSharesOf;
      if (revoke != null) {
        revoked.addAll(await revoke(session.sessionId));
      }
    }

    // 阶段 2：宽限期已过 → 真正删磁盘。
    final List<String> released = <String>[];
    for (final GuestSession session in registry.releasable()) {
      await staging.purgeSession(session.sessionId);
      registry.markReleased(session.sessionId);
      released.add(session.sessionId);
    }

    return SweepResult(
      expiredSessions: expiredIds,
      releasedSessions: released,
      revokedShares: revoked,
    );
  }

  /// 会话结束时立即执行阶段 1（不等下一次 sweep）。
  ///
  /// beforeunload / pagehide / 显式撤销都走这里：链接必须**立刻** 410，
  /// 而磁盘清理由后续 sweep 在宽限期后完成。
  Future<List<String>> revokeSharesNow(String sessionId) async {
    final Future<List<String>> Function(String)? revoke = revokeSharesOf;
    if (revoke == null) return <String>[];
    return revoke(sessionId);
  }
}
