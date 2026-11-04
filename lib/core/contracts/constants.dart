// SPDX-License-Identifier: GPL-3.0-only

/// 全局常量：端口、超时、容量上限。
///
/// 任何模块不得自带魔数，一律从此处取。
library;

/// 全工程共用的硬性常量。
final class LanFileConstants {
  const LanFileConstants._();

  /// HTTP 服务默认端口，被占用时按 [httpPortFallbackSpan] 顺延。
  static const int httpPort = 47778;

  /// 端口顺延的最大尝试次数。
  static const int httpPortFallbackSpan = 8;

  /// UDP 发现端口。
  static const int udpPort = 47777;

  /// 组播组地址。
  static const String multicastGroup = '239.255.77.77';

  /// 有活跃共享时的公告间隔。
  static const Duration announceIntervalServing = Duration(seconds: 10);

  /// 空闲（无共享）时的公告间隔。
  static const Duration announceIntervalIdle = Duration(seconds: 30);

  /// 超过该时长未收到公告即判定为离线（UI 置灰）。
  static const Duration peerOfflineAfter = Duration(seconds: 30);

  /// 超过该时长未收到公告即从列表中移除。
  static const Duration peerForgetAfter = Duration(minutes: 5);

  /// 单文件大小上限（100 GB）。
  static const int maxFileBytes = 100 * 1024 * 1024 * 1024;

  /// 目录分页大小。
  static const int treePageSize = 200;

  /// 下载并发连接数。
  static const int downloadConcurrency = 8;

  /// 单次 Range 分片大小。
  static const int rangeChunkBytes = 4 * 1024 * 1024;

  /// 一次性临时分享的有效期。
  static const Duration offerShareTtl = Duration(minutes: 30);

  /// 待决策 offer 的默认过期时长。
  static const Duration offerDecisionTtl = Duration(minutes: 30);

  /// 网页访客会话心跳间隔。
  static const Duration guestHeartbeat = Duration(seconds: 15);

  /// 网页访客会话两次心跳缺失即判定结束。
  static const int guestMissedBeatsBeforeExpiry = 2;

  /// 网页临时区默认配额（20 GB）。
  static const int webShareQuotaBytes = 20 * 1024 * 1024 * 1024;

  /// 会话撤销后临时文件的清理宽限期。
  static const Duration webShareGracePeriod = Duration(minutes: 10);

  /// 传输中断后静默续传的等待上限，超过则进入等待重连态。
  static const Duration transferSilentResumeWindow = Duration(seconds: 30);

  /// 传输失败判定窗口，超过则标记失败并保留断点。
  static const Duration transferFailWindow = Duration(minutes: 5);

  /// 协议版本号，公告与 API 均携带。
  static const int protocolVersion = 2;

  /// API 前缀。
  static const String apiPrefix = '/api/v1';
}
