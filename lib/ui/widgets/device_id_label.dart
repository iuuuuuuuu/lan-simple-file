// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/tokens.dart';
import '../../core/contracts/contracts.dart';
import 'app_toast.dart';

class DeviceIdLabel extends StatelessWidget {
  const DeviceIdLabel({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LanFileTokens>()!;
    return Row(
      children: [
        Text('ID ', style: TextStyle(fontSize: 11, color: tokens.fgDim)),
        Expanded(
          child: Tooltip(
            message: id,
            child: Text(
              id,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: tokens.fgDim),
            ),
          ),
        ),
        IconButton(
          tooltip: '复制设备 ID',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          icon: Icon(Icons.copy_outlined, size: 13, color: tokens.fgDim),
          onPressed: PeerId.tryParse(id) == null
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: id));
                  if (context.mounted) AppToast.show(context, '已复制设备 ID');
                },
        ),
      ],
    );
  }
}
