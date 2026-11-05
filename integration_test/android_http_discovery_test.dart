// SPDX-License-Identifier: GPL-3.0-only
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lan_simple_file/app/app.dart';
import 'package:lan_simple_file/app/assembly.dart';
import 'package:lan_simple_file/core/messaging/messaging_service_impl.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'MuMu automatically finds Windows across NAT and exchanges signed messages',
    (tester) async {
      final temp = await Directory.systemTemp.createTemp('lsf_mumu_nat_');
      final services = await AppAssembler.assemble(
        dataDir: temp,
        name: 'MuMu NAT test',
        enableDiscovery: true,
      );
      try {
        expect(services.lanHost, '10.0.2.15');
        Future<void> waitFor(Future<bool> Function() condition) async {
          final deadline = DateTime.now().add(const Duration(seconds: 45));
          while (!await condition()) {
            if (DateTime.now().isAfter(deadline)) {
              fail('MuMu NAT timed out: ${services.httpDiscovery?.lastError}');
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }

        await waitFor(
          () async => services.discovery.currentPeers.any(
            (peer) => peer.name == 'MuMu discovery host' && peer.online,
          ),
        );
        final host = services.discovery.currentPeers.singleWhere(
          (peer) => peer.name == 'MuMu discovery host',
        );
        expect(await services.discovery.findEndpoint(host.peerId), (
          host: '10.0.2.2',
          port: 47778,
        ));
        await waitFor(() async => services.messaging.isPeerOnline(host.peerId));
        await tester.pumpWidget(
          ProviderScope(child: LanFileApp(services: services)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('mobile-nav-nearby')));
        await tester.pumpAndSettle();
        expect(find.text('MuMu discovery host'), findsWidgets);
        expect(tester.takeException(), isNull);

        final thread = directThreadId(services.identity.peerId, host.peerId);
        await services.messaging.sendText(thread, 'MuMu NAT hello');
        await waitFor(
          () async =>
              (await services.store.listMessages(thread))
                  .any((message) => message.body == 'Windows NAT reply'),
        );
        final sent = (await services.store.listMessages(thread))
            .singleWhere((message) => message.body == 'MuMu NAT hello');
        await services.messaging.revoke(sent.id);
        // Outlive the offline threshold to check automatic host polling.
        await Future<void>.delayed(const Duration(seconds: 35));
        await services.discovery.refresh();
        expect(
          services.discovery.currentPeers
              .singleWhere((peer) => peer.peerId == host.peerId)
              .online,
          true,
        );
        expect(services.messaging.unverifiedInbound, 0);
        expect(services.messaging.unsignedInbound, 0);
        await services.messaging.sendText(thread, 'MuMu NAT complete');
        await Future<void>.delayed(const Duration(seconds: 1));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await services.stop();
        await temp.delete(recursive: true);
      }
    },
    skip: !const bool.fromEnvironment('RUN_MUMU_DISCOVERY'),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
