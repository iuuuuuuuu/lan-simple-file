// SPDX-License-Identifier: GPL-3.0-only

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/platform/windows_firewall.dart';

void main() {
  test('程序路径使用 PowerShell 字符串转义，端口严格校验', () {
    final String script = buildWindowsFirewallScript(
      executablePath: r"D:\分享 O'Brien\app.exe",
      port: 47778,
    );
    expect(script, contains(r"D:\分享 O''Brien\app.exe"));
    expect(script, contains("LocalPorts = '47778'"));
    for (final int port in <int>[0, -1, 65536]) {
      expect(
        () => buildWindowsFirewallScript(
          executablePath: r'D:\app.exe',
          port: port,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => buildWindowsFirewallScript(executablePath: 'app.exe', port: 47778),
      throwsArgumentError,
    );
  });

  test('真实 Windows 规则：移除私人网络 TCP 阻止，保留公共网络和 UDP', () async {
    final String tag = 'LSF test ${DateTime.now().microsecondsSinceEpoch}';
    final String program = 'D:\\$tag\\app.exe';
    final String escapedProgram = program.replaceAll("'", "''");
    const int port = 47778;
    final String allowName = 'Lan Simple File HTTP $port - $program';

    Future<ProcessResult> run(String script) => Process.run(
      'powershell.exe',
      <String>['-NoProfile', '-NonInteractive', '-Command', script],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    final ProcessResult admin = await run(r'''
$identity = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
$identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
''');
    if (admin.stdout.toString().trim() != 'True') {
      markTestSkipped('真实防火墙规则检查需要管理员权限');
      return;
    }

    try {
      final ProcessResult setup = await run('''
\$ErrorActionPreference = 'Stop'
\$policy = New-Object -ComObject HNetCfg.FwPolicy2
foreach (\$entry in @(@('$tag TCP', 6, 7), @('$tag UDP', 17, 2))) {
  \$rule = New-Object -ComObject HNetCfg.FWRule
  \$rule.Name = \$entry[0]
  \$rule.ApplicationName = '$escapedProgram'
  \$rule.Protocol = \$entry[1]
  \$rule.Profiles = \$entry[2]
  \$rule.Direction = 1
  \$rule.Action = 0
  \$rule.Enabled = \$true
  \$policy.Rules.Add(\$rule)
}
''');
      expect(setup.exitCode, 0, reason: setup.stderr.toString());
      for (int i = 0; i < 2; i++) {
        final ProcessResult repaired = await run(
          buildWindowsFirewallScript(executablePath: program, port: port),
        );
        expect(repaired.exitCode, 0, reason: repaired.stderr.toString());
        expect(repaired.stdout.toString().trim(), 'OK');
      }
      final ProcessResult inspect = await run('''
\$policy = New-Object -ComObject HNetCfg.FwPolicy2
@(\$policy.Rules | Where-Object { \$_.ApplicationName -ieq '$escapedProgram' } |
  Select-Object Name,Protocol,Profiles,Action,Enabled,LocalPorts,RemoteAddresses) |
  ConvertTo-Json -Compress
''');
      expect(inspect.exitCode, 0, reason: inspect.stderr.toString());
      final List<dynamic> rules =
          jsonDecode(inspect.stdout.toString()) as List<dynamic>;
      expect(rules, hasLength(3), reason: '重复修复不得添加重复规则');
      final Map<String, dynamic> tcp = rules
          .cast<Map<String, dynamic>>()
          .singleWhere((r) => r['Name'] == '$tag TCP');
      final Map<String, dynamic> udp = rules
          .cast<Map<String, dynamic>>()
          .singleWhere((r) => r['Name'] == '$tag UDP');
      final Map<String, dynamic> allow = rules
          .cast<Map<String, dynamic>>()
          .singleWhere((r) => r['Name'] == allowName);
      expect(tcp['Profiles'], 4);
      expect(tcp['Action'], 0);
      expect(udp['Profiles'], 2);
      expect(udp['Action'], 0);
      expect(allow['Profiles'], 3);
      expect(allow['Action'], 1);
      expect(allow['LocalPorts'], '$port');
      expect(allow['RemoteAddresses'], 'LocalSubnet');
    } finally {
      await run('''
\$policy = New-Object -ComObject HNetCfg.FwPolicy2
foreach (\$rule in @(\$policy.Rules | Where-Object { \$_.ApplicationName -ieq '$escapedProgram' })) {
  \$policy.Rules.Remove(\$rule.Name)
}
''');
    }
  }, skip: !Platform.isWindows);
}
