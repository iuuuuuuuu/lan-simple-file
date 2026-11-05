// SPDX-License-Identifier: GPL-3.0-only
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/assembly.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/messaging/messaging_service_impl.dart';

void main() {
  test(
    'MuMu NAT: signed discovery, authenticated chat and revocation',
    () async {
      final temp = await Directory.systemTemp.createTemp('lsf_mumu_host_');
      final host = await AppAssembler.assemble(
        dataDir: temp,
        name: 'MuMu discovery host',
        enableDiscovery: false,
      );
      addTearDown(() async {
        await host.stop();
        await temp.delete(recursive: true);
      });
      expect(host.port, LanFileConstants.httpPort);
      stdout.writeln(
        'MUMU_HOST_READY ${host.port} ${host.identity.peerId.value}',
      );

      Future<void> waitFor(Future<bool> Function() condition) async {
        final deadline = DateTime.now().add(const Duration(minutes: 4));
        while (!await condition()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Timed out waiting for the MuMu integration test');
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }

      PeerId? emulator;
      await waitFor(() async {
        for (final peer in host.discovery.currentPeers) {
          if (peer.name == 'MuMu NAT test' && peer.online) {
            emulator = peer.peerId;
            return true;
          }
        }
        return false;
      });
      final peer = emulator!;
      await waitFor(() async => host.messaging.isPeerOnline(peer));
      final thread = directThreadId(host.identity.peerId, peer);
      await waitFor(
        () async =>
            (await host.store.listMessages(thread))
                .any((message) => message.body == 'MuMu NAT hello'),
      );
      await host.messaging.sendText(thread, 'Windows NAT reply');
      await waitFor(
        () async => (await host.store.listMessages(thread)).any(
          (message) => message.body == 'MuMu NAT hello' && message.isRevoked,
        ),
      );
      await waitFor(
        () async =>
            (await host.store.listMessages(thread))
                .any((message) => message.body == 'MuMu NAT complete'),
      );
      expect(host.messaging.unverifiedInbound, 0);
      expect(host.messaging.unsignedInbound, 0);
      expect(
        host.discovery.currentPeers.singleWhere((p) => p.peerId == peer).online,
        true,
      );
      await waitFor(() async => !host.messaging.isPeerOnline(peer));
      stdout.writeln('MUMU_HOST_VERIFIED ${peer.value}');
    },
    skip: !const bool.fromEnvironment('RUN_MUMU_DISCOVERY'),
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
