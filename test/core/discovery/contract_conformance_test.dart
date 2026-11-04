// SPDX-License-Identifier: GPL-3.0-only

/// 契约对齐用例：验证 AnnounceServiceImpl 真的实现了扩展后的契约接口。
///
/// 这一组专门防「analyze 通过但语义没接上」——比如 setter 写成构造参数、
/// rejected 返回了私有类型、未接线时没有安全默认。
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/discovery/announce_codec.dart';
import 'package:lan_simple_file/core/discovery/announce_service_impl.dart';
import 'package:lan_simple_file/core/identity/device_identity_impl.dart';

import 'discovery_test_support.dart';

DeviceIdentityImpl identityA() =>
    DeviceIdentityImpl.fromSeed(Uint8List.fromList(List<int>.generate(32, (int i) => i)));

DeviceIdentityImpl identityB() => DeviceIdentityImpl.fromSeed(
      Uint8List.fromList(List<int>.generate(32, (int i) => 0x20 + i)),
    );

void main() {
  group('契约接口对齐', () {
    test('AnnounceServiceImpl 可赋给契约类型 AnnounceService', () {
      final AnnounceService service = AnnounceServiceImpl(
        identity: identityA(),
        serverPort: 47878,
        shareCountProvider: FakeShareCount(0),
        clock: newFakeClock().now,
      );
      // 能编译即证明 implements 关系成立。
      expect(service, isNotNull);
      expect(service, isA<AnnounceServiceImpl>());
    });

    test('rejected 的静态类型是契约的 RejectedDatagramCounter', () {
      final AnnounceServiceImpl impl = AnnounceServiceImpl(
        identity: identityA(),
        serverPort: 47878,
        shareCountProvider: FakeShareCount(0),
        clock: newFakeClock().now,
      );
      // 声明成契约类型：若返回私有类型这行会编译失败。
      final RejectedDatagramCounter counter = impl.rejected;
      expect(counter.badSignature, 0);
      expect(counter.malformed, 0);
      expect(counter.fromSelf, 0);
      expect(counter.unknownPeerId, 0);
      expect(counter.recentReasons, isEmpty);
    });

    test('peerSink 是可变 setter：可后挂载、可替换、置 null 回落 no-op', () {
      final AnnounceServiceImpl impl = AnnounceServiceImpl(
        identity: identityA(),
        serverPort: 47878,
        shareCountProvider: FakeShareCount(0),
        clock: newFakeClock().now,
      );
      expect(impl.peerSink, isA<NoopPeerUpsertSink>(),
          reason: '默认必须是不写库的 no-op，不能假装写');

      final RecordingSink sink1 = RecordingSink();
      impl.peerSink = sink1;
      expect(identical(impl.peerSink, sink1), isTrue);

      final RecordingSink sink2 = RecordingSink();
      impl.peerSink = sink2;
      expect(identical(impl.peerSink, sink2), isTrue, reason: '必须可替换');

      impl.peerSink = null;
      expect(impl.peerSink, isA<NoopPeerUpsertSink>(),
          reason: '置 null 必须回落 no-op，不能留空引用');
    });

    test('publicKeyLookup 是可变 setter，可后挂载', () {
      final AnnounceServiceImpl impl = AnnounceServiceImpl(
        identity: identityA(),
        serverPort: 47878,
        shareCountProvider: FakeShareCount(0),
        clock: newFakeClock().now,
      );
      expect(impl.publicKeyLookup, isNull, reason: '未接线为 null');

      final FakeKeyLookup lookup = FakeKeyLookup();
      impl.publicKeyLookup = lookup;
      expect(identical(impl.publicKeyLookup, lookup), isTrue);

      impl.publicKeyLookup = null;
      expect(impl.publicKeyLookup, isNull);
    });

    test('未降级时 degradedReason 为 null、isSendOnly 为 false', () {
      final AnnounceServiceImpl impl = AnnounceServiceImpl(
        identity: identityA(),
        serverPort: 47878,
        shareCountProvider: FakeShareCount(0),
        clock: newFakeClock().now,
      );
      expect(impl.degradedReason, isNull);
      expect(impl.isSendOnly, isFalse);
    });

    test('buildSignedPacket 已暴露到契约公开面', () async {
      final AnnounceService service = AnnounceServiceImpl(
        identity: identityA(),
        serverPort: 47878,
        shareCountProvider: FakeShareCount(0),
        clock: newFakeClock().now,
      );
      // 通过契约类型调用：能编译即证明确实在接口上。
      final AnnouncePacket signed = await service.buildSignedPacket();
      expect(signed.signature, isNotEmpty);
      expect(service.buildPacket().signature, isEmpty,
          reason: 'buildPacket 允许未签名（契约注释明确）');
    });
  });

  group('未接线时的安全默认', () {
    test('未注入 publicKeyLookup → 公告验签失败被丢弃，绝不 upsert', () async {
      final DeviceIdentityImpl a = identityA();
      final DeviceIdentityImpl b = identityB();
      final int portA = await pickFreeUdpPort();
      final int portB = await pickFreeUdpPort();

      final RecordingSink sinkB = RecordingSink();
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
      );

      try {
        await serviceA.start();
        await serviceB.start();
        expect(serviceB.publicKeyLookup, isNull);

        serviceA.debugSendTo(
          encodeAnnounceFrame(await serviceA.buildSignedPacket()),
          portB,
        );
        await waitForDiscovery(
          () => serviceB.rejected.badSignature > 0,
          const Duration(seconds: 5),
        );

        expect(serviceB.rejected.badSignature, 1,
            reason: '未接线 → 无法验签 → 必须计入 badSignature');
        expect(sinkB.upserted, isEmpty, reason: '绝不能 upsert');
      } finally {
        await serviceA.stop();
        await serviceB.stop();
      }
    });
  });

  group('后挂载 sink 必须真正生效（App 组装顺序）', () {
    test('service 已 start 后才挂 sink → 后续验签通过的公告进到这个 sink', () async {
      final DeviceIdentityImpl a = identityA();
      final DeviceIdentityImpl b = identityB();
      final int portA = await pickFreeUdpPort();
      final int portB = await pickFreeUdpPort();

      final AnnounceServiceImpl serviceA = AnnounceServiceImpl(
        identity: a,
        serverPort: 47878,
        shareCountProvider: FakeShareCount(1),
        port: portA,
        clock: newFakeClock().now,
      );
      // B 先起，此时既没有 keys 也没有 sink。
      final AnnounceServiceImpl serviceB = AnnounceServiceImpl(
        identity: b,
        serverPort: 47879,
        shareCountProvider: FakeShareCount(0),
        port: portB,
        clock: newFakeClock().now,
      );

      try {
        await serviceA.start();
        await serviceB.start();

        // 阶段一：未接线 → 包被丢弃。
        serviceA.debugSendTo(
          encodeAnnounceFrame(await serviceA.buildSignedPacket()),
          portB,
        );
        await waitForDiscovery(
          () => serviceB.rejected.badSignature >= 1,
          const Duration(seconds: 5),
        );

        // 阶段二：模拟 App 稍后完成组装，后挂 keys + sink。
        final RecordingSink lateSink = RecordingSink();
        final FakeKeyLookup lateKeys = FakeKeyLookup()
          ..register(a.peerId, a.publicKey);
        serviceB.publicKeyLookup = lateKeys;
        serviceB.peerSink = lateSink;

        final int badBefore = serviceB.rejected.badSignature;
        serviceA.debugSendTo(
          encodeAnnounceFrame(await serviceA.buildSignedPacket()),
          portB,
        );
        await waitForDiscovery(
          () => lateSink.countFor(a.peerId) == 1,
          const Duration(seconds: 5),
        );

        expect(lateSink.countFor(a.peerId), 1,
            reason: '后挂载的 sink 必须真的收到 upsert');
        expect(serviceB.rejected.badSignature, badBefore,
            reason: '接线后不得再计入验签失败');
      } finally {
        await serviceA.stop();
        await serviceB.stop();
      }
    });

    test('换 sink 后，新 sink 收到后续包，旧 sink 不再增长', () async {
      final DeviceIdentityImpl a = identityA();
      final DeviceIdentityImpl b = identityB();
      final int portA = await pickFreeUdpPort();
      final int portB = await pickFreeUdpPort();

      final RecordingSink firstSink = RecordingSink();
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
        sink: firstSink,
        clock: newFakeClock().now,
      )..publicKeyLookup = keysB;

      try {
        await serviceA.start();
        await serviceB.start();

        serviceA.debugSendTo(
          encodeAnnounceFrame(await serviceA.buildSignedPacket()),
          portB,
        );
        await waitForDiscovery(
          () => firstSink.countFor(a.peerId) == 1,
          const Duration(seconds: 5),
        );

        final RecordingSink secondSink = RecordingSink();
        serviceB.peerSink = secondSink;
        final int firstCount = firstSink.countFor(a.peerId);

        serviceA.debugSendTo(
          encodeAnnounceFrame(await serviceA.buildSignedPacket()),
          portB,
        );
        await waitForDiscovery(
          () => secondSink.countFor(a.peerId) == 1,
          const Duration(seconds: 5),
        );

        expect(secondSink.countFor(a.peerId), 1, reason: '新 sink 必须生效');
        expect(firstSink.countFor(a.peerId), firstCount,
            reason: '旧 sink 不得再被写入');
      } finally {
        await serviceA.stop();
        await serviceB.stop();
      }
    });
  });
}
