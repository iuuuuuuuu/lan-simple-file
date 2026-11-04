// SPDX-License-Identifier: GPL-3.0-only

/// 组播组地址的解析与「哪些网卡能加入」的判定。
///
/// 抽成独立文件的原因：组播是本模块唯一依赖平台协议栈行为的部分，
/// 单独放一处便于排障（「为什么对方收不到组播」时只看这一个文件）。
library;

import 'dart:io';

import 'package:lan_simple_file/core/contracts/contracts.dart';

/// 组播组的解析结果与网卡筛选。
final class MulticastGroup {
  const MulticastGroup(this.address, this.port);

  /// 组播地址。
  final InternetAddress address;

  /// 目标端口。
  final int port;

  /// 从字符串 + 端口构造；地址非法时抛 [LanFileException]。
  factory MulticastGroup.parse(String group, int port) {
    final InternetAddress address;
    try {
      address = InternetAddress(group);
    } on ArgumentError catch (error) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '组播地址非法: $group',
        cause: error,
      );
    }
    if (!address.isMulticast) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '不是组播地址: $group',
      );
    }
    if (port <= 0 || port > 65535) {
      throw LanFileException(LanFileErrorCode.invalidArgument, '端口越界: $port');
    }
    return MulticastGroup(address, port);
  }

  /// 契约里的默认组播组。
  static MulticastGroup defaultGroup({int? port}) => MulticastGroup.parse(
    LanFileConstants.multicastGroup,
    port ?? LanFileConstants.udpPort,
  );

  @override
  String toString() => '${address.address}:$port';
}

/// 枚举可用于组播的 IPv4 网卡。
///
/// 排除：环回、没有 IPv4 地址的接口。保留顺序按系统返回顺序，
/// 不排序——排序会让「主网卡」在多网卡机器上漂移。
Future<List<NetworkInterface>> listMulticastInterfaces({
  void Function(Object error)? onError,
}) async {
  try {
    final List<NetworkInterface> all = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    return all
        .where(
          (NetworkInterface i) =>
              i.addresses.any((InternetAddress a) => !a.isLoopback),
        )
        .toList(growable: false);
  } on SocketException catch (error) {
    onError?.call(error);
    return const <NetworkInterface>[];
  }
}

/// 对一组网卡逐一 join 组播；返回真正 join 成功的网卡地址。
///
/// 单块网卡失败不抛出：多网卡机器上某块网卡不支持组播是常态，
/// 抛异常会让整条通道起不来。失败原因通过 [onError] 上报。
List<InternetAddress> joinMulticastOnAll({
  required RawDatagramSocket socket,
  required MulticastGroup group,
  required List<NetworkInterface> interfaces,
  void Function(Object error)? onError,
}) {
  final List<InternetAddress> joined = <InternetAddress>[];
  for (final NetworkInterface interface in interfaces) {
    try {
      socket.joinMulticast(group.address, interface);
      if (interface.addresses.isNotEmpty) {
        joined.add(interface.addresses.first);
      }
    } on SocketException catch (error) {
      onError?.call(error);
    }
  }
  if (joined.isEmpty) {
    // 没有可用网卡时退回默认接口 join；失败才算真失败。
    try {
      socket.joinMulticast(group.address);
      joined.add(InternetAddress.anyIPv4);
    } on SocketException catch (error) {
      onError?.call(error);
    }
  }
  return joined;
}
