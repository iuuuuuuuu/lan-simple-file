// SPDX-License-Identifier: GPL-3.0-only

/// 真实网络用例：同进程内两个 AnnounceServiceImpl 用**不同 UDP 端口**互发。
///
/// 纪律：不 mock 网络。每条用例都真绑 socket、真发字节、真收字节。
///
/// 端口分配：契约常量 udpPort=47777 是生产值；测试里两个实例必须用不同端口，
/// 否则第二个 bind 会撞端口——这正是构造参数 port 存在的意义。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/discovery/announce_codec.dart';
import 'package:lan_simple_file/core/discovery/announce_service_impl.dart';
import 'package:lan_simple_file/core/discovery/udp_channel.dart';
import 'package:lan_simple_file/core/identity/device_identity_impl.dart';

import 'discovery_test_support.dart';

DeviceIdentityImpl identityA() =>
    DeviceIdentityImpl.fromSeed(Uint8List.fromList(List<int>.generate(32, (int i) => i)));

DeviceIdentityImpl identityB() => DeviceIdentityImpl.fromSeed(
      Uint8List.fromList(List<int>.generate(32, (int i) => 0x20 + i)),
    );

Uint8List decodeB64(String text) {
  final int remainder = text.length % 4;
  final String padded = remainder == 0 ? text : text + '=' * (4 - remainder);
  return Uint8List.fromList(base64Url.decode(padded));
}

Future<bool> verifyPacket(AnnouncePacket packet, DeviceIdentity verifier) {
  return verifier.verifyOwn(
    Uint8List.fromList(packet.signableBytes()),
    decodeB64(packet.signature),
  );
}

