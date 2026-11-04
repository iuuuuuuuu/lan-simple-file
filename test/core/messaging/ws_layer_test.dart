// SPDX-License-Identifier: GPL-3.0-only

/// WS 层测试：退避策略、WsLink 握手与坏帧、服务端拒绝非 WS 请求、客户端重连。
///
/// 需要真网络的部分（服务端拒绝、重连）起真实 HttpServer；
/// 纯策略与状态机部分（退避、WsLink）用内存 transport，避免把逻辑正确性
/// 绑在网络时序上。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/messaging/message_sync.dart';
import 'package:lan_simple_file/core/messaging/ws_client_endpoint.dart';
import 'package:lan_simple_file/core/messaging/ws_hub.dart';
import 'package:lan_simple_file/core/messaging/ws_server_endpoint.dart';
import 'package:lan_simple_file/core/server/http_server_host.dart';
import 'package:lan_simple_file/core/server/router.dart';

PeerId _peer(String s) => PeerId.parse('p_7fk3m9x2a1c$s');

/// 内存 transport：把 add 的帧直接回灌到本地 stream，用于单测 WsLink 状态机。
final class MemoryTransport implements WsTransport {
  MemoryTransport();

  final StreamController<Object?> _incoming =
      StreamController<Object?>.broadcast();
  final List<String> sent = <String>[];
  bool closed = false;

  @override
  Stream<Object?> get stream => _incoming.stream;

  @override
  void add(Object? data) {
    if (data is String) sent.add(data);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    closed = true;
    if (!_incoming.isClosed) await _incoming.close();
  }

  /// 模拟对端发来一帧（可传二进制以测协议错误路径）。
  void deliver(Object? data) {
    if (!_incoming.isClosed) _incoming.add(data);
  }

  /// 模拟传输层出错。
  void fail(Object error) {
    if (!_incoming.isClosed) _incoming.addError(error);
  }
}

