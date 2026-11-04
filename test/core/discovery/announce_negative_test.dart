// SPDX-License-Identifier: GPL-3.0-only

/// 负向与状态机用例：验签失败丢弃计数、probe 即时应答、端口降级、自己过滤。
///
/// 全部走真实 socket。「能变红」的证明写在报告里：把验签逻辑注释掉后
/// 「篡改 sig 不被 upsert」这条会立刻失败（见报告的真实输出节选）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

/// 把 base64url 签名解出来改一个字节再编回去。
String corruptSignature(String signature) {
  final Uint8List raw = decodeB64(signature);
  raw[0] ^= 0x01;
  return base64Url.encode(raw).replaceAll('=', '');
}

void main() {
  group('验签失败必须丢弃并计数（不得 upsert）', () {
    test('篡改 sig 一个字节 → 不 upsert、不进流、badSignature+1', () async {
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

      final List<AnnouncePacket> seen = <AnnouncePacket>[];
      final StreamSubscription<AnnouncePacket> sub =
          serviceB.watchIncoming().listen(seen.add);

      try {
        await serviceA.start();
        await serviceB.start();

        // 先投一条**合法**的，确认链路本身是通的（反假绿）。
        final AnnouncePacket good = await serviceA.buildSignedPacket();
        expect(serviceA.debugSendTo(encodeAnnounceFrame(good), portB), isTrue);
        await _waitFor(() => sinkB.upserted.isNotEmpty, const Duration(seconds: 5));
        expect(sinkB.countFor(a.peerId), 1);
        expect(seen.where((AnnouncePacket p) => p.peerId == a.peerId).length, 1);

        // 再投一条篡改了签名的。
        final int badBefore = serviceB.rejected.badSignature;
        final AnnouncePacket bad = good.withSignature(
          corruptSignature(good.signature),
        );
        expect(
          serviceA.debugSendTo(encodeAnnounceFrame(bad), portB),
          isTrue,
        );
        await _waitFor(
          () => serviceB.rejected.badSignature > badBefore,
          const Duration(seconds: 5),
        );

        // 核心断言：验签失败**不得** upsert，**不得**进流。
        expect(serviceB.rejected.badSignature, badBefore + 1);
        expect(sinkB.countFor(a.peerId), 1, reason: '坏包绝不能 upsert');
        expect(
          seen.where((AnnouncePacket p) => p.peerId == a.peerId).length,
          1,
          reason: '坏包绝不能进 incoming 流',
        );
      } finally {
        await sub.cancel();
        await serviceA.stop();
        await serviceB.stop();
      }
    });

    test('公钥表里没有对方 → 无法验签 → 丢弃计数，不 upsert', () async {
      final DeviceIdentityImpl a = identityA();
      final DeviceIdentityImpl b = identityB();
      final int portA = await pickFreeUdpPort();
      final int portB = await pickFreeUdpPort();

      final RecordingSink sinkB = RecordingSink();
      // 故意不登记 A 的公钥。
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
      )..publicKeyLookup = FakeKeyLookup();

      try {
        await serviceA.start();
        await serviceB.start();
        final AnnouncePacket good = await serviceA.buildSignedPacket();
        serviceA.debugSendTo(encodeAnnounceFrame(good), portB);

        await _waitFor(
          () => serviceB.rejected.badSignature > 0,
          const Duration(seconds: 5),
        );
        expect(serviceB.rejected.badSignature, 1);
        expect(sinkB.upserted, isEmpty);
      } finally {
        await serviceA.stop();
        await serviceB.stop();
      }
    });

    test('畸形包计入 malformed，且不打断接收循环', () async {
      final DeviceIdentityImpl b = identityB();
      final int portB = await pickFreeUdpPort();
      final RecordingSink sinkB = RecordingSink();
      final AnnounceServiceImpl serviceB = AnnounceServiceImpl(
        identity: b,
        serverPort: 47879,
        shareCountProvider: FakeShareCount(0),
        port: portB,
        sink: sinkB,
        clock: newFakeClock().now,
      )..publicKeyLookup = FakeKeyLookup();

      // 用一个真实 socket 往 B 的端口灌垃圾。
      try {
        await serviceB.start();
        final int malformedBefore = serviceB.rejected.malformed;

        final AnnounceServiceImpl sender = AnnounceServiceImpl(
          identity: identityA(),
          serverPort: 47878,
          shareCountProvider: FakeShareCount(0),
          port: await pickFreeUdpPort(),
          clock: newFakeClock().now,
        );
        await sender.start();
        try {
          sender.debugSendTo(Uint8List.fromList(<int>[0xff, 0x00, 0x13]), portB);
          sender.debugSendTo(
            Uint8List.fromList(utf8.encode('{"k":"zzz"}')),
            portB,
          );
        } finally {
          await sender.stop();
        }

        await _waitFor(
          () => serviceB.rejected.malformed > malformedBefore,
          const Duration(seconds: 5),
        );
        expect(serviceB.rejected.malformed, greaterThan(malformedBefore));
        expect(sinkB.upserted, isEmpty);
        expect(serviceB.isRunning, isTrue, reason: '垃圾包不得打断接收');
      } finally {
        await serviceB.stop();
      }
    });
  });

  group('自己过滤', () {
    test('收到自己发的公告 → 计入 fromSelf，不进流、不 upsert', () async {
      final DeviceIdentityImpl a = identityA();
      final int port = await pickFreeUdpPort();
      final RecordingSink sink = RecordingSink();
      final FakeKeyLookup keys = FakeKeyLookup()
        ..register(a.peerId, a.publicKey);

      final AnnounceServiceImpl service = AnnounceServiceImpl(
        identity: a,
        serverPort: 47878,
        shareCountProvider: FakeShareCount(1),
        port: port,
        sink: sink,
        clock: newFakeClock().now,
      )..publicKeyLookup = keys;

      final List<AnnouncePacket> seen = <AnnouncePacket>[];
      final StreamSubscription<AnnouncePacket> sub =
          service.watchIncoming().listen(seen.add);

      try {
        await service.start();
        final AnnouncePacket signed = await service.buildSignedPacket();
        service.debugSendTo(encodeAnnounceFrame(signed), port);

        await _waitFor(
          () => service.rejected.fromSelf > 0,
          const Duration(seconds: 5),
        );
        expect(service.rejected.fromSelf, greaterThan(0));
        expect(seen, isEmpty, reason: 'watchIncoming 必须过滤自己');
        expect(sink.upserted, isEmpty);
      } finally {
        await sub.cancel();
        await service.stop();
      }
    });
  });

  group('probe 即时应答', () {
    test('A 发 probe → B 立即回公告，不等心跳周期', () async {
      final DeviceIdentityImpl a = identityA();
      final DeviceIdentityImpl b = identityB();
      final int portA = await pickFreeUdpPort();
      final int portB = await pickFreeUdpPort();

      final FakeKeyLookup keysA = FakeKeyLookup()
        ..register(b.peerId, b.publicKey);
      final AnnounceServiceImpl serviceA = AnnounceServiceImpl(
        identity: a,
        serverPort: 47878,
        shareCountProvider: FakeShareCount(0),
        port: portA,
        clock: newFakeClock().now,
      )..publicKeyLookup = keysA;
      final AnnounceServiceImpl serviceB = AnnounceServiceImpl(
        identity: b,
        serverPort: 47879,
        shareCountProvider: FakeShareCount(4),
        // B 的安��周期是 30s（idle 未设分享时）——我们在下面证明回包不等它。
        port: portB,
        clock: newFakeClock().now,
      );

      final Completer<AnnouncePacket> reply = Completer<AnnouncePacket>();
      final StreamSubscription<AnnouncePacket> sub =
          serviceA.watchIncoming().listen((AnnouncePacket p) {
        if (!reply.isCompleted && p.peerId == b.peerId) {
          reply.complete(p);
        }
      });

      try {
        await serviceA.start();
        await serviceB.start();

        final Stopwatch stopwatch = Stopwatch()..start();
        final Uint8List probeFrame = encodeProbeFrame(
          peerId: a.peerId,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );
        expect(serviceA.debugSendTo(probeFrame, portB), isTrue);

        final AnnouncePacket got =
            await reply.future.timeout(const Duration(seconds: 5));
        stopwatch.stop();
        expect(got.peerId, b.peerId);
        expect(got.shareCount, 4);
        // 心跳周期是 10s/30s；即时回包必须显著快于此。
        expect(
          stopwatch.elapsed,
          lessThan(const Duration(seconds: 3)),
          reason: 'probe 必须在心跳周期之前就回包，实测 ${stopwatch.elapsed}',
        );
      } finally {
        await sub.cancel();
        await serviceA.stop();
        await serviceB.stop();
      }
    });
  });

  group('端口占用降级', () {
    test('端口被独占占住 → 不崩，降级为只发不收并记录原因', () async {
      final int port = await pickFreeUdpPort();
      // 真实现场：别的程序用独占方式绑了这个端口。
      //
      // 实测（Windows）：两边都 reuseAddress:true 时是可以同时绑上的；
      // 只有先独占绑（reuseAddress:false）之后，第二个带 reuse 的绑定才会
      // 以 errno 10013 失败。生产里 UdpChannel 保持 reuseAddress:true
      // 是为了组播接收可靠，因此「端口被占」的真实触发条件就是这种独占占用。
      final RawDatagramSocket squatter = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: false,
      );

      final AnnounceServiceImpl service = AnnounceServiceImpl(
        identity: identityB(),
        serverPort: 47879,
        shareCountProvider: FakeShareCount(0),
        port: port,
        clock: newFakeClock().now,
      );
      try {
        await service.start();
        expect(service.isRunning, isTrue, reason: '端口被占不得崩溃');
        expect(service.isSendOnly, isTrue, reason: '应降级为只发不收');
        expect(service.degradedReason, isNotEmpty, reason: '必须记录原因');

        // 降级后仍必须能发（用系统分配的临时端口出包）。
        final SendReport? report = await service.announceNow();
        expect(report, isNotNull);
        expect(report!.delivered, isTrue, reason: '降级仍必须能发');
      } finally {
        await service.stop();
        squatter.close();
      }
    });
  });
}

/// 轮询等待条件成立；超时抛 TestFailure 而不是静默返回。
Future<void> _waitFor(
  bool Function() condition,
  Duration timeout, {
  Duration interval = const Duration(milliseconds: 20),
}) async {
  final Stopwatch watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > timeout) {
      throw TestFailure('等待超时（${timeout.inSeconds}s）：条件始终未成立');
    }
    await Future<void>.delayed(interval);
  }
}
