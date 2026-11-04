// SPDX-License-Identifier: GPL-3.0-only

/// 本机默认昵称：取**登录账户名**，不是主机名。
///
/// 为什么不用 `Platform.localHostname`：那是机器名（如「公司电脑-M600」），
/// 同一台机器上换账号仍是同一个名字，用来区分「谁在共享」是错的。
/// 用户名才是「人的身份」。
library;

import 'dart:io';

/// 取当前登录账户名。
///
/// 环境变量优先级按平台习惯：Windows 用 USERNAME，Unix/macOS 用 USER/LOGNAME。
/// 都取不到时回落主机名，再不行给「本机」——**绝不返回空串**，
/// 空名字会让「附近的人」里出现一条没有名字的记录。
String resolveDefaultNickname({Map<String, String>? environment}) {
  final Map<String, String> env = environment ?? Platform.environment;
  for (final String key in const <String>[
    'USERNAME', // Windows
    'USER', // Unix / macOS
    'LOGNAME', // POSIX 备用
  ]) {
    final String? value = env[key];
    if (value != null) {
      final String trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
  }
  try {
    final String host = Platform.localHostname.trim();
    if (host.isNotEmpty) {
      return host;
    }
  } on Object {
    // 某些受限环境拿不到主机名；继续回落。
  }
  return '本机';
}