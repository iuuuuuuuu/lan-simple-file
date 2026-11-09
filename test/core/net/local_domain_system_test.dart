// SPDX-License-Identifier: GPL-3.0-only

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/net/lan_address.dart';
import 'package:lan_simple_file/core/net/local_domain.dart';

/// Opt-in: binds real mDNS on the connected LAN without changing DNS or hosts.
void main() {
  test(
    'system resolver reaches the advertised HTTP service',
    () async {
      final address = await pickLanAddress();
      expect(address, isNotNull, reason: 'A connected LAN is required');
      final nonce = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final domain = LocalDomainService(
        username: () => 'lan-check-$nonce',
        deviceId: 'p_testdevice123',
        address: () async => address,
      );
      final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      final requests = server.listen((request) async {
        request.response.write('lan-domain-ok');
        await request.response.close();
      });
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      try {
        await domain.start();
        expect(domain.ready, isTrue, reason: domain.error);
        final resolved = await InternetAddress.lookup(domain.host!)
            .timeout(const Duration(seconds: 8));
        expect(resolved.map((a) => a.address), contains(address));
        final request = await client
            .getUrl(Uri(scheme: 'http', host: domain.host, port: server.port))
            .timeout(const Duration(seconds: 8));
        final response = await request.close();
        expect(response.statusCode, HttpStatus.ok);
        await response.drain<void>();
        // ignore: avoid_print
        print('System DNS and HTTP passed: ${domain.host} -> $address');
      } finally {
        client.close(force: true);
        await domain.stop();
        await server.close(force: true);
        await requests.cancel();
      }
    },
    skip: !const bool.fromEnvironment('LAN_SYSTEM_TEST'),
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
