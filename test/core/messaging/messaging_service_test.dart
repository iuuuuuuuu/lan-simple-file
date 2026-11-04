// SPDX-License-Identifier: GPL-3.0-only

/// 单聊集成测试：真实 HttpServer + 真实 WebSocket + 真实临时 SQLite。
///
/// 这里不 mock 任何一层：两实例各起一个 HttpServerHost，
/// 各自持一个 LanFileStoreImpl（磁盘文件，非内存），互连后收发。
/// 之所以坚持全真：本任务的验收本质是「跨进程可达语义」，
/// mock 掉 WS 或存储后，补拉与幂等这两个最容易出错的点就测不到了。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/identity/device_identity_impl.dart';
import 'package:lan_simple_file/core/messaging/hlc_clock.dart';
import 'package:lan_simple_file/core/messaging/messaging_service_impl.dart';
import 'package:lan_simple_file/core/messaging/ws_client_endpoint.dart';
import 'package:lan_simple_file/core/messaging/ws_hub.dart';
import 'package:lan_simple_file/core/messaging/ws_server_endpoint.dart';
import 'package:lan_simple_file/core/server/http_server_host.dart';
import 'package:lan_simple_file/core/server/router.dart';
import 'package:lan_simple_file/core/store/store_impl.dart';

/// 一台「节点」：身份 + 库 + 消息服务 + HTTP/WS 监听。
final class TestNode {
  TestNode._({
    required this.identity,
    required this.store,
    required this.service,
    required this.host,
    required this.tempDir,
  });

  final DeviceIdentityImpl identity;
  final LanFileStoreImpl store;
  final MessagingServiceImpl service;
  final HttpServerHost host;
  final Directory tempDir;

  PeerId get peer => identity.peerId;

  int get port => host.port!;

  static Future<TestNode> start(int seedByte, String name) async {
    final Directory dir =
        await Directory.systemTemp.createTemp('lsf_msg_node_');
    final File dbFile =
        File('${dir.path}${Platform.pathSeparator}db.sqlite');
    final DeviceIdentityImpl identity = DeviceIdentityImpl.fromSeed(
      // 固定种子 -> 固定 peerId，避免每次跑出不同 id 让断言难写。
      Uint8List.fromList(List<int>.generate(32, (int i) => (i * 7 + seedByte) % 256)),
    );
    final LanFileStoreImpl store =
        await LanFileStoreImpl.open(dbFile: dbFile);
    final MessagingServiceImpl service = MessagingServiceImpl(
      store: store,
      identity: identity,
      selfName: name,
      selfAvatarHash: '',
    );

    final Router router = Router();
    final HttpServerHost host =
        HttpServerHost(router: router, preferredPort: 0);
    router.get(kWsPath, (HttpRequest request) async {
      await handleWsRequest(
        request,
        service.adoptInboundLink,
        localPeerId: identity.peerId,
        localName: name,
        localAvatarHash: '',
        localCapabilities: WsFrame.all,
      );
    });
    await host.start();

    return TestNode._(
      identity: identity,
      store: store,
      service: service,
      host: host,
      tempDir: dir,
    );
  }

  /// 主动连到 [other]，并注册链路。
  Future<WsClientEndpoint> connectTo(TestNode other) async {
    final WsClientEndpoint client = WsClientEndpoint(
      host: '127.0.0.1',
      port: other.port,
      localPeerId: identity.peerId,
      localName: 'x',
      localAvatarHash: '',
      localCapabilities: WsFrame.all,
      onLinkUp: (WsLink link) async {
        await service.adoptOutboundLink(other.peer, link);
      },
    );
    await client.connect();
    return client;
  }

  Future<void> stop() async {
    await service.dispose();
    await host.stop();
    await store.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  }
}