void main() {
  group('ReconnectBackoff', () {
    test('从 base 起步按 2 的幂增长，且不超过上限 30s', () {
      final ReconnectBackoff backoff = ReconnectBackoff(
        base: const Duration(milliseconds: 200),
        max: const Duration(seconds: 30),
      );
      expect(backoff.nextDelay, const Duration(milliseconds: 200));
      expect(backoff.recordFailure(), const Duration(milliseconds: 200));
      expect(backoff.recordFailure(), const Duration(milliseconds: 400));
      expect(backoff.recordFailure(), const Duration(milliseconds: 800));
      expect(backoff.recordFailure(), const Duration(milliseconds: 1600));
    });

    test('持续失败封顶在上限，不会无限增长', () {
      final ReconnectBackoff backoff = ReconnectBackoff(
        base: const Duration(milliseconds: 200),
        max: const Duration(seconds: 30),
      );
      for (int i = 0; i < 100; i++) {
        backoff.recordFailure();
      }
      expect(backoff.nextDelay, const Duration(seconds: 30),
          reason: '协议要求退避上限 30s');
    });

    test('reset 后回到 base', () {
      final ReconnectBackoff backoff = ReconnectBackoff();
      for (int i = 0; i < 8; i++) {
        backoff.recordFailure();
      }
      expect(backoff.nextDelay, greaterThan(const Duration(seconds: 1)));
      backoff.reset();
      expect(backoff.attempt, 0);
      expect(backoff.nextDelay, backoff.base);
    });
  });

  group('WsLink 状态机', () {
    test('握手前收到业务帧会被拒绝（不断链时不投递）', () async {
      final MemoryTransport transport = MemoryTransport();
      final WsLink link = WsLink(
        transport: transport,
        localPeerId: _peer('aa'),
        localName: 'A',
        localAvatarHash: '',
        localCapabilities: WsFrame.all,
      );
      link.start();
      final List<WsFrame> received = <WsFrame>[];
      link.frames.listen(received.add);

      transport.deliver(encodeFrame(
        WsFrame(WsFrame.msg, <String, Object?>{'id': 'x'}),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(received, isEmpty, reason: '未握手不得投递业务帧');
      await link.closed.timeout(const Duration(seconds: 2));
      expect(link.isClosed, isTrue, reason: '未握手先发业务帧应断链');
    });

    test('缺失 id 的 hello 会断链，而不是接受匿名对端', () async {
      final MemoryTransport transport = MemoryTransport();
      final WsLink link = WsLink(
        transport: transport,
        localPeerId: _peer('aa'),
        localName: 'A',
        localAvatarHash: '',
        localCapabilities: WsFrame.all,
      );
      link.start();
      transport.deliver(encodeFrame(WsFrame(WsFrame.hello, <String, Object?>{})));

      await link.closed.timeout(const Duration(seconds: 2));
      expect(link.remote, isNull);
    });

    test('合法 hello 后被投递，远程身份可读', () async {
      final MemoryTransport transport = MemoryTransport();
      final WsLink link = WsLink(
        transport: transport,
        localPeerId: _peer('aa'),
        localName: 'A',
        localAvatarHash: '',
        localCapabilities: WsFrame.all,
      );
      link.start();
      transport.deliver(encodeFrame(WsFrame(WsFrame.hello, <String, Object?>{
        'id': _peer('bb').value,
        'name': 'B',
        'av': '',
        'caps': <String>[WsFrame.msg],
      })));

      final RemoteIdentity remote = await link.handshake;
      expect(remote.peerId, _peer('bb'));
      expect(remote.name, 'B');
      expect(remote.supports(WsFrame.msg), isTrue);
      expect(remote.supports(WsFrame.typing), isFalse);
    });

    test('非文本帧（二进制）直接断链', () async {
      final MemoryTransport transport = MemoryTransport();
      final WsLink link = WsLink(
        transport: transport,
        localPeerId: _peer('aa'),
        localName: 'A',
        localAvatarHash: '',
        localCapabilities: WsFrame.all,
      );
      link.start();
      transport.deliver(<int>[1, 2, 3]);
      await link.closed.timeout(const Duration(seconds: 2));
      expect(link.isClosed, isTrue);
    });

    test('链路关闭后 send 返回 false 而不是抛异常', () async {
      final MemoryTransport transport = MemoryTransport();
      final WsLink link = WsLink(
        transport: transport,
        localPeerId: _peer('aa'),
        localName: 'A',
        localAvatarHash: '',
        localCapabilities: WsFrame.all,
      );
      link.start();
      expect(link.send(WsFrame(WsFrame.msg, <String, Object?>{})), isTrue);
      await link.close();
      expect(link.send(WsFrame(WsFrame.msg, <String, Object?>{})), isFalse);
    });
  });

  group('服务端拒绝非 WS 请求（真实 HttpServer）', () {
    late HttpServerHost host;
    late Router router;

    setUp(() async {
      router = Router();
      router.get(kWsPath, (HttpRequest request) async {
        await handleWsRequest(
          request,
          (WsLink link) async {
            link.start();
            link.sendHello();
          },
          localPeerId: _peer('aa'),
          localName: 'A',
          localAvatarHash: '',
          localCapabilities: WsFrame.all,
        );
      });
      host = HttpServerHost(router: router, preferredPort: 0);
      await host.start();
    });

    tearDown(() async {
      await host.stop();
    });

    test('普通 GET /ws 返回 400 且 body 是可解析 JSON', () async {
      final HttpClient client = HttpClient();
      final HttpClientRequest request = await client
          .getUrl(Uri.parse('http://127.0.0.1:${host.port}/ws'));
      final HttpClientResponse response = await request.close();
      final String body = await response.transform(const Utf8Decoder()).join();
      client.close();

      expect(response.statusCode, 400);
      final Map<String, Object?> json =
          jsonDecode(body) as Map<String, Object?>;
      expect(json['code'], isNotNull);
      expect(json['message'], isNotNull);
    });
  });

  group('客户端重连（真实 HttpServer）', () {
    test('对端不可达时 connect 抛错，且退避被安排', () async {
      final List<Duration> scheduled = <Duration>[];
      final WsClientEndpoint client = WsClientEndpoint(
        host: '127.0.0.1',
        // 一个几乎肯定没人监听的端口。
        port: 1,
        localPeerId: _peer('aa'),
        localName: 'A',
        localAvatarHash: '',
        localCapabilities: WsFrame.all,
        connectTimeout: const Duration(milliseconds: 300),
        onReconnectScheduled: scheduled.add,
      );

      await expectLater(client.connect(), throwsA(isA<LanFileException>()));
      expect(scheduled, isNotEmpty, reason: '失败后应安排退避重连');
      expect(scheduled.first, client.attempts > 0 ? isNotNull : isNotNull);
      await client.dispose();
    });

    test('dispose 后不再安排重连', () async {
      final List<Duration> scheduled = <Duration>[];
      final WsClientEndpoint client = WsClientEndpoint(
        host: '127.0.0.1',
        port: 1,
        localPeerId: _peer('aa'),
        localName: 'A',
        localAvatarHash: '',
        localCapabilities: WsFrame.all,
        connectTimeout: const Duration(milliseconds: 300),
        onReconnectScheduled: scheduled.add,
      );

      await expectLater(client.connect(), throwsA(isA<LanFileException>()));
      final int before = scheduled.length;
      await client.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(scheduled.length, before, reason: 'dispose 后不得再安排重连');
    });

    test('断开后自动重连成功（服务端重启）', () async {
      PeerId local = _peer('aa');
      Router serverRouter = Router();
      WsLink? serverLink;
      serverRouter.get(kWsPath, (HttpRequest request) async {
        await handleWsRequest(
          request,
          (WsLink link) async {
            link.start();
            link.sendHello();
            serverLink = link;
          },
          localPeerId: _peer('bb'),
          localName: 'B',
          localAvatarHash: '',
          localCapabilities: WsFrame.all,
        );
      });
      final HttpServerHost server =
          HttpServerHost(router: serverRouter, preferredPort: 0);
      final int port = await server.start();

      int linkUps = 0;
      final WsClientEndpoint client = WsClientEndpoint(
        host: '127.0.0.1',
        port: port,
        localPeerId: local,
        localName: 'A',
        localAvatarHash: '',
        localCapabilities: WsFrame.all,
        backoff: ReconnectBackoff(
          base: const Duration(milliseconds: 50),
          max: const Duration(milliseconds: 200),
        ),
        onLinkUp: (WsLink link) async {
          linkUps++;
        },
      );

      await client.connect();
      expect(linkUps, 1);
      expect(client.isConnected, isTrue);

      // 服务端单方面断开，客户端应自动重连。
      await serverLink!.close(reason: 'server closes');

      final DateTime deadline =
          DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(deadline) && linkUps < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(linkUps, greaterThanOrEqualTo(2), reason: '断线后应自动重连');

      await client.dispose();
      await server.stop();
    });
  });
}