void main() {
  group('AnnounceServiceImpl 基本形态', () {
    test('buildPacket 按 shareCount 决定 mode=serving / idle', () {
      final FakeShareCount shares = FakeShareCount(0);
      final AnnounceServiceImpl service = AnnounceServiceImpl(
        identity: identityA(),
        serverPort: 47878,
        shareCountProvider: shares,
        clock: newFakeClock().now,
      );
      expect(service.buildPacket().mode, 'idle');

      shares.shareCount = 3;
      final AnnouncePacket serving = service.buildPacket();
      expect(serving.mode, 'serving');
      expect(serving.shareCount, 3);

      shares.shareCount = 0;
      expect(service.buildPacket().mode, 'idle');
    });

    test('buildPacket 携带契约版本与注入的端口/名字/能力', () {
      final AnnounceServiceImpl service = AnnounceServiceImpl(
        identity: identityA(),
        serverPort: 47999,
        shareCountProvider: FakeShareCount(0),
        name: 'YG 的台式机',
        avatarHash: 'sha256:ab12',
        clock: newFakeClock().now,
      );
      final AnnouncePacket packet = service.buildPacket();
      expect(packet.version, LanFileConstants.protocolVersion);
      expect(packet.peerId, identityA().peerId);
      expect(packet.port, 47999);
      expect(packet.name, 'YG 的台式机');
      expect(packet.avatarHash, 'sha256:ab12');
      expect(packet.capabilities, contains('web-session'));
      expect(packet.ip, '');
    });

    test('签名版公告能被签发者公钥验过；篡改后验不过', () async {
      final DeviceIdentityImpl identity = identityA();
      final AnnounceServiceImpl service = AnnounceServiceImpl(
        identity: identity,
        serverPort: 47878,
        shareCountProvider: FakeShareCount(2),
        clock: newFakeClock().now,
      );
      final AnnouncePacket signed = await service.buildSignedPacket();
      expect(signed.signature, isNotEmpty);
      expect(decodeB64(signed.signature).length, 64);
      expect(await verifyPacket(signed, identity), isTrue);

      final AnnouncePacket renamed = AnnouncePacket(
        version: signed.version,
        peerId: signed.peerId,
        name: '冒充者',
        avatarHash: signed.avatarHash,
        port: signed.port,
        ip: signed.ip,
        shareCount: signed.shareCount,
        capabilities: signed.capabilities,
        mode: signed.mode,
        timestamp: signed.timestamp,
        signature: signed.signature,
      );
      expect(await verifyPacket(renamed, identity), isFalse);
    });
  });

  group('真实 socket：广播路径', () {
    test('A 发公告 → B 经真实 socket 收到、验签通过、upsert 一次并入流', () async {
      final DeviceIdentityImpl a = identityA();
      final DeviceIdentityImpl b = identityB();
      final int portA = await pickFreeUdpPort();
      final int portB = await pickFreeUdpPort();

      final RecordingSink sinkB = RecordingSink();
      final FakeKeyLookup keysB = FakeKeyLookup()
        ..register(a.peerId, a.publicKey);

      final AnnounceServiceImpl serviceA = AnnounceServiceImpl(
        identity: a,
        serverPort: 47878,
        shareCountProvider: FakeShareCount(2),
        port: portA,
        clock: newFakeClock().now,
      );
      final AnnounceServiceImpl serviceB = AnnounceServiceImpl(
        identity: b,
        serverPort: 47879,
        shareCountProvider: FakeShareCount(0),
        port: portB,
        sink: sinkB,
        clock: newFakeClock().now,
      )..publicKeyLookup = keysB;

      final Completer<AnnouncePacket> received = Completer<AnnouncePacket>();
      final StreamSubscription<AnnouncePacket> sub =
          serviceB.watchIncoming().listen((AnnouncePacket p) {
        if (!received.isCompleted && p.peerId == a.peerId) {
          received.complete(p);
        }
      });

      try {
        await serviceA.start();
        await serviceB.start();
        expect(serviceA.isRunning, isTrue);
        expect(serviceB.isRunning, isTrue);
        expect(serviceA.isSendOnly, isFalse, reason: '端口空闲时不应降级');
        expect(serviceB.isSendOnly, isFalse);

        final AnnouncePacket signed = await serviceA.buildSignedPacket();
        final Uint8List frame = encodeAnnounceFrame(signed);
        expect(serviceA.debugSendTo(frame, portB), isTrue);

        final AnnouncePacket got =
            await received.future.timeout(const Duration(seconds: 5));
        expect(got.peerId, a.peerId);
        expect(got.mode, 'serving');
        expect(got.shareCount, 2);
        expect(sinkB.countFor(a.peerId), 1, reason: '验签通过必须 upsert');
        expect(serviceB.rejected.badSignature, 0);
        expect(serviceB.tracker.contains(a.peerId), isTrue);
      } finally {
        await sub.cancel();
        await serviceA.stop();
        await serviceB.stop();
      }
    });

    test('broadcast() 真的把包提交给系统（广播 + 组播至少一路成功）', () async {
      final int port = await pickFreeUdpPort();
      final AnnounceServiceImpl service = AnnounceServiceImpl(
        identity: identityA(),
        serverPort: 47878,
        shareCountProvider: FakeShareCount(0),
        port: port,
        clock: newFakeClock().now,
      );
      try {
        await service.start();
        final SendReport? report = await service.announceNow();
        expect(report, isNotNull);
        expect(
          report!.delivered,
          isTrue,
          reason: '广播与组播全失败通常意味着网络栈不可用；'
              'failures=${report.failures}',
        );
        expect(report.broadcastTargets, greaterThan(0),
            reason: '必须对网卡发广播');
        expect(report.bytesSent, greaterThan(0));
        expect(service.lastSendReport, isNotNull);
      } finally {
        await service.stop();
      }
    });
  });

  group('真实 socket：组播路径', () {
    test('向组播组投递 → 已 join 的 B 收到并完成验签', () async {
      final DeviceIdentityImpl a = identityA();
      final DeviceIdentityImpl b = identityB();
      final int portA = await pickFreeUdpPort();
      final int portB = await pickFreeUdpPort();

      final RecordingSink sinkB = RecordingSink();
      final FakeKeyLookup keysB = FakeKeyLookup()
        ..register(a.peerId, a.publicKey);

      final AnnounceServiceImpl serviceA = AnnounceServiceImpl(
        identity: a,
        serverPort: 47878,
        shareCountProvider: FakeShareCount(1),
        port: portA,
        clock: newFakeClock().now,
      );
      final AnnounceServiceImpl serviceB = AnnounceServiceImpl(
        identity: b,
        serverPort: 47879,
        shareCountProvider: FakeShareCount(0),
        port: portB,
        sink: sinkB,
        clock: newFakeClock().now,
      )..publicKeyLookup = keysB;

      final Completer<AnnouncePacket> received = Completer<AnnouncePacket>();
      final StreamSubscription<AnnouncePacket> sub =
          serviceB.watchIncoming().listen((AnnouncePacket p) {
        if (!received.isCompleted && p.peerId == a.peerId) {
          received.complete(p);
        }
      });

      try {
        await serviceA.start();
        await serviceB.start();

        final AnnouncePacket signed = await serviceA.buildSignedPacket();
        final Uint8List frame = encodeAnnounceFrame(signed);
        expect(serviceA.debugSendToMulticast(frame, portB), isTrue);

        final AnnouncePacket got =
            await received.future.timeout(const Duration(seconds: 5));
        expect(got.peerId, a.peerId);
        expect(sinkB.countFor(a.peerId), 1);
      } finally {
        await sub.cancel();
        await serviceA.stop();
        await serviceB.stop();
      }
    });

    test('通道 join 了组播组（joinedInterfaces 非空）', () async {
      final int port = await pickFreeUdpPort();
      final AnnounceServiceImpl service = AnnounceServiceImpl(
        identity: identityA(),
        serverPort: 47878,
        shareCountProvider: FakeShareCount(0),
        port: port,
        clock: newFakeClock().now,
      );
      try {
        await service.start();
        final List<String> joined = service.debugJoinedInterfaces;
        expect(joined, isNotEmpty, reason: '必须真正 joinMulticastGroup 成功');
      } finally {
        await service.stop();
      }
    });
  });
}
