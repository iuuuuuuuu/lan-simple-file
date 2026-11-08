// SPDX-License-Identifier: GPL-3.0-only

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../diagnostics/network_log.dart';

const lanNetworkChannel = MethodChannel('lan_simple_file/lan_network');

/// Android cellular networks can have RFC1918 addresses too. Only interfaces
/// owned by a Wi-Fi or Ethernet Network are eligible for LAN advertisement.
Future<List<NetworkInterface>> lanInterfaces(
  List<NetworkInterface> interfaces, {
  String? operatingSystem,
  MethodChannel channel = lanNetworkChannel,
}) async {
  if ((operatingSystem ?? Platform.operatingSystem) != 'android') {
    return interfaces;
  }
  try {
    final networks = await channel
        .invokeListMethod<Object?>('getLanInterfaces')
        .timeout(const Duration(seconds: 2));
    if (networks == null) throw const FormatException('Missing LAN snapshot');
    final eligible = <String, Set<String>>{};
    String? preferred;
    for (final item in networks) {
      if (item is! Map ||
          item['name'] is! String ||
          item['addresses'] is! List) {
        throw const FormatException('Invalid LAN snapshot');
      }
      final name = item['name'] as String;
      eligible
          .putIfAbsent(name, () => {})
          .addAll((item['addresses'] as List).whereType<String>());
      if (item['isDefault'] == true) preferred = name;
    }
    final selected = <NetworkInterface>[];
    for (final interface in interfaces) {
      final addresses = interface.addresses
          .where((a) => eligible[interface.name]?.contains(a.address) ?? false)
          .toList();
      if (addresses.isNotEmpty) {
        selected.add(_LanInterface(interface.name, interface.index, addresses));
      }
    }
    selected.sort((a, b) {
      if ((a.name == preferred) != (b.name == preferred)) {
        return a.name == preferred ? -1 : 1;
      }
      return a.name.compareTo(b.name);
    });
    NetworkLog.record('network.lan_selection', {
      'source': 'android-network-capabilities',
      'defaultInterface': preferred,
      'interfaces': [
        for (final i in selected)
          {
            'name': i.name,
            'addresses': i.addresses.map((a) => a.address).toList(),
          },
      ],
    });
    return selected;
  } on Object catch (error) {
    NetworkLog.record(
      'network.lan_selection_fallback',
      NetworkLog.errorFields(error),
    );
    // Older embeddings may not have the channel. Never fall back to arbitrary
    // private addresses: rmnet/ccmni and VPN interfaces must stay excluded.
    return interfaces
        .where(
          (i) => RegExp(
            r'^(?:wlan|wifi|swlan|eth|en|ap|softap|rndis|usb)\d+$',
            caseSensitive: false,
          ).hasMatch(i.name),
        )
        .toList();
  }
}

class _LanInterface implements NetworkInterface {
  _LanInterface(this.name, this.index, this.addresses);
  @override
  final String name;
  @override
  final int index;
  @override
  final List<InterfaceAddress> addresses;
}
