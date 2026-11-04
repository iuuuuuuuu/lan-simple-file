// SPDX-License-Identifier: GPL-3.0-only

/// 端到端状态机用例：真实 socket 收包 + 注入时钟推进 30s / 5min。
///
/// 关键点：不 sleep。时钟是注入的，推进 31 秒只是一次 advance，
/// 所以这条用例跑完不到一秒，也不会因为 CI 抖动而假红。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/discovery/announce_codec.dart';
import 'package:lan_simple_file/core/discovery/announce_service_impl.dart';
import 'package:lan_simple_file/core/discovery/peer_activity_tracker.dart';
import 'package:lan_simple_file/core/identity/device_identity_impl.dart';

import 'discovery_test_support.dart';

DeviceIdentityImpl identityA() =>
    DeviceIdentityImpl.fromSeed(Uint8List.fromList(List<int>.generate(32, (int i) => i)));

DeviceIdentityImpl identityB() => DeviceIdentityImpl.fromSeed(
      Uint8List.fromList(List<int>.generate(32, (int i) => 0x20 + i)),
    );

void main() {
  group('端到端：真实收包 + 注入时钟', () {
    test('收包后推进 31s → offline；推进到 5min1s → 从 tracker 移除', () async {
      final DeviceIdentityImpl a = identityA();
      final DeviceIdentityImpl b = identityB();
      final int portA = await pickFreeUdpPort();
      final int portB = await pickFreeUdpPort();
      final FakeClock clock = newFakeClock();

      final RecordingSink sinkB = RecordingSink();
      final FakeKeyLookup keysB = FakeKeyLookup()..register(a.peerId, a.publicKey);

      final AnnounceServiceImpl serviceA = AnnounceServiceImpl(
        identity: a,
        serverPort: 47878,
        shareCountProvider: FakeShareCount(1),
        port: portA,
        clock: clock.now,
      );
      final AnnounceServiceImpl serviceB = AnnounceServiceImpl(
        identity: b,
        serverPort: 47879,
        shareCountProvider: FakeShareCount(0),
        port: portB,
        sink: sinkB,
        clock: clock.now,
      )..publicKeyLookup = keysB;

      final Completer<void> got = Completer<void>();
      final StreamSubscription<AnnouncePacket> sub =
          serviceB.watchIncoming().listen((AnnouncePacket p) {
        if (!got.isCompleted && p.peerId == a.peerId) {
          got.complete();
        }
      });

      try {
        await serviceA.start();
        await serviceB.start();

        final AnnouncePacket signed = await serviceA.buildSignedPacket();
        expect(serviceA.debugSendTo(encodeAnnounceFrame(signed), portB), isTrue);
        await got.future.timeout(const Duration(seconds: 5));

        final PeerActivityTracker tracker = serviceB.tracker;
        expect(tracker[a.peerId]!.liveness, PeerLiveness.online);

        clock.advance(const Duration(seconds: 31));
        tracker.sweep();
        expect(tracker[a.peerId]!.liveness, PeerLiveness.offline);
        expect(tracker.contains(a.peerId), isTrue);
        expect(tracker.onlineCount, 0);

        clock.advance(const Duration(minutes: 4, seconds: 30));
        final List<TrackedPeer> removed = tracker.sweep();
        expect(removed.length, 1);
        expect(removed.single.packet.peerId, a.peerId);
        expect(tracker.contains(a.peerId), isFalse);
      } finally {
        await sub.cancel();
        await serviceA.stop();
        await serviceB.stop();
      }
    });

    test('offline 后对端再次公告 → 回到 online 且 upsert 累加到 2 次', () async {
      final DeviceIdentityImpl a = identityA();
      final DeviceIdentityImpl b = identityB();
      final int portA = await pickFreeUdpPort();
      final int portB = await pickFreeUdpPort();
      final FakeClock clock = newFakeClock();

      final RecordingSink sinkB = RecordingSink();
      final FakeKeyLookup keysB = FakeKeyLookup()..register(a.peerId, a.publicKey);

      final AnnounceServiceImpl serviceA = AnnounceServiceImpl(
        identity: a,
        serverPort: 47878,
        shareCountProvider: FakeShareCount(1),
        port: portA,
        clock: clock.now,
      );
      final AnnounceServiceImpl serviceB = AnnounceServiceImpl(
        identity: b,
        serverPort: 47879,
        shareCountProvider: FakeShareCount(0),
        port: portB,
        sink: sinkB,
        clock: clock.now,
      )..publicKeyLookup = keysB;

      final StreamSubscription<AnnouncePacket> sub =
          serviceB.watchIncoming().listen((AnnouncePacket _) {});

      try {
        await serviceA.start();
        await serviceB.start();

        final AnnouncePacket first = await serviceA.buildSignedPacket();
        serviceA.debugSendTo(encodeAnnounceFrame(first), portB);
        await waitForDiscovery(() => sinkB.countFor(a.peerId) == 1,
            const Duration(seconds: 5));

        clock.advance(const Duration(seconds: 40));
        serviceB.tracker.sweep();
        expect(serviceB.tracker[a.peerId]!.liveness, PeerLiveness.offline);

        final AnnouncePacket second = await serviceA.buildSignedPacket();
        serviceA.debugSendTo(encodeAnnounceFrame(second), portB);
        await waitForDiscovery(() => sinkB.countFor(a.peerId) == 2,
            const Duration(seconds: 5));

        expect(serviceB.tracker[a.peerId]!.liveness, PeerLiveness.online,
            reason: '再次收到公告必须回到 online');
        expect(serviceB.tracker.onlineCount, 1);
      } finally {
        await sub.cancel();
        await serviceA.stop();
        await serviceB.stop();
      }
    });

    test('mode 随注入的 shareCount 变化，且真实反映到对端收到的包', () async {
      final DeviceIdentityImpl a = identityA();
      final DeviceIdentityImpl b = identityB();
      final int portA = await pickFreeUdpPort();
      final int portB = await pickFreeUdpPort();
      final FakeShareCount sharesA = FakeShareCount(0);

      final FakeKeyLookup keysB = FakeKeyLookup()..register(a.peerId, a.publicKey);
      final AnnounceServiceImpl serviceA = AnnounceServiceImpl(
        identity: a,
        serverPort: 47878,
        shareCountProvider: sharesA,
        port: portA,
        clock: newFakeClock().now,
      );
      final AnnounceServiceImpl serviceB = AnnounceServiceImpl(
        identity: b,
        serverPort: 47879,
        shareCountProvider: FakeShareCount(0),
        port: portB,
        clock: newFakeClock().now,
      )..publicKeyLookup = keysB;

      final List<AnnouncePacket> seen = <AnnouncePacket>[];
      final StreamSubscription<AnnouncePacket> sub =
          serviceB.watchIncoming().listen(seen.add);

      try {
        await serviceA.start();
        await serviceB.start();

        serviceA.debugSendTo(
          encodeAnnounceFrame(await serviceA.buildSignedPacket()),
          portB,
        );
        await waitForDiscovery(
          () => seen.where((AnnouncePacket p) => p.peerId == a.peerId).length == 1,
          const Duration(seconds: 5),
        );
        expect(seen.last.mode, 'idle');
        expect(seen.last.shareCount, 0);

        sharesA.shareCount = 5;
        serviceA.debugSendTo(
          encodeAnnounceFrame(await serviceA.buildSignedPacket()),
          portB,
        );
        await waitForDiscovery(
          () => seen.where((AnnouncePacket p) => p.peerId == a.peerId).length == 2,
          const Duration(seconds: 5),
        );
        expect(seen.last.mode, 'serving');
        expect(seen.last.shareCount, 5);
      } finally {
        await sub.cancel();
        await serviceA.stop();
        await serviceB.stop();
      }
    });

    test('stop 后 tracker 清空且幂等', () async {
      final DeviceIdentityImpl b = identityB();
      final int portB = await pickFreeUdpPort();
      final AnnounceServiceImpl serviceB = AnnounceServiceImpl(
        identity: b,
        serverPort: 47879,
        shareCountProvider: FakeShareCount(0),
        port: portB,
        clock: newFakeClock().now,
      );
      await serviceB.start();
      expect(serviceB.isRunning, isTrue);

      await serviceB.stop();
      expect(serviceB.isRunning, isFalse);
      expect(serviceB.tracker.peers, isEmpty, reason: 'stop 应清空状态机');
      await serviceB.stop();
    });
  });
}
