// SPDX-License-Identifier: GPL-3.0-only

import 'dart:convert';
import 'dart:io';

class WindowsBrowserProxy {
  const WindowsBrowserProxy({
    required this.enabled,
    required this.server,
    required this.bypass,
  });

  final bool enabled;
  final String server;
  final String bypass;

  bool usesProxyFor(String host) {
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
  try {
    final result = await Process.run('powershell.exe', [
      '-NoLogo',
      '-NoProfile',
      '-NonInteractive',
      '-WindowStyle',
      'Hidden',
      '-Command',
      r"Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop | Select-Object ProxyEnable,ProxyServer,ProxyOverride | ConvertTo-Json -Compress",
    ]).timeout(const Duration(seconds: 3));
    if (result.exitCode != 0) return null;
    final data = jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
    return WindowsBrowserProxy(
      enabled: data['ProxyEnable'] == 1,
      server: data['ProxyServer'] as String? ?? '',
      bypass: data['ProxyOverride'] as String? ?? '',
    );
  } on Object {
    return null;
  }
}

/// Avoids forwarding mDNS names to an HTTP proxy without changing OS settings.
class BrowserLinkPolicy {
  const BrowserLinkPolicy({this.proxyQuery = readWindowsBrowserProxy});

  final Future<WindowsBrowserProxy?> Function() proxyQuery;

  Future<String?> domainFor(String? domain) async {
    if (domain == null) return null;
    final proxy = await proxyQuery();
    return proxy?.usesProxyFor(domain) == true ? null : domain;
  }
}
