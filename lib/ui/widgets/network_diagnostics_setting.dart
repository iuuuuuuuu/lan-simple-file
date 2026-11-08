// SPDX-License-Identifier: GPL-3.0-only

import 'package:flutter/material.dart';

import '../../app/network_diagnostics.dart';
import '../shell/custom_title_bar.dart';
import 'app_controls.dart';
import 'setting_row.dart';

class NetworkDiagnosticsEntry extends StatelessWidget {
  const NetworkDiagnosticsEntry({super.key, this.exportLog});
  final Future<bool> Function({required bool save})? exportLog;

  @override
  Widget build(BuildContext context) => SettingRow(
    key: const ValueKey('open-network-diagnostics'),
    label: '网络诊断',
    subtitle: '查看与导出本机网络日志',
    leading: const Icon(Icons.network_check, size: 20),
    trailing: const Icon(Icons.chevron_right, size: 20),
    onTap: () => Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => AppScaffold(
          body: SafeArea(
            child: Column(
              children: [
                  if (CustomTitleBar.enabled) const CustomTitleBar(),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      AppIconButton(
                        key: const ValueKey('diagnostics-back'),
                        tooltip: '返回设置',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        '网络诊断',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: NetworkDiagnosticsSetting(exportLog: exportLog),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class NetworkDiagnosticsSetting extends StatefulWidget {
  const NetworkDiagnosticsSetting({super.key, this.exportLog});
  final Future<bool> Function({required bool save})? exportLog;

  @override
  State<NetworkDiagnosticsSetting> createState() =>
      _NetworkDiagnosticsSettingState();
}

class _NetworkDiagnosticsSettingState extends State<NetworkDiagnosticsSetting> {
  bool _busy = false;
  String? _status;

  Future<void> _export(bool save) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '正在检查本机网络并整理日志…';
    });
    try {
      final action = widget.exportLog ?? NetworkDiagnostics.active!.export;
      final done = await action(save: save);
      if (mounted) {
        setState(() {
          _status = !done
              ? '已取消保存'
              : save
              ? '日志已保存'
              : '已打开系统分享';
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _status = '导出失败，请重试或选择另一种导出方式';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SettingGroup(
    title: '本机诊断日志',
    children: [
      const SettingRow(
        label: '日志内容',
        subtitle: '包含局域网地址、域名和系统网络状态；不包含文件内容、聊天内容或分享凭证。',
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppButton(
                  key: const ValueKey('share-network-log'),
                  onPressed: _busy ? null : () => _export(false),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.share_outlined, size: 18),
                      SizedBox(width: 6),
                      Text('分享日志'),
                    ],
                  ),
                ),
                AppButton(
                  key: const ValueKey('save-network-log'),
                  onPressed: _busy ? null : () => _export(true),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.save_alt, size: 18),
                      SizedBox(width: 6),
                      Text('保存日志文件'),
                    ],
                  ),
                ),
              ],
            ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_status!),
              ),
          ],
        ),
      ),
    ],
  );
}
