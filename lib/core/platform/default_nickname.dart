// SPDX-License-Identifier: GPL-3.0-only

/// 本机默认昵称：Android 取系统设备名，桌面端取登录账户名。
library;

import 'dart:io';

import 'package:flutter/services.dart';

const deviceNameChannel = MethodChannel('lan_simple_file/device_info');

Future<String> loadDefaultNickname({
  String? operatingSystem,
  MethodChannel channel = deviceNameChannel,
}) async {
  if ((operatingSystem ?? Platform.operatingSystem) != 'android') {
    return resolveDefaultNickname();
  }
  try {
    final name = (await channel.invokeMethod<String>('getDeviceName'))?.trim();
    if (name != null && name.isNotEmpty) {
      return name.length > 64 ? name.substring(0, 64) : name;
    }
  } on PlatformException {
    // Device names are optional; no permissions are requested.
  } on MissingPluginException {
    // Tests and older embeddings may not expose the channel.
  }
  return 'Android';
}

/// 取当前登录账户名。
///
/// 环境变量优先级按平台习惯：Windows 用 USERNAME，Unix/macOS 用 USER/LOGNAME。
/// 都取不到时回落主机名，再不行给「本机」——**绝不返回空串**，
/// 空名字会让「附近的人」里出现一条没有名字的记录。
String resolveDefaultNickname({Map<String, String>? environment}) {
  if (environment == null && Platform.isAndroid) return 'Android';
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
