// SPDX-License-Identifier: GPL-3.0-only

/// 为当前程序的 HTTP 端口放行本地子网访问。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// 只调整指定程序的 TCP 规则，保留公共网络上的阻止设置。
String buildWindowsFirewallScript({
  required String executablePath,
  required int port,
  bool includeMdns = false,
  bool includeBrowserPort = false,
}) {
  if (port < 1 || port > 65535 || !p.windows.isAbsolute(executablePath)) {
    throw ArgumentError('需要绝对程序路径和有效端口');
  }
  final String program = executablePath.replaceAll("'", "''");
  final String mdnsRule = includeMdns
      ? r'''
  $mdnsName = "Lan Simple File mDNS 5353 - $program"
  try { $mdns = $policy.Rules.Item($mdnsName) } catch { $mdns = $null }
  $newMdns = $null -eq $mdns
  if ($newMdns) { $mdns = New-Object -ComObject HNetCfg.FWRule }
  $mdns.Name = $mdnsName
  $mdns.Description = 'Username.local discovery on the local subnet'
  $mdns.ApplicationName = $program
  $mdns.Protocol = 17
  $mdns.LocalPorts = '5353'
  $mdns.RemoteAddresses = 'LocalSubnet'
  $mdns.Profiles = 3
  $mdns.Direction = 1
  $mdns.Action = 1
  $mdns.EdgeTraversal = $false
  $mdns.Enabled = $true
  if ($newMdns) { $policy.Rules.Add($mdns) }
'''
      : '';
  final String mdnsProtocol = includeMdns ? r' -or $rule.Protocol -eq 17' : '';
  final String browserRule = includeBrowserPort && port != 80
      ? r'''
  $browserName = "Lan Simple File HTTP 80 - $program"
  try { $browser = $policy.Rules.Item($browserName) } catch { $browser = $null }
  $newBrowser = $null -eq $browser
  if ($newBrowser) { $browser = New-Object -ComObject HNetCfg.FWRule }
  $browser.Name = $browserName
  $browser.Description = 'Domain sharing without a port on the local subnet'
  $browser.ApplicationName = $program
  $browser.Protocol = 6
  $browser.LocalPorts = '80'
  $browser.RemoteAddresses = 'LocalSubnet'
  $browser.Profiles = 3
  $browser.Direction = 1
  $browser.Action = 1
  $browser.EdgeTraversal = $false
  $browser.Enabled = $true
  if ($newBrowser) { $policy.Rules.Add($browser) }
'''
      : '';
  return '''
\$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new(\$false)
try {
  \$identity = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
  if (-not \$identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw '请以管理员身份运行一次应用，再允许局域网访问'
  }
  \$program = '$program'
  \$policy = New-Object -ComObject HNetCfg.FwPolicy2
  \$ruleName = "Lan Simple File HTTP $port - \$program"
  try { \$allow = \$policy.Rules.Item(\$ruleName) } catch { \$allow = \$null }
  \$isNew = \$null -eq \$allow
  if (\$isNew) { \$allow = New-Object -ComObject HNetCfg.FWRule }
  \$allow.Name = \$ruleName
  \$allow.Description = 'HTTP sharing on the local subnet'
  \$allow.ApplicationName = \$program
  \$allow.Protocol = 6
  \$allow.LocalPorts = '$port'
  \$allow.RemoteAddresses = 'LocalSubnet'
  \$allow.Profiles = 3
  \$allow.Direction = 1
  \$allow.Action = 1
  \$allow.EdgeTraversal = \$false
  \$allow.Enabled = \$true
  if (\$isNew) { \$policy.Rules.Add(\$allow) }
  $mdnsRule
  $browserRule
  # Explicit block rules override allows, including rules left by a denied prompt.
  foreach (\$rule in @(\$policy.Rules)) {
    if (\$rule.Enabled -and \$rule.Direction -eq 1 -and \$rule.Action -eq 0 -and
        \$rule.ApplicationName -ieq \$program -and
        (\$rule.Protocol -eq 6 -or \$rule.Protocol -eq 256$mdnsProtocol) -and
        (\$rule.Profiles -band 3) -ne 0) {
      \$remaining = \$rule.Profiles -band 4
      if (\$remaining -eq 0) { \$rule.Enabled = \$false }
      else { \$rule.Profiles = \$remaining }
    }
  }
  Write-Output 'OK'
} catch {
  [Console]::Error.WriteLine(\$_.Exception.Message)
  exit 1
}
''';
}

/// 成功返回 null；失败返回可展示的原因。
Future<String?> allowWindowsLanAccess(int port) async {
  if (!Platform.isWindows) return '此操作仅适用于 Windows';
  try {
    final String script = buildWindowsFirewallScript(
      executablePath: Platform.resolvedExecutable,
      port: port,
      includeMdns: true,
      includeBrowserPort: true,
    );
    // -EncodedCommand 使用 UTF-16LE，保留中文路径并避免 shell 参数插值。
    final ByteData bytes = ByteData(script.length * 2);
    for (int i = 0; i < script.length; i++) {
      bytes.setUint16(i * 2, script.codeUnitAt(i), Endian.little);
    }
    final ProcessResult result = await Process.run(
      'powershell.exe',
      <String>[
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-EncodedCommand',
        base64Encode(bytes.buffer.asUint8List()),
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode == 0 && result.stdout.toString().trim() == 'OK') {
      return null;
    }
    return '防火墙设置失败：${result.stderr.toString().trim()}';
  } on Object catch (error) {
    return '防火墙设置失败：$error';
  }
}
