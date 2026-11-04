// SPDX-License-Identifier: GPL-3.0-only

/// 局域网地址判定：明文的唯一合法范围。
///
/// 为什么必须自己判而不能靠 Android 的 network_security_config：
/// Flutter 的 dart:io 走自己的 socket 实现，**不经过 Android 的 java.net 栈**，
/// 因此 `network_security_config.xml` 里的 cleartext 限制对 Dart 侧网络完全不生效。
/// 也就是说「只对局域网明文」这条约束必须在 Dart 里真正实现，否则它是空的。
library;

import 'dart:io';

import '../contracts/contracts.dart';

/// 私有网段判定。
///
/// 白名单而不是「非私有即拒」的原因是：判定必须**默认拒绝**，
/// 只有明确落在这些网段里的地址才允许明文，其余一律要求加密通道。
abstract final class LanAddressGuard {
  /// 判断 [address] 是否属于允许明文的局域网范围。
  ///
  /// 允许：IPv4 私有段（10/8、172.16/12、192.168/16）、链路本地（169.254/16）、回环（127/8）。
  /// 拒绝：公网地址、IPv6 全局地址、以及任何解析失败。
  static bool allowsCleartext(String address) {
    final InternetAddress? parsed = InternetAddress.tryParse(address);
    if (parsed == null) {
      return false;
    }
    return allowsCleartextAddress(parsed);
  }

  /// 同 [allowsCleartext]，但接受已解析地址。
  static bool allowsCleartextAddress(InternetAddress address) {
    switch (address.type) {
      case InternetAddressType.IPv4:
        final List<int> octets = address.rawAddress;
        if (octets.length != 4) {
          return false;
        }
        final int a = octets[0];
        final int b = octets[1];
        // 回环 127/8
        if (a == 127) return true;
        // 私有 10/8
        if (a == 10) return true;
        // 私有 172.16/12
        if (a == 172 && b >= 16 && b <= 31) return true;
        // 私有 192.168/16
        if (a == 192 && b == 168) return true;
        // 链路本地 169.254/16
        if (a == 169 && b == 254) return true;
        return false;
      case InternetAddressType.IPv6:
        final List<int> raw = address.rawAddress;
        if (raw.length != 16) {
          return false;
        }
        // 回环 ::1
        bool allZeroButLast = true;
        for (int i = 0; i < 15; i++) {
          if (raw[i] != 0) {
            allZeroButLast = false;
            break;
          }
        }
        if (allZeroButLast && raw[15] == 1) return true;
        // 链路本地 fe80::/10
        if (raw[0] == 0xfe && (raw[1] & 0xc0) == 0x80) return true;
        // 唯一本地 fc00::/7
        if ((raw[0] & 0xfe) == 0xfc) return true;
        return false;
      case InternetAddressType.unix:
        return false;
      default:
        // 未知类型一律拒绝：判定必须默认拒绝，不能因新增类型而放行。
        return false;
    }
  }

  /// 断言：非局域网地址**必须**被拒。
  ///
  /// 抽出来单独存在的理由：调用点要做的是「不满足就抛异常」，
  /// 而抛出什么错误码是业务决定，不能散在每个调用点各写一遍。
  static void requireCleartextAllowed(String address) {
    if (!allowsCleartext(address)) {
      throw LanFileException(
        LanFileErrorCode.accessDenied,
        '非局域网地址不允许明文传输：$address',
      );
    }
  }
}
