// SPDX-License-Identifier: GPL-3.0-only

/// 本机在局域网内的可达地址。
///
/// 为什么需要它：用户要的是「局域网内能直接打开的网页链接」
/// （形如 http://我的IP:端口/s/分享ID?k=凭证）。
/// 没有本机地址，链接就只能是 lsf:// 自定义协议——那要求对方装了这个 App，
/// 浏览器里打不开，与产品要求不符。
///
/// 同时它也是公告里 ip 字段的唯一正确来源：之前一直是空串，
/// 导致对端拿到公告后无法回连（能看到人、却下不了他的文件）。
library;

import 'dart:io';

import '../contracts/contracts.dart';
import 'lan_address_guard.dart';
import 'lan_interfaces.dart';
import 'local_domain.dart' show isLocalDomain;

/// 选出最适合对外通告的本机 IPv4 地址。
///
/// 规则（按优先级）：
/// 1. 必须通过 LanAddressGuard（只允许私有/链路本地段，公网地址不能做局域网分享）；
/// 2. 避开回环（127/8）与链路本地（169.254/16）：前者对方连不上，
///    后者多半是没拿到 DHCP，通告出去也没用；
/// 3. 虚拟网卡（vEthernet / vmnet / docker）排最后但不排除——
///    有些机器只有这一块在用。
///
/// 找不到返回 null：**不猜**。调用方据此给可读提示，而不是拼一个必然失效的链接。
Future<String?> pickLanAddress({
  Future<List<NetworkInterface>> Function()? listInterfaces,
  String? operatingSystem,
}) async {
  final List<NetworkInterface> interfaces;
  try {
    interfaces = await lanInterfaces(
      await (listInterfaces?.call() ??
          NetworkInterface.list(
            type: InternetAddressType.IPv4,
            includeLoopback: false,
            includeLinkLocal: false,
          )),
      operatingSystem: operatingSystem,
    );
  } on Object {
    return null;
  }

  final List<String> candidates = <String>[];
  final android = (operatingSystem ?? Platform.operatingSystem) == 'android';
  for (final NetworkInterface iface in interfaces) {
    final String name = iface.name.toLowerCase();
    final bool isVirtual =
        name.contains('vethernet') ||
        name.contains('vmnet') ||
        name.contains('docker') ||
        name.contains('br-') ||
        name.contains('virtualbox') ||
        name.contains('loopback');
    for (final InternetAddress addr in iface.addresses) {
      if (addr.type != InternetAddressType.IPv4) continue;
      final String ip = addr.address;
      if (!LanAddressGuard.allowsCleartext(ip)) continue;
      if (ip.startsWith('127.')) continue;
      if (ip.startsWith('169.254.')) continue;
      // Native Android selection orders connected LAN interfaces by the
      // active network. Never compare a cellular private IP with a Wi-Fi IP.
      if (android) return ip;
      // 前缀即排序权重：0 最优，1 次优，2 兜底。
      final String key = isVirtual
          ? '2$ip'
          : (ip.startsWith('192.168.') || ip.startsWith('10.')
                ? '0$ip'
                : '1$ip');
      candidates.add(key);
    }
  }
  if (candidates.isEmpty) {
    return null;
  }
  candidates.sort();
  return candidates.first.substring(1);
}

/// 由本机地址、端口、shareId 拼出**浏览器可直接打开**的分享页地址。
///
/// 与 lsf:// 深链分工：
/// - lsf:// 给装了 App 的同类设备（能唤起并定位到分享）；
/// - 本函数给「任何有浏览器的设备」（手机扫码、发给别人、粘到浏览器）。
Uri buildWebShareUrl({
  required String host,
  required int port,
  required ShareId shareId,
  String? token,
  String? localDomain,
}) => _buildWebUrl(
  host: host,
  port: port,
  localDomain: localDomain,
  path: '/s/${shareId.value}',
  token: token,
);

Uri buildWebHomeUrl({
  required String host,
  required int port,
  String? localDomain,
}) => _buildWebUrl(host: host, port: port, localDomain: localDomain, path: '/');

Uri _buildWebUrl({
  required String host,
  required int port,
  required String path,
  String? localDomain,
  String? token,
}) {
  LanAddressGuard.requireCleartextAllowed(host);
  if (localDomain != null && !isLocalDomain(localDomain)) {
    throw const LanFileException(LanFileErrorCode.invalidArgument, '局域网域名无效');
  }
  return Uri(
    scheme: 'http',
    host: localDomain ?? host,
    port: port,
    path: path,
    queryParameters: token == null || token.isEmpty
        ? null
        : <String, String>{'k': token},
  );
}
