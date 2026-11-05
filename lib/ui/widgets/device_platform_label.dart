// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../core/platform/device_platform.dart';

class DevicePlatformLabel extends StatelessWidget {
  const DevicePlatformLabel({super.key, required this.os});

  final String os;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LanFileTokens>()!;
    final icon = switch (os.toLowerCase()) {
      'windows' => Icons.desktop_windows_outlined,
      'android' => Icons.phone_android,
      'macos' => Icons.laptop_mac,
      'ios' => Icons.phone_iphone,
      _ => Icons.computer,
    };
    return Tooltip(
      message: platformLabel(os),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: tokens.fgDim),
          const SizedBox(width: 3),
          Text(
            platformLabel(os),
            style: TextStyle(fontSize: 11, color: tokens.fgDim),
          ),
        ],
      ),
    );
  }
}
