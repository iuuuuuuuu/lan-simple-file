// SPDX-License-Identifier: GPL-3.0-only

/// 发现层测试夹具：可控时钟、内存公钥表、内存 upsert 收集器、真实端口分配。
///
/// 这里**不做网络 mock**：用例一律用真实 `RawDatagramSocket` 收发，
/// 夹具只负责时间与落库口子这类非网络依赖。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/discovery/announce_service_impl.dart';
import 'package:flutter_test/flutter_test.dart';

/// 可手动推进的时钟。
final class FakeClock {
  FakeClock(this._now);

  DateTime _now;

  /// 当前时刻。
  DateTime now() => _now;

  /// 推进一段时间。
  void advance(Duration by) {
    _now = _now.add(by);
  }

  /// 直接设定时刻。
  void set(DateTime value) {
    _now = value;
  }
}

/// 固定起点的测试时钟：2026-01-01T00:00:00Z。
FakeClock newFakeClock() => FakeClock(DateTime.utc(2026, 1, 1));

/// 内存公钥表：公告里不带公钥，验签只能靠这张表。
final class FakeKeyLookup implements PublicKeyLookup {
  final Map<String, Uint8List> _keys = <String, Uint8List>{};

  /// 登记。
  void register(PeerId peerId, Uint8List publicKey) {
    _keys[peerId.value] = Uint8List.fromList(publicKey);
  }

  /// 注销。
  void forget(PeerId peerId) => _keys.remove(peerId.value);

  int get size => _keys.length;

  @override
  Future<Uint8List?> findPublicKey(PeerId peerId) async {
    final Uint8List? key = _keys[peerId.value];
    return key == null ? null : Uint8List.fromList(key);
  }
}

/// 记录所有「已验签通过」的 upsert 调用。
///
/// 验收要点：验签失败的包**不得**出现在这里。
final class RecordingSink implements PeerUpsertSink {
  final List<AnnouncePacket> upserted = <AnnouncePacket>[];

  @override
  Future<void> upsertVerifiedPeer(AnnouncePacket packet) async {
    upserted.add(packet);
  }

  /// 某个 peer 被 upsert 了几次。
  int countFor(PeerId peerId) =>
      upserted.where((AnnouncePacket p) => p.peerId == peerId).length;

  List<PeerId> get peerIds =>
      upserted.map((AnnouncePacket p) => p.peerId).toList(growable: false);

  void clear() => upserted.clear();
}

/// 固定分享数量来源。
final class FakeShareCount implements ShareCountProvider {
  FakeShareCount([this.shareCount = 0]);

  @override
  int shareCount;
}

/// 找一个当前可用的 UDP 端口：绑 0 取系统分配值后立刻释放。
///
/// 有极小概率被别的进程抢走；用例里每个实例只用一次，
/// 且绑定失败会被报到测试日志而不静默通过。
Future<int> pickFreeUdpPort() async {
  final RawDatagramSocket probe = await RawDatagramSocket.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  final int port = probe.port;
  probe.close();
  return port;
}
/// 轮询等待条件成立；超时抛 TestFailure 而不是静默放过。
///
/// 刻意不做成 `Future.delayed + 固定次数`：失败时必须让用例变红。
Future<void> waitForDiscovery(
  bool Function() condition,
  Duration timeout, {
  Duration interval = const Duration(milliseconds: 20),
}) async {
  final Stopwatch watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed > timeout) {
      throw TestFailure(
        '等待超时（${timeout.inSeconds}s）：条件始终未成立',
      );
    }
    await Future<void>.delayed(interval);
  }
}