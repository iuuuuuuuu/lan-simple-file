// SPDX-License-Identifier: GPL-3.0-only

import 'package:flutter/material.dart';

import 'app_controls.dart';

import '../../platform/android/permission_flow.dart';
import 'setting_row.dart';

class AndroidAllFilesSetting extends StatefulWidget {
  const AndroidAllFilesSetting({super.key, this.bridge});

  final PermissionBridge? bridge;

  @override
  State<AndroidAllFilesSetting> createState() => _AndroidAllFilesSettingState();
}

class _AndroidAllFilesSettingState extends State<AndroidAllFilesSetting>
    with WidgetsBindingObserver {
  late final PermissionBridge _bridge =
      widget.bridge ?? const PermissionBridge();
  PermissionGrantState _state = PermissionGrantState.unknown;
  bool _loading = true;
  bool _opening = false;
  int _readId = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final readId = ++_readId;
    final state = await _bridge.allFilesAccessState();
    if (!mounted || readId != _readId) return;
    setState(() {
      _state = state;
      _loading = false;
    });
  }

  Future<void> _openSettings() async {
    if (_loading || _opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      await _bridge.openAllFilesAccessSettings();
      await _load();
    } on PermissionFlowFailure catch (error) {
      if (mounted) setState(() => _error = error.userMessage);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _loading
        ? '读取中'
        : switch (_state) {
            PermissionGrantState.granted => '已授权',
            PermissionGrantState.denied => '未授权',
            PermissionGrantState.notRequired => '不适用',
            PermissionGrantState.unknown => '状态未知',
          };
    final open =
        _loading || _opening || _state == PermissionGrantState.notRequired
        ? null
        : _openSettings;
    return SettingRow(
      label: '所有文件访问',
      subtitle: _error ?? '可选权限；不包含 Android/data、obb 和应用私有目录',
      onTap: open,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SettingValue(text: status),
          AppIconButton(
            key: const ValueKey('all-files-settings'),
            tooltip: '文件访问授权设置',
            onPressed: open,
            icon: const Icon(Icons.settings_outlined, size: 18),
          ),
        ],
      ),
    );
  }
}
