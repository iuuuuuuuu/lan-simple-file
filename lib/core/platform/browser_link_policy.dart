// SPDX-License-Identifier: GPL-3.0-only

import 'dart:convert';
import 'dart:io';

import '../net/local_domain.dart' show isLocalDomain;

class WindowsBrowserProxy {
  const WindowsBrowserProxy({
    required this.enabled,
    required this.server,
    required this.bypass,
    this.autoConfigUrl = '',
  });

  final bool enabled;
  final String server;
  final String bypass;
  final String autoConfigUrl;

  factory WindowsBrowserProxy.fromJson(Map<String, dynamic> data) =>
      WindowsBrowserProxy(
        enabled: data['ProxyEnable'] == 1,
        server: data['ProxyServer'] as String? ?? '',
        bypass: data['ProxyOverride'] as String? ?? '',
        autoConfigUrl: data['AutoConfigURL'] as String? ?? '',
      );

  bool usesProxyFor(String host) {
    // PAC decisions cannot be inferred from the manual proxy bypass list.
    if (autoConfigUrl.trim().isNotEmpty) return true;
    if (!enabled || server.trim().isEmpty) return false;
    final httpProxy = server
        .split(';')
        .any(
          (part) =>
              !part.contains('=') ||
              part.trim().toLowerCase().startsWith('http=') ||
              part.trim().toLowerCase().startsWith('socks='),
        );
    if (!httpProxy) return false;
    for (final raw in bypass.split(';')) {
      final rule = raw.trim().toLowerCase();
      if (rule.isEmpty) continue;
      if (rule == '<local>') {
        if (!host.contains('.')) return false;
        continue;
      }
      final pattern = RegExp.escape(rule)
          .replaceAll(r'\*', '.*')
          .replaceAll(r'\?', '.');
      if (RegExp('^$pattern\$', caseSensitive: false).hasMatch(host)) {
        return false;
      }
    }
    return true;
  }
}

Future<WindowsBrowserProxy?>? _proxyQuery;
DateTime? _proxyQueryTime;

Future<WindowsBrowserProxy?> readWindowsBrowserProxy() async {
  if (!Platform.isWindows) return null;
  if (_proxyQuery == null ||
      DateTime.now().difference(_proxyQueryTime!) >
          const Duration(seconds: 30)) {
    _proxyQueryTime = DateTime.now();
    _proxyQuery = _readProxy();
  }
  return _proxyQuery!;
}

Future<WindowsBrowserProxy?> _readProxy() async {
  return _runProxyCommand(
    r"Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop | Select-Object ProxyEnable,ProxyServer,ProxyOverride,AutoConfigURL | ConvertTo-Json -Compress",
  );
}

Future<WindowsBrowserProxy?> _runProxyCommand(
  String command, {
  String? domain,
}) async {
  try {
    final result = await Process.run(
      'powershell.exe',
      [
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-Command',
        r"$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); " +
            command,
      ],
      environment: domain == null
          ? null
          : {'LAN_SIMPLE_FILE_LOCAL_DOMAIN': domain},
      stdoutEncoding: utf8,
    ).timeout(Duration(seconds: domain == null ? 3 : 8));
    if (result.exitCode != 0) return null;
    final data = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
    return WindowsBrowserProxy.fromJson(data);
  } on Object {
    return null;
  }
}

/// Adds one LAN domain to the current user's manual proxy bypass list.
Future<WindowsBrowserProxy?> ensureWindowsBrowserProxyBypass(
  String domain,
) async {
  if (!Platform.isWindows || !isLocalDomain(domain)) return null;
  final proxy = await _runProxyCommand(_addProxyBypassCommand, domain: domain);
  _proxyQuery = null;
  _proxyQueryTime = null;
  return proxy;
}

const _addProxyBypassCommand = r'''
$domain = $env:LAN_SIMPLE_FILE_LOCAL_DOMAIN
if ($domain -cnotmatch '^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.local$') {
    throw 'Only a valid LAN domain can bypass the proxy.'
}
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$mutex = [Threading.Mutex]::new($false, "Local\LanSimpleFile.ProxyBypass.$sid")
$locked = $false
try {
    try { $locked = $mutex.WaitOne(3000) }
    catch [Threading.AbandonedMutexException] { $locked = $true }
    if (!$locked) { throw 'Proxy bypass update is busy.' }
    $proxy = Get-ItemProperty -LiteralPath $key
    if (![string]::IsNullOrWhiteSpace([string]$proxy.AutoConfigURL)) {
        throw 'PAC rules cannot be changed by a manual proxy bypass.'
    }
    if ($proxy.ProxyEnable -eq 1 -and ![string]::IsNullOrWhiteSpace([string]$proxy.ProxyServer)) {
        $old = [string]$proxy.ProxyOverride
        $rules = @($old -split ';' | ForEach-Object { $_.Trim() })
        if ($rules -notcontains $domain) {
            $updated = if ($old.Length -eq 0) { $domain } else { "$old;$domain" }
            Set-ItemProperty -LiteralPath $key -Name ProxyOverride -Value $updated
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class LanProxyRefresh {
    [DllImport("wininet.dll", SetLastError=true)]
    public static extern bool InternetSetOption(IntPtr handle, int option, IntPtr buffer, int length);
}
'@
            if (![LanProxyRefresh]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) -or
                ![LanProxyRefresh]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0)) {
                throw 'The browser proxy cache could not be refreshed.'
            }
        }
    }
    Get-ItemProperty -LiteralPath $key |
        Select-Object ProxyEnable,ProxyServer,ProxyOverride,AutoConfigURL |
        ConvertTo-Json -Compress
} finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
''';

/// Repairs a manual proxy bypass before retaining an mDNS browser link.
class BrowserLinkPolicy {
  const BrowserLinkPolicy({
    this.proxyQuery = readWindowsBrowserProxy,
    this.proxyRepair = ensureWindowsBrowserProxyBypass,
  });

  final Future<WindowsBrowserProxy?> Function() proxyQuery;
  final Future<WindowsBrowserProxy?> Function(String domain)? proxyRepair;

  Future<String?> domainFor(String? domain) async {
    if (domain == null) return null;
    try {
      final proxy = await proxyQuery();
      // An unreadable configuration is not evidence that mDNS bypasses a proxy.
      if (proxy == null) return null;
      if (!proxy.usesProxyFor(domain)) return domain;
      if (proxy.autoConfigUrl.trim().isNotEmpty || !isLocalDomain(domain)) {
        return null;
      }
      final repaired = await proxyRepair?.call(domain);
      return repaired != null && !repaired.usesProxyFor(domain) ? domain : null;
    } on Object {
      return null;
    }
  }
}
