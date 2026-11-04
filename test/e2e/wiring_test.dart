// SPDX-License-Identifier: GPL-3.0-only

/// Lead 侧验收：发现服务真的能驱动「附近的人」，且传输解析真的能落到对端地址。
///
/// 这两条是接线层的关键：没有它们，UI 永远空白、下载永远没有地址。
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/discovery/announce_service_impl.dart';
import 'package:lan_simple_file/core/discovery/discovery_service_impl.dart';
import 'package:lan_simple_file/core/discovery/peer_activity_tracker.dart';
import 'package:lan_simple_file/core/identity/device_identity_impl.dart';
import 'package:lan_simple_file/core/transfer/store_target_resolver.dart';

DeviceIdentityImpl identityOf(int seed) => DeviceIdentityImpl.fromSeed(
      Uint8List.fromList(List<int>.generate(32, (int i) => (i * 7 + seed) & 0xff)),
    );

AnnouncePacket packetOf(PeerId peer, {String name = '邻居', int port = 47778}) =>
    AnnouncePacket(
      version: LanFileConstants.protocolVersion,
      peerId: peer,
      name: name,
      avatarHash: '',
      port: port,
      ip: '192.168.1.42',
      shareCount: 3,
      capabilities: const <String>{'chat'},
      mode: 'serving',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      signature: 'sig',
    );

void main() {
  group('发现服务：附近的人', () {
    test('空表时仍返回自己一条（不是完全空白）', () async {
      final DeviceIdentityImpl me = identityOf(1);
      final PeerActivityTracker tracker = PeerActivityTracker(clock: DateTime.now);
      final AnnounceServiceImpl announce = AnnounceServiceImpl(
        identity: me,
        serverPort: 47778,
        shareCountProvider: const ZeroShareCountProvider(),
        port: 0, // 测试不占用真实 UDP 端口
      );
      final DiscoveryServiceImpl svc = DiscoveryServiceImpl(
        announce: announce,
        tracker: tracker,
        identity: me,
      );
      await svc.refresh();
      final List<PeerView> peers = await svc.watchPeers().first;
      expect(peers.length, 1, reason: '至少要有自己');
      expect(peers.single.peerId, me.peerId);
      expect(peers.single.online, isTrue);
      await svc.dispose();
    });

    test('收到公告后出现在列表里，且带着名字与分享数', () async {
      final DeviceIdentityImpl me = identityOf(2);
      final DeviceIdentityImpl other = identityOf(9);
      final PeerActivityTracker tracker = PeerActivityTracker(clock: DateTime.now);
      // 直接往 tracker 里塞一条，模拟收到公告（避免依赖真实 UDP）
      tracker.touch(packetOf(other.peerId, name: '客厅 NAS', port: 50001));

      final AnnounceServiceImpl announce = AnnounceServiceImpl(
        identity: me,
        serverPort: 47778,
        shareCountProvider: const ZeroShareCountProvider(),
        port: 0,
      );
      final DiscoveryServiceImpl svc = DiscoveryServiceImpl(
        announce: announce,
        tracker: tracker,
        identity: me,
      );
      await svc.refresh();
      final List<PeerView> peers = await svc.watchPeers().first;
      expect(peers.length, 2);
      final PeerView found =
          peers.firstWhere((PeerView p) => p.peerId == other.peerId);
      expect(found.name, '客厅 NAS');
      expect(found.shareCount, 3);
      expect(found.online, isTrue);
      expect(peers.first.peerId, me.peerId, reason: '自己排首位');
      await svc.dispose();
    });
  });

  group('传输解析：把 shareId 拼成对端地址', () {
    test('在线对端给出完整 URL（host:port 与路径正确）', () async {
      final DeviceIdentityImpl me = identityOf(3);
      final DeviceIdentityImpl other = identityOf(11);
      final PeerActivityTracker tracker = PeerActivityTracker(clock: DateTime.now);
      tracker.touch(packetOf(other.peerId, port: 50555));
      final DiscoveryServiceImpl svc = DiscoveryServiceImpl(
        announce: AnnounceServiceImpl(
          identity: me,
          serverPort: 47778,
          shareCountProvider: const ZeroShareCountProvider(),
          port: 0,
        ),
        tracker: tracker,
        identity: me,
      );
      final StoreTargetResolver resolver = StoreTargetResolver(endpoints: svc);
      final Uri uri = await resolver.resolve(
        peer: other.peerId,
        share: ShareId.parse('7Qm2xK'),
        itemKey: ItemKey.parse('a/b.txt'),
      );
      expect(uri.scheme, 'http');
      expect(uri.host, '192.168.1.42');
      expect(uri.port, 50555);
      // 路径分隔符必须保留（服务端按 * 通配取子路径），只逐段编码。
      expect(uri.path, '/s/7Qm2xK/f/a/b.txt');
      await svc.dispose();
    });

    test('未知对端必须抛 providerOffline（不许猜地址）', () async {
      final DeviceIdentityImpl me = identityOf(4);
      final DiscoveryServiceImpl svc = DiscoveryServiceImpl(
        announce: AnnounceServiceImpl(
          identity: me,
          serverPort: 47778,
          shareCountProvider: const ZeroShareCountProvider(),
          port: 0,
        ),
        tracker: PeerActivityTracker(clock: DateTime.now),
        identity: me,
      );
      final StoreTargetResolver resolver = StoreTargetResolver(endpoints: svc);
      await expectLater(
        resolver.resolve(
          peer: PeerId.parse('p_zzzzzzzzzzzzz'),
          share: ShareId.parse('7Qm2xK'),
          itemKey: ItemKey.parse('a.txt'),
        ),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.providerOffline,
          ),
        ),
      );
      await svc.dispose();
    });

    test('公网地址必须被拒（局域网明文边界）', () async {
      // 用只返回公网地址的假 endpoints，验证 guard 真的挡住了。
      final StoreTargetResolver resolver = StoreTargetResolver(
        endpoints: _PublicEndpointSource(),
      );
      await expectLater(
        resolver.resolve(
          peer: PeerId.parse('p_zzzzzzzzzzzzz'),
          share: ShareId.parse('7Qm2xK'),
          itemKey: ItemKey.parse('a.txt'),
        ),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.accessDenied,
          ),
        ),
      );
    });
  });
}

/// 故意返回公网地址，用于验证 guard 必须拦下。
final class _PublicEndpointSource implements PeerEndpointSource {
  @override
  Future<({String host, int port})?> findEndpoint(PeerId peer) async =>
      (host: '8.8.8.8', port: 80);
}