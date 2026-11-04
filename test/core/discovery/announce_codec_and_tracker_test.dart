// SPDX-License-Identifier: GPL-3.0-only

/// 纯逻辑用例：信封编解码、上下线状态机、组播组校验。
///
/// 这一组不碰网络，纯粹验证「垃圾包不抛异常」「30s/5min 阈值」这类硬语义。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/discovery/announce_codec.dart';
import 'package:lan_simple_file/core/discovery/multicast_join.dart';
import 'package:lan_simple_file/core/discovery/peer_activity_tracker.dart';

import 'discovery_test_support.dart';

AnnouncePacket samplePacket({
  required PeerId peerId,
  String name = 'YG',
  String mode = 'idle',
  int shareCount = 0,
  int port = 47778,
  int ts = 1767225600000,
  String sig = 'AA',
}) =>
    AnnouncePacket(
      version: LanFileConstants.protocolVersion,
      peerId: peerId,
      name: name,
      avatarHash: 'sha256:ab12',
      port: port,
      ip: '192.168.1.23',
      shareCount: shareCount,
      capabilities: <String>{'chat', 'offer'},
      mode: mode,
      timestamp: ts,
      signature: sig,
    );

BytesBuilder _bytesOf(String text) =>
    BytesBuilder()..add(utf8.encode(text));

