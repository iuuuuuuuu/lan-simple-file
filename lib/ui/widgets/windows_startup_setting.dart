// SPDX-License-Identifier: GPL-3.0-only

import 'package:flutter/material.dart';

import 'app_controls.dart';

import '../../core/platform/windows_startup.dart';
import 'setting_row.dart';

class WindowsStartupSetting extends StatefulWidget {
  const WindowsStartupSetting({super.key, this.service});
  final WindowsStartup? service;
  @override
  State<WindowsStartupSetting> createState() => _WindowsStartupSettingState();
}

class _WindowsStartupSettingState extends State<WindowsStartupSetting> {
  late final WindowsStartup service = widget.service ?? WindowsStartup();
  bool _enabled = false, _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final enabled = await service.enabled();
      if (mounted) setState(() => _enabled = enabled);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '读取启动项失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _change(bool enabled) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await service.setEnabled(enabled);
      final actual = await service.enabled();
      if (actual != enabled) throw StateError('启动项未成功保存');
      if (mounted) setState(() => _enabled = actual);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '保存启动项失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SettingRow(
    label: '开机自动启动',
    subtitle: _error ?? '登录 Windows 后自动启动客户端',
    trailing: MiuixSwitch(value: _enabled, onChanged: _busy ? null : _change),
  );
}
