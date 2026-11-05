// SPDX-License-Identifier: GPL-3.0-only
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/assembly.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/discovery/announce_service_impl.dart';
import 'package:lan_simple_file/core/discovery/discovery_service_impl.dart';
import 'package:lan_simple_file/core/discovery/peer_activity_tracker.dart';
import 'package:lan_simple_file/core/platform/device_platform.dart';
import 'package:lan_simple_file/ui/shell/qq_shell.dart';
import 'package:lan_simple_file/ui/shell/session_rail.dart';

import '../discovery/announce_network_test.dart'
    show identityA, identityB, verifyPacket;

void main() {
  test('supported platforms have readable labels; unknown and ambiguous tags do not guess', () {
    const labels = {
      'windows': 'Windows',
      'android': 'Android',
      'macos': 'macOS',
      'ios': 'iOS',
      'linux': 'Linux',
    };
    for (final entry in labels.entries) {
      expect(platformLabel(entry.key), entry.value);
      expect(platformFromCapabilities({'chat', 'os:${entry.key}'}), entry.key);
    }
    expect(platformFromCapabilities({'chat'}), isNull);
    expect(platformFromCapabilities({'os:future'}), isNull);
    expect(platformFromCapabilities({'os:windows', 'os:android'}), isNull);
  });

  test('OS capability survives protocol roundtrip and is protected by the signature', () async {
    final identity = identityA();
    final announce = AnnounceServiceImpl(
      identity: identity,
      serverPort: 47778,
      shareCountProvider: const ZeroShareCountProvider(),
      operatingSystem: 'android',
    );
    final signed = await announce.buildSignedPacket();
    final decoded = AnnouncePacket.fromJson(signed.toJson());
    expect(decoded.operatingSystem, 'android');
    expect(await verifyPacket(decoded, identity), isTrue);
    final tampered = AnnouncePacket.fromJson({
      ...signed.toJson(),
      'caps': ['chat', 'os:windows'],
    });
    expect(await verifyPacket(tampered, identity), isFalse);
    expect(announce.capabilities, isNot(contains('os:android')));
  });

  test('signed OS persists to store and reaches self, nearby and offline session rows', () async {
    final temp = await Directory.systemTemp.createTemp('lsf_platform_');
    final services = await AppAssembler.assemble(
      dataDir: temp,
      httpPortOverride: 0,
      udpPortOverride: 0,
      enableDiscovery: false,
    );
    addTearDown(() async {
      await services.stop();
      await temp.delete(recursive: true);
    });
    final announce = AnnounceServiceImpl(
      identity: identityB(),
      serverPort: 47778,
      shareCountProvider: const ZeroShareCountProvider(),
      operatingSystem: 'android',
    );
    final packet = await announce.buildSignedPacket();
    await StorePeerUpsertSink(
      services.store,
      services.identity.peerId,
    ).upsertVerifiedPeer(packet);
    expect((await services.store.findDevice(packet.peerId))!.os, 'android');
    expect(
      services.announce.buildPacket().operatingSystem,
      Platform.operatingSystem,
    );
    services.tracker.touch(packet);
    await services.discovery.refresh();
    expect(
      services.discovery.currentPeers
          .singleWhere((p) => p.peerId == packet.peerId)
          .os,
      'android',
    );
    expect(
      services.discovery.currentPeers
          .singleWhere((p) => p.peerId == services.identity.peerId)
          .os,
      Platform.operatingSystem,
    );
    final source = ServiceShellSessionSource(services);
    expect(
      (await source.rowsFor(ShellSection.nearby))
          .singleWhere((r) => r.id == packet.peerId.value)
          .os,
      'android',
    );
    final offlinePacket = AnnounceServiceImpl(
      identity: identityA(),
      serverPort: 47778,
      shareCountProvider: const ZeroShareCountProvider(),
      operatingSystem: 'macos',
    ).buildPacket();
    await StorePeerUpsertSink(
      services.store,
      services.identity.peerId,
    ).upsertVerifiedPeer(offlinePacket);
    final offline = (await source.rowsFor(ShellSection.nearby))
        .singleWhere((r) => r.id == offlinePacket.peerId.value);
    expect(offline.os, 'macos');
    expect(offline.online, isFalse);
  });

  test('legacy packets retain an OS previously read from storage', () async {
    final self = identityA();
    final tracker = PeerActivityTracker(clock: DateTime.now);
    final announce = AnnounceServiceImpl(
      identity: identityB(),
      serverPort: 47778,
      shareCountProvider: const ZeroShareCountProvider(),
    );
    tracker.touch(announce.buildPacket());
    expect(tracker.peers.single.toPeerView().os, isNull);
    final discovery = DiscoveryServiceImpl(
      announce: announce,
      tracker: tracker,
      identity: self,
      osReader: (_) async => 'macos',
    );
    addTearDown(discovery.dispose);
    await discovery.refresh();
    expect(
      discovery.currentPeers
          .singleWhere((p) => p.peerId == announce.identity.peerId)
          .os,
      'macos',
    );
  });
}
