// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';

import '../shell/startup_behavior.dart';
import 'setting_row.dart';

class SilentStartupSetting extends StatefulWidget {
  const SilentStartupSetting({super.key, required this.behavior});

  final StartupBehavior behavior;

  @override
  State<SilentStartupSetting> createState() => _SilentStartupSettingState();
}

class _SilentStartupSettingState extends State<SilentStartupSetting> {
  bool _busy = false;
  String? _error;

  Future<void> _change(bool enabled) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.behavior.setEnabled(enabled);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '保存失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: widget.behavior,
    builder: (context, enabled, _) => SettingRow(
      label: '静默启动',
      subtitle: _error ?? '下次启动时进入托盘，后台分享继续运行',
      trailing: Switch(value: enabled, onChanged: _busy ? null : _change),
    ),
  );
}
