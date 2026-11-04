// SPDX-License-Identifier: GPL-3.0-only

/// 统一错误类型：不抛裸 Exception，所有失败都带可判定的错误码。
library;

/// 可判定的错误码。UI 与网页端按码出文案，不解析 message。
enum LanFileErrorCode {
  invalidArgument,
  notFound,
  accessDenied,
  revoked,
  expired,
  providerOffline,
  quotaExceeded,
  checksumMismatch,
  cancelled,
  unsupported,
  conflict,
  io,
  network,
  internal,
}

/// 工程内所有可预期失败的载体。
final class LanFileException implements Exception {
  const LanFileException(
    this.code,
    this.message, {
    this.httpStatus,
    this.cause,
  });

  final LanFileErrorCode code;
  final String message;
  final int? httpStatus;
  final Object? cause;

  /// 默认 HTTP 状态映射；调用方显式传入 [httpStatus] 时以传入值为准。
  int get resolvedHttpStatus {
    if (httpStatus != null) return httpStatus!;
    switch (code) {
      case LanFileErrorCode.invalidArgument:
        return 400;
      case LanFileErrorCode.notFound:
        return 404;
      case LanFileErrorCode.accessDenied:
        return 403;
      case LanFileErrorCode.revoked:
      case LanFileErrorCode.expired:
        return 410;
      case LanFileErrorCode.providerOffline:
        return 503;
      case LanFileErrorCode.quotaExceeded:
        return 507;
      case LanFileErrorCode.checksumMismatch:
        return 422;
      case LanFileErrorCode.unsupported:
        return 501;
      case LanFileErrorCode.conflict:
        return 409;
      case LanFileErrorCode.cancelled:
        return 499;
      case LanFileErrorCode.io:
      case LanFileErrorCode.internal:
        return 500;
      case LanFileErrorCode.network:
        return 502;
    }
  }

  @override
  String toString() => 'LanFileException(${code.name}): $message';
}
