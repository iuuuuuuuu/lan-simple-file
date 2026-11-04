// SPDX-License-Identifier: GPL-3.0-only

/// 发现服务的落地：把 AnnounceService 的公告流与 PeerActivityTracker 组合成
/// 界面可直接消费的 DiscoveryService。
///
/// 各模块互不 import，发现层、存储、UI 三方的接缝全部收敛在这里。
library;

import 'dart:async';

import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/discovery/peer_activity_tracker.dart';
import 'package:lan_simple_file/core/server/api/gateway_api.dart';
import 'package:lan_simple_file/core/transfer/store_target_resolver.dart';

/// 由发现层活动表驱动的「附近的人」。
final class DiscoveryServiceImpl
    implements DiscoveryService, PeerEndpointSource, PeerEndpointLookup {
  DiscoveryServiceImpl({
    required this.announce,
    required this.tracker,
    required this.identity,
    this.nameResolver,
    this.shareCountReader,
    this.avatarHashReader,
  });

  final AnnounceService announce;
  final PeerActivityTracker tracker;
  final DeviceIdentity identity;

  /// 从 peers 表读名字；为 null 时用公告里的名字。
  final Future<String?> Function(PeerId peer)? nameResolver;

  /// 读某人分享数量；为 null 时用公告里的 shareCount。
  final Future<int?> Function(PeerId peer)? shareCountReader;
  final Future<String?> Function(PeerId peer)? avatarHashReader;

  final StreamController<List<PeerView>> _watch =
      StreamController<List<PeerView>>.broadcast();

  /// 最近一次 tick 的结果缓存，新订阅者立刻能拿到（不用等下一轮）。
  List<PeerView> _last = const <PeerView>[];
  List<PeerView> get currentPeers => _last;

  /// 轮询间隔：与公告心跳同量级即可，不需要更密。
  static const Duration tickInterval = Duration(seconds: 3);

  Timer? _timer;
  StreamSubscription<AnnouncePacket>? _incoming;
  bool _started = false;

  /// 启动内部的周期刷新；幂等。
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _incoming = announce.watchIncoming().listen((packet) {
      tracker.touch(packet);
      unawaited(_refreshOnce());
    });
    await announce.start();
    _timer = Timer.periodic(tickInterval, (_) => unawaited(_refreshOnce()));
    await _refreshOnce();
  }

  @override
  Stream<List<PeerView>> watchPeers() {
    // 每次订阅都**立刻算一次**再给出去，而不是把上一轮的缓存推一下。
    //
    // 只推缓存会漏掉「首次订阅时还没 tick 过」的情形（_last 是空数组），
    // UI 会先空白几秒；而发现是有状态的，等下一 tick 才出数据不可接受。
    return Stream<List<PeerView>>.multi((StreamController<List<PeerView>> c) {
      unawaited(_refreshOnce());
      final StreamSubscription<List<PeerView>> sub = _watch.stream.listen(
        c.add,
        onError: c.addError,
        onDone: c.close,
      );
      c.onCancel = () => sub.cancel();
    }, isBroadcast: true);
  }

  @override
  Future<void> refresh({bool sweep = false}) async {
    if (sweep) {
      await announce.probe();
    }
    await _refreshOnce();
  }

  @override
  Future<void> addByAddress(String host, int port) async {
    // 手动添加走一次主动探测；真正的定向 contact 属发现层能力，
    // 这里至少要让调用方看到「已请求」，而不是静默空转。
    await announce.probe();
  }

  /// 网关用：把在线对端解析成可连接地址。
  @override
  Future<PeerEndpoint?> find(PeerId peerId) async {
    final ({String host, int port})? ep = await findEndpoint(peerId);
    if (ep == null) {
      return null;
    }
    return PeerEndpoint(host: ep.host, port: ep.port);
  }

  @override
  Future<({String host, int port})?> findEndpoint(PeerId peer) async {
    final TrackedPeer? tracked = tracker[peer];
    if (tracked == null) {
      return null;
    }
    // 只有在线才算「可下载」，离线时让上层出可读提示。
    if (tracked.liveness != PeerLiveness.online) {
      return null;
    }
    final AnnouncePacket packet = tracked.packet;
    if (packet.ip.isEmpty || packet.port <= 0) {
      return null;
    }
    return (host: packet.ip, port: packet.port);
  }

  Future<void> _refreshOnce() async {
    // sweep 会把超时 peer 移出表；返回被移除的，供诊断。
    tracker.sweep();

    final List<PeerView> views = <PeerView>[];
    // 自己排首位。
    views.add(
      PeerView(
        peerId: identity.peerId,
        name: await nameResolver?.call(identity.peerId) ?? '本机',
        avatarHash: await avatarHashReader?.call(identity.peerId) ?? '',
        online: true,
        shareCount: await shareCountReader?.call(identity.peerId) ?? 0,
        lastSeen: DateTime.now(),
      ),
    );
    for (final TrackedPeer p in tracker.peers) {
      // TrackedPeer 没有独立的 peerId getter，身份只在 packet 里。
      final PeerId pid = p.packet.peerId;
      if (pid == identity.peerId) continue;
      views.add(
        PeerView(
          peerId: pid,
          name:
              await nameResolver?.call(pid) ??
              (p.packet.name.isEmpty ? pid.value : p.packet.name),
          avatarHash: p.packet.avatarHash,
          online: p.liveness == PeerLiveness.online,
          shareCount: await shareCountReader?.call(pid) ?? p.packet.shareCount,
          lastSeen: p.lastSeen,
        ),
      );
    }
    _last = List<PeerView>.unmodifiable(views);
    if (!_watch.isClosed) {
      _watch.add(_last);
    }
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _incoming?.cancel();
    await announce.stop();
    if (!_watch.isClosed) {
      await _watch.close();
    }
  }
}