/// 轮询等待条件成立，超时抛错（而不是死等）。
Future<void> waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  String reason = '条件未在超时内成立',
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('waitFor 超时: $reason');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late TestNode a;
  late TestNode b;
  final List<WsClientEndpoint> clients = <WsClientEndpoint>[];

  setUp(() async {
    a = await TestNode.start(11, 'A');
    b = await TestNode.start(22, 'B');
  });

  tearDown(() async {
    for (final WsClientEndpoint client in clients) {
      await client.dispose();
    }
    clients.clear();
    await a.stop();
    await b.stop();
  });

  group('threadId', () {
    test('A 对 B 与 B 对 A 生成同一 threadId', () {
      final String fromA = directThreadId(a.peer, b.peer);
      final String fromB = directThreadId(b.peer, a.peer);
      expect(fromA, fromB);
      expect(fromA.startsWith(kDirectThreadPrefix), isTrue);
      // 反解也能对上。
      expect(peerInDirectThread(fromA, a.peer), b.peer);
      expect(peerInDirectThread(fromA, b.peer), a.peer);
    });

    test('同一个 peer 与自己生成稳定 threadId（字典序幂等）', () {
      expect(directThreadId(a.peer, a.peer), directThreadId(a.peer, a.peer));
      expect(peerInDirectThread(directThreadId(a.peer, a.peer), a.peer), isNull,
          reason: '两侧都是自己时没有对端');
    });
  });

  group('互发与顺序', () {
    test('两实例互发 20 条后，双方 listMessages 顺序完全一致', () async {
      clients.add(await a.connectTo(b));
      await waitFor(() => a.service.isPeerOnline(b.peer),
          reason: 'A 应看到 B 在线');
      await waitFor(() => b.service.isPeerOnline(a.peer),
          reason: 'B 应看到 A 在线');

      final String threadA = directThreadId(a.peer, b.peer);
      final String threadB = directThreadId(b.peer, a.peer);
      expect(threadA, threadB);

      // 交替发，模拟真实聊天。
      for (int i = 0; i < 10; i++) {
        await a.service.sendText(threadA, 'A-$i');
        await b.service.sendText(threadB, 'B-$i');
      }


      List<MessageRecord> listA = <MessageRecord>[];
      List<MessageRecord> listB = <MessageRecord>[];
      final DateTime deadline =
          DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(deadline)) {
        listA = await a.store.listMessages(threadA, limit: -1);
        listB = await b.store.listMessages(threadB, limit: -1);
        if (listA.length >= 20 && listB.length >= 20) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      expect(listA.length, 20, reason: 'A 应看到全部 20 条');
      expect(listB.length, 20, reason: 'B 应看到全部 20 条');

      final List<String> idsA =
          listA.map((MessageRecord m) => m.id).toList(growable: false);
      final List<String> idsB =
          listB.map((MessageRecord m) => m.id).toList(growable: false);
      expect(idsA, idsB, reason: '两侧顺序必须完全一致');

      // 顺序必须严格按 HLC 单调（listMessages 已按定宽 hlc 升序）。
      for (int i = 1; i < listA.length; i++) {
        expect(listA[i].hlc.compareTo(listA[i - 1].hlc), greaterThan(0));
      }

      // 双向都收到了对方的 10 条。
      expect(listA.where((MessageRecord m) => m.senderPeerId == a.peer).length, 10);
      expect(listA.where((MessageRecord m) => m.senderPeerId == b.peer).length, 10);
    });
  });

  group('撤回', () {
    test('撤回后对端能看到 revokedAt（只标记不删除）', () async {
      clients.add(await a.connectTo(b));
      await waitFor(() => a.service.isPeerOnline(b.peer));
      await waitFor(() => b.service.isPeerOnline(a.peer));

      final String thread = directThreadId(a.peer, b.peer);
      await a.service.sendText(thread, '要被撤回的消息');

      // 等 B 收到。
      List<MessageRecord> onB = <MessageRecord>[];
      final DateTime deadline =
          DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(deadline)) {
        onB = await b.store.listMessages(thread, limit: -1);
        if (onB.isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(onB.length, 1);
      expect(onB.single.isRevoked, isFalse);

      final String messageId = onB.single.id;
      await a.service.revoke(messageId, reason: '发错了');

      // 1 秒内对端应看到 revokedAt。
      await waitFor(
        () => true,
        timeout: const Duration(milliseconds: 1000),
        reason: '给撤回帧一点传播时间',
      );
      final DateTime revokeDeadline =
          DateTime.now().add(const Duration(seconds: 1));
      MessageRecord? seen;
      while (DateTime.now().isBefore(revokeDeadline)) {
        final List<MessageRecord> now =
            await b.store.listMessages(thread, limit: -1);
        if (now.isNotEmpty && now.single.isRevoked) {
          seen = now.single;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(seen, isNotNull, reason: '对端 1 秒内必须看到 revokedAt');
      expect(seen!.revokedAt, isNotNull);
      expect(seen.revokeReason, '发错了');
      // 只标记不物理删除：那条消息仍在。
      expect(
        (await b.store.listMessages(thread, limit: -1)).length,
        1,
        reason: '撤回不得物理删除，必须仍可查到',
      );
    });
  });

  group('离线补拉', () {
    test('断线期间发 5 条，重连后补齐且不重复', () async {
      final WsClientEndpoint first = await a.connectTo(b);
      clients.add(first);
      await waitFor(() => a.service.isPeerOnline(b.peer));
      await waitFor(() => b.service.isPeerOnline(a.peer));

      final String thread = directThreadId(a.peer, b.peer);
      await a.service.sendText(thread, '在线时的一条');
      await waitFor(
        () => a.service.pendingCount(b.peer) == 0,
        reason: '断线前在线消息应已收到确认',
      );

      // 断开。
      await first.dispose();
      clients.remove(first);
      await waitFor(
        () => !a.service.isPeerOnline(b.peer),
        reason: 'A 应感知 B 离线',
      );

      // 断线期间再发 5 条：这些只进本地库 + 离线队列。
      for (int i = 0; i < 5; i++) {
        await a.service.sendText(thread, '离线-$i');
      }
      expect(a.service.pendingCount(b.peer), 5,
          reason: '5 条应进离线待发队列');

      final int beforeReconnect =
          (await a.store.listMessages(thread, limit: -1)).length;
      expect(beforeReconnect, 6, reason: '发送侧本地库应有 1+5 条');

      // 重连：补拉 + 离线补发都由 adoptOutboundLink 触发。
      clients.add(await a.connectTo(b));

      final DateTime deadline =
          DateTime.now().add(const Duration(seconds: 10));
      List<MessageRecord> onB = <MessageRecord>[];
      while (DateTime.now().isBefore(deadline)) {
        onB = await b.store.listMessages(thread, limit: -1);
        if (onB.length >= 6) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      expect(onB.length, 6, reason: '重连后 5 条离线消息应补齐（外加在线那条）');
      final Set<String> ids = onB.map((MessageRecord m) => m.id).toSet();
      expect(ids.length, 6, reason: '不得重复');
      expect(
        onB.where((MessageRecord m) => m.body.startsWith('离线-')).length,
        5,
      );

      // 补发成功后队列应清空（对端 ack）。
      final DateTime ackDeadline =
          DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(ackDeadline) &&
          a.service.pendingCount(b.peer) > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(a.service.pendingCount(b.peer), 0,
          reason: '收到 ack 后离线队列应清空');
    });
  });

  group('时钟回退韧性', () {
    test('注入倒退时钟，HLC 仍严格单调递增', () {
      // 直接对 HlcClock 注入倒退墙钟；服务层用的是同一个类。
      final List<int> walls = <int>[1000, 999, 500, 100, 50];
      int index = 0;
      final HlcClock clock = HlcClock(
        origin: a.peer.value,
        now: () {
          final int value = walls[index < walls.length ? index : walls.length - 1];
          if (index < walls.length) index++;
          return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
        },
      );
      Hlc previous = clock.next();
      for (int i = 0; i < 20; i++) {
        final Hlc current = clock.next();
        expect(current.compareTo(previous), greaterThan(0),
            reason: '墙钟持续回退时 HLC 仍必须严格递增');
        previous = current;
      }
    });
  });
}
