// SPDX-License-Identifier: GPL-3.0-only

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/diagnostics/network_log.dart';
import '../core/discovery/announce_service_impl.dart';
import '../core/net/lan_address_guard.dart';
import 'assembly.dart';

class NetworkDiagnostics with WidgetsBindingObserver {
  NetworkDiagnostics(this.log);

  static const enabled = bool.fromEnvironment('NETWORK_DIAGNOSTICS');
  static NetworkDiagnostics? active;
  static const _channel = MethodChannel('lan_simple_file/network_diagnostics');
  final NetworkLog log;
  AppServices? services;
  Timer? _timer;
  Future<void>? _collecting;
  bool _exporting = false;

  static Future<void> initialize(Directory support) async {
    if (!enabled) return;
    final journal = NetworkLog(
      Directory('${support.path}/network-diagnostics'),
    );
    NetworkLog.active = journal;
    final session = NetworkDiagnostics(journal);
    active = session;
    WidgetsBinding.instance.addObserver(session);
    journal.add('app.start', {
      'os': Platform.operatingSystem,
      'diagnosticRevision': 3,
    });
    // Recording is best-effort and must never prevent application startup.
    await journal.flush();
  }

  void attach(AppServices value) {
    services = value;
    unawaited(collect(selfCheck: true));
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(collect());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    log.add('app.lifecycle', {'state': state.name});
    unawaited(log.flush());
    if (state == AppLifecycleState.resumed) unawaited(collect());
  }

  Future<void> collect({bool selfCheck = false}) async {
    final pending = _collecting;
    if (pending != null) {
      await pending;
      if (!selfCheck) return;
    }
    final task = _collect(selfCheck);
    _collecting = task;
    try {
      await task;
    } finally {
      if (identical(_collecting, task)) _collecting = null;
    }
  }

  Future<void> _collect(bool selfCheck) async {
    try {
      var interfaces = <NetworkInterface>[];
      try {
        interfaces = await NetworkInterface.list(includeLoopback: true)
            .timeout(const Duration(seconds: 3));
      } on Object catch (e) {
        log.add('network.interfaces_error', NetworkLog.errorFields(e));
      }
      log.add('network.interfaces', {
        'interfaces': [
          for (final i in interfaces)
            {
              'name': i.name,
              'index': i.index,
              'addresses': i.addresses.map((a) => a.address).toList(),
            },
        ],
      });
      if (Platform.isAndroid) {
        try {
          final snapshot = await _channel
              .invokeMapMethod<String, Object?>('snapshot')
              .timeout(const Duration(seconds: 3));
          log.add('android.network', snapshot ?? {});
        } on Object catch (e) {
          log.add('android.snapshot_error', {
            ...NetworkLog.errorFields(e),
            if (e is PlatformException) 'nativeError': e.message,
          });
        }
      }
      final s = services;
      if (s == null) return;
      final domain = s.localDomain;
      log.add('services.snapshot', {
        'httpRunning': s.server.isRunning,
        'httpPort': s.server.port,
        'browserRunning': s.browserServer?.isRunning ?? false,
        'browserPort': s.browserPort,
        'browserFallback': s.browserServerError != null,
        'domain': domain?.host,
        'advertisedIp': domain?.ip ?? s.lanHost,
        'mdnsReady': domain?.ready,
        'mdnsPort': domain?.port,
        'mdnsHasError': domain?.error != null,
        'udp': s.announce is AnnounceServiceImpl
            ? (s.announce as AnnounceServiceImpl).diagnosticState
            : null,
      });
      if (!selfCheck) return;
      // Only our own addresses and listener ports, never a subnet scan.
      if (domain?.host case final host?) {
        try {
          final resolved = await InternetAddress.lookup(host)
              .timeout(const Duration(seconds: 3));
          log.add('dns.self_lookup', {
            'host': host,
            'addresses': resolved.map((a) => a.address).toList(),
            'origin': 'same-device',
          });
        } on Object catch (e) {
          log.add('dns.self_lookup_error', {
            'host': host,
            ...NetworkLog.errorFields(e),
          });
        }
      }
      final hosts = <String>{
        '127.0.0.1',
        for (final i in interfaces)
          for (final a in i.addresses)
            if (a.type == InternetAddressType.IPv4 &&
                LanAddressGuard.allowsCleartext(a.address))
              a.address,
      }.take(6);
      final ports = <int>{s.port, s.browserPort};
      for (final host in hosts) {
        for (final port in ports) {
          await checkHttp(host, port);
        }
      }
    } on Object catch (e) {
      log.add('diagnostics.collect_error', NetworkLog.errorFields(e));
    } finally {
      await log.flush();
    }
  }

  Future<void> checkHttp(String host, int port) async {
    final client = HttpClient()
      ..findProxy = ((_) => 'DIRECT')
      ..connectionTimeout = const Duration(seconds: 2);
    final watch = Stopwatch()..start();
    try {
      final request = await client
          .getUrl(Uri(scheme: 'http', host: host, port: port, path: '/'))
          .timeout(const Duration(seconds: 2));
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 2),
      );
      log.add('http.self_check', {
        'host': host,
        'port': port,
        'status': response.statusCode,
        'elapsedMs': watch.elapsedMilliseconds,
        'origin': 'same-device',
      });
      // Do not retain catalog contents or follow redirects.
    } on Object catch (e) {
      log.add('http.self_check_error', {
        'host': host,
        'port': port,
        'elapsedMs': watch.elapsedMilliseconds,
        ...NetworkLog.errorFields(e),
      });
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> export({required bool save}) async {
    if (_exporting) throw StateError('正在导出日志');
    _exporting = true;
    try {
      log.add('diagnostics.export');
      await collect(selfCheck: true);
      final cache = await getTemporaryDirectory();
      final file = await log.export(
        Directory('${cache.path}/network-diagnostics'),
      );
      return await _channel.invokeMethod<bool>(save ? 'save' : 'share', {
            'path': file.path,
          }) ??
          false;
    } finally {
      _exporting = false;
    }
  }
}
