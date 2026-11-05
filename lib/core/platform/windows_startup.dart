// SPDX-License-Identifier: GPL-3.0-only
import 'dart:io';

class WindowsStartup {
  WindowsStartup({String? executable, this.valueName = 'LanSimpleFile'})
    : executable = executable ?? Platform.resolvedExecutable;
  final String executable, valueName;
  static const registryPath =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  Future<bool> enabled() async {
    if (!Platform.isWindows) return false;
    final result = await Process.run('reg.exe', [
      'query',
      registryPath,
      '/v',
      valueName,
    ]);
    if (result.exitCode == 1) return false;
    if (result.exitCode != 0) throw StateError(result.stderr.toString());
    return result.stdout.toString().contains('"$executable"');
  }

  Future<void> setEnabled(bool value) async {
    if (!Platform.isWindows) throw UnsupportedError('仅Windows支持');
    if (value && !File(executable).existsSync()) throw StateError('客户端程序不存在');
    if (!value && !await enabled()) return;
    final args = value
        ? [
            'add',
            registryPath,
            '/v',
            valueName,
            '/t',
            'REG_SZ',
            '/d',
            '"$executable"',
            '/f',
          ]
        : ['delete', registryPath, '/v', valueName, '/f'];
    final result = await Process.run('reg.exe', args);
    if (result.exitCode != 0) throw StateError(result.stderr.toString());
  }
}