void main() {
  group('announce_codec', () {
    final PeerId peer = PeerId.parse('p_aaaaaaaaaaaaa');

    test('公告编码后能原样解回（含 caps 排序）', () {
      final AnnouncePacket packet = samplePacket(peerId: peer);
      final Uint8List frame = encodeAnnounceFrame(packet);
      final DecodedDatagram decoded = decodeDatagram(frame);
      expect(decoded, isA<DecodedAnnounce>());
      final AnnouncePacket back =
          (decoded as DecodedAnnounce).envelope.packet;
      expect(back.peerId, peer);
      expect(back.name, 'YG');
      expect(back.port, 47778);
      expect(back.shareCount, 0);
      expect(back.mode, 'idle');
      expect(back.signature, 'AA');
      expect(back.capabilities, <String>{'chat', 'offer'});
      // 键序固定：caps 在签名前被排序。
      expect(back.signablePayload().keys.toList(), <String>[
        'v',
        'id',
        'name',
        'av',
        'port',
        'ip',
        'shareCount',
        'caps',
        'mode',
        'ts',
      ]);
    });

    test('probe 编码可解回，且能区分请求与应答', () {
      final Uint8List request = encodeProbeFrame(
        peerId: peer,
        timestamp: 1234,
      );
      final DecodedDatagram decodedRequest = decodeDatagram(request);
      expect(decodedRequest, isA<DecodedProbe>());
      final ProbeFrame frame = (decodedRequest as DecodedProbe).frame;
      expect(frame.peerId, peer);
      expect(frame.timestamp, 1234);
      expect(frame.isReply, isFalse);

      final Uint8List reply = encodeProbeFrame(
        peerId: peer,
        timestamp: 1234,
        isReply: true,
      );
      final DecodedProbe decodedReply = decodeDatagram(reply) as DecodedProbe;
      expect(decodedReply.frame.isReply, isTrue);
    });

    test('畸形输入一律 DecodedInvalid，绝不抛异常', () {
      final List<Uint8List> bad = <Uint8List>[
        Uint8List(0),
        Uint8List.fromList(<int>[0xff, 0xfe, 0xfd]),
        _bytesOf('not json').toBytes(),
        _bytesOf('[]').toBytes(),
        _bytesOf('123').toBytes(),
        _bytesOf('{"k":"a"}').toBytes(),
        _bytesOf('{"k":"zzz"}').toBytes(),
        _bytesOf('{"k":"p"}').toBytes(),
        _bytesOf('{"k":"a","v":"2","id":"p_aaaaaaaaaaaaa","port":1,"ts":1,"sig":"AA"}')
            .toBytes(),
        _bytesOf('{"k":"a","v":2,"id":"bad","port":1,"ts":1,"sig":"AA"}')
            .toBytes(),
      ];
      for (final Uint8List bytes in bad) {
        final DecodedDatagram decoded = decodeDatagram(bytes);
        expect(decoded, isA<DecodedInvalid>(),
            reason: '应当被判为畸形: ${utf8.decode(bytes, allowMalformed: true)}');
      }
    });

    test('probe 缺 id 时 peerId 为 null，但仍能解析出 ts', () {
      final DecodedDatagram decoded =
          decodeDatagram(_bytesOf('{"k":"p","ts":99}').toBytes());
      expect(decoded, isA<DecodedProbe>());
      final ProbeFrame frame = (decoded as DecodedProbe).frame;
      expect(frame.peerId, isNull);
      expect(frame.timestamp, 99);
    });

    test('信封类型字段 k 参与判别，不会被公告自身字段覆盖', () {
      // 带 k 的公告不会被误当成 probe。
      final Uint8List frame = encodeAnnounceFrame(samplePacket(peerId: peer));
      expect(decodeDatagram(frame), isA<DecodedAnnounce>());
    });
  });

  group('PeerActivityTracker 状态机', () {
    final PeerId a = PeerId.parse('p_aaaaaaaaaaaaa');
    final PeerId b = PeerId.parse('p_bbbbbbbbbbbbb');

    test('收到公告即 online', () {
      final FakeClock clock = newFakeClock();
      final PeerActivityTracker tracker = PeerActivityTracker(clock: clock.now);
      final PeerTouchResult result =
          tracker.touch(samplePacket(peerId: a));

      expect(result.peer.liveness, PeerLiveness.online);
      expect(tracker.onlineCount, 1);
      expect(tracker.contains(a), isTrue);
      expect(result.removed, isEmpty);
    });

    test('推进 31 秒 → offline；推进 5 分 1 秒 → 移除', () {
      final FakeClock clock = newFakeClock();
      final PeerActivityTracker tracker = PeerActivityTracker(clock: clock.now);
      tracker.touch(samplePacket(peerId: a));
      expect(tracker[a]!.liveness, PeerLiveness.online);

      // 29 秒：还 online（阈值是 >=30s 才 offline）。
      clock.advance(const Duration(seconds: 29));
      expect(tracker.sweep(), isEmpty);
      expect(tracker[a]!.liveness, PeerLiveness.online);

      // 31 秒：offline，但还在表里。
      clock.advance(const Duration(seconds: 2));
      expect(tracker.sweep(), isEmpty);
      expect(tracker[a]!.liveness, PeerLiveness.offline);
      expect(tracker.contains(a), isTrue);
      expect(tracker.onlineCount, 0);

      // 推进到 5 分 1 秒：移除，并从表中消失。
      clock.advance(const Duration(minutes: 4, seconds: 30));
      final List<TrackedPeer> removed = tracker.sweep();
      expect(removed.length, 1);
      expect(removed.single.packet.peerId, a);
      expect(removed.single.liveness, PeerLiveness.removed);
      expect(tracker.contains(a), isFalse);
      expect(tracker.peers, isEmpty);
    });

    test('offline 后再次收到公告回到 online', () {
      final FakeClock clock = newFakeClock();
      final PeerActivityTracker tracker = PeerActivityTracker(clock: clock.now);
      tracker.touch(samplePacket(peerId: a));
      clock.advance(const Duration(seconds: 45));
      tracker.sweep();
      expect(tracker[a]!.liveness, PeerLiveness.offline);

      final PeerTouchResult revived = tracker.touch(samplePacket(peerId: a));
      expect(revived.peer.liveness, PeerLiveness.online);
      expect(tracker.onlineCount, 1);
    });

    test('移除只返回一次，不重复上报', () {
      final FakeClock clock = newFakeClock();
      final PeerActivityTracker tracker = PeerActivityTracker(clock: clock.now);
      tracker.touch(samplePacket(peerId: a));
      clock.advance(const Duration(minutes: 10));
      expect(tracker.sweep().length, 1);
      expect(tracker.sweep(), isEmpty);
    });

    test('多个 peer 各自独立计时', () {
      final FakeClock clock = newFakeClock();
      final PeerActivityTracker tracker = PeerActivityTracker(clock: clock.now);
      tracker.touch(samplePacket(peerId: a));
      clock.advance(const Duration(seconds: 20));
      tracker.touch(samplePacket(peerId: b));

      clock.advance(const Duration(seconds: 15)); // a 已 idle 35s，b 只有 15s
      tracker.sweep();
      expect(tracker[a]!.liveness, PeerLiveness.offline);
      expect(tracker[b]!.liveness, PeerLiveness.online);
      expect(tracker.onlineCount, 1);
    });

    test('公告内容被最新一条覆盖，firstSeen 保持', () {
      final FakeClock clock = newFakeClock();
      final PeerActivityTracker tracker = PeerActivityTracker(clock: clock.now);
      final DateTime first = clock.now();
      tracker.touch(samplePacket(peerId: a, name: '旧名字', shareCount: 0));
      clock.advance(const Duration(seconds: 5));
      tracker.touch(samplePacket(peerId: a, name: '新名字', shareCount: 7));

      expect(tracker[a]!.packet.name, '新名字');
      expect(tracker[a]!.packet.shareCount, 7);
      expect(tracker[a]!.firstSeen, first);
      expect(tracker[a]!.lastSeen, clock.now());
    });

    test('toPeerView 把 liveness 映射成 online 布尔', () {
      final FakeClock clock = newFakeClock();
      final PeerActivityTracker tracker = PeerActivityTracker(clock: clock.now);
      tracker.touch(samplePacket(peerId: a, shareCount: 3));
      PeerView view = tracker[a]!.toPeerView();
      expect(view.online, isTrue);
      expect(view.shareCount, 3);

      clock.advance(const Duration(seconds: 40));
      tracker.sweep();
      view = tracker[a]!.toPeerView();
      expect(view.online, isFalse);
    });

    test('clear 清空全部记录', () {
      final FakeClock clock = newFakeClock();
      final PeerActivityTracker tracker = PeerActivityTracker(clock: clock.now);
      tracker.touch(samplePacket(peerId: a));
      tracker.touch(samplePacket(peerId: b));
      expect(tracker.peers.length, 2);
      tracker.clear();
      expect(tracker.peers, isEmpty);
    });
  });

  group('MulticastGroup', () {
    test('契约默认组能解析且通过 isMulticast', () {
      final MulticastGroup group = MulticastGroup.defaultGroup();
      expect(group.address.address, LanFileConstants.multicastGroup);
      expect(group.port, LanFileConstants.udpPort);
      expect(group.address.isMulticast, isTrue);
    });

    test('非组播地址抛 invalidArgument', () {
      expect(
        () => MulticastGroup.parse('192.168.1.1', 47777),
        throwsA(isA<LanFileException>().having(
          (LanFileException e) => e.code,
          'code',
          LanFileErrorCode.invalidArgument,
        )),
      );
    });

    test('端口越界抛 invalidArgument', () {
      expect(
        () => MulticastGroup.parse(LanFileConstants.multicastGroup, 0),
        throwsA(isA<LanFileException>()),
      );
      expect(
        () => MulticastGroup.parse(LanFileConstants.multicastGroup, 70000),
        throwsA(isA<LanFileException>()),
      );
    });
  });
}
