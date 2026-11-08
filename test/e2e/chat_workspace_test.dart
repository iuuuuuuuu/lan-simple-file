// SPDX-License-Identifier: GPL-3.0-only
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/assembly.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/discovery/announce_codec.dart';
import 'package:lan_simple_file/core/discovery/announce_service_impl.dart';
import 'package:lan_simple_file/core/identity/ed25519_signer.dart';
import 'package:lan_simple_file/core/messaging/message_sync.dart';
import 'package:lan_simple_file/core/messaging/messaging_service_impl.dart';
import 'package:lan_simple_file/core/messaging/ws_peer_auth.dart';

import 'profile_share_groups_test.dart' show packetOf;

void main() {
  late Directory temp;
  final nodes = <AppServices>[];

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lsf_chat_workspace_');
  });
  tearDown(() async {
    for (final node in nodes.reversed) {
      await node.stop();
    }
    nodes.clear();
    await temp.delete(recursive: true);
  });

  Future<AppServices> boot(String name) async {
    final reservation = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
    );
    final port = reservation.port;
    reservation.close();
    final node = await AppAssembler.assemble(
      dataDir: Directory('${temp.path}/$name'),
      name: name,
      httpPortOverride: 0,
      udpPortOverride: port,
      enableDiscovery: true,
    );
    nodes.add(node);
    return node;
  }

  Future<void> waitUntil(Future<bool> Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (!await condition()) {
      if (DateTime.now().isAfter(deadline)) fail('聊天状态等待超时');
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }

  Future<void> discover(List<AppServices> active) async {
    for (final sender in active) {
      final packet = await packetOf(sender);
      for (final receiver in active) {
        if (sender == receiver) continue;
        expect(
          (sender.announce as AnnounceServiceImpl).debugSendTo(
            encodeAnnounceFrame(packet),
            (receiver.announce as AnnounceServiceImpl).port,
          ),
          isTrue,
          reason:
              'sender=${(sender.announce as AnnounceServiceImpl).diagnosticState}; '
              'receiver=${(receiver.announce as AnnounceServiceImpl).diagnosticState}; '
              'errors=${sender.announce.rejected.recentReasons}',
        );
      }
    }
    await waitUntil(
      () async => active.every(
        (a) => active.every(
          (b) => a == b || a.messaging.isPeerOnline(b.identity.peerId),
        ),
      ),
    );
  }

  test('真实 UDP 发现后自动认证建链，私聊双向送达，本机消息和多个会话不覆盖', () async {
    final a = await boot('a');
    final b = await boot('b');
    final c = await boot('c');
    await discover([a, b, c]);
    final ab = directThreadId(a.identity.peerId, b.identity.peerId);
    final ac = directThreadId(a.identity.peerId, c.identity.peerId);
    final aa = directThreadId(a.identity.peerId, a.identity.peerId);
    await Future.wait([
      a.messaging.sendText(ab, '发给 B'),
      a.messaging.sendText(ac, '发给 C'),
      a.messaging.sendText(aa, '本机笔记'),
    ]);
    await b.messaging.sendText(ab, 'B 的回复');
    await waitUntil(
      () async =>
          (await a.store.listMessages(ab)).length == 2 &&
          (await b.store.listMessages(ab)).length == 2 &&
          (await c.store.listMessages(ac)).length == 1,
    );
    expect((await a.store.listMessages(aa)).single.body, '本机笔记');
    final own = [
      ...await a.store.listMessages(ab),
      ...await a.store.listMessages(ac),
      ...await a.store.listMessages(aa),
    ].where((m) => m.senderPeerId == a.identity.peerId);
    expect(own.map((m) => m.id).toSet(), hasLength(3));
    expect((await c.store.listMessages(ab)), isEmpty);
    expect(
      (await a.store.listThreads()).where((t) => t.id == ab).single.unread,
      1,
    );
    await a.messaging.markRead(ab);
    expect(
      (await a.store.listThreads()).where((t) => t.id == ab).single.unread,
      0,
    );
    final received = (await a.store.listMessages(ab))
        .firstWhere((m) => m.senderPeerId == b.identity.peerId);
    await expectLater(
      a.messaging.revoke(received.id),
      throwsA(isA<LanFileException>()),
    );
    final ownMessage = (await a.store.listMessages(ab))
        .firstWhere((m) => m.senderPeerId == a.identity.peerId);
    await a.messaging.revoke(ownMessage.id);
    await waitUntil(
      () async =>
          (await b.store.listMessages(ab))
              .firstWhere((m) => m.id == ownMessage.id)
              .isRevoked,
    );
    expect(
      (await a.store.listMessages(ab))
          .firstWhere((m) => m.id == ownMessage.id)
          .isRevoked,
      isTrue,
    );
    await a.messaging.sendText(ab, '离线后撤回');
    await waitUntil(
      () async =>
          (await b.store.listMessages(ab)).any((m) => m.body == '离线后撤回'),
    );
    final offlineMessage = (await a.store.listMessages(ab))
        .firstWhere((m) => m.body == '离线后撤回');
    nodes.remove(b);
    await b.stop();
    await a.messaging.revoke(offlineMessage.id);
    final restartedB = await boot('b');
    await discover([a, restartedB, c]);
    await waitUntil(
      () async =>
          (await restartedB.store.listMessages(ab))
              .firstWhere((m) => m.id == offlineMessage.id)
              .isRevoked,
    );
  });

  test('群创建后即时发消息可补齐，群历史离线重启后同步，非成员不得读取或写入', () async {
    var a = await boot('a');
    var b = await boot('b');
    final c = await boot('c');
    await discover([a, b, c]);
    final groupId = await a.messaging.createGroup('测试群', [b.identity.peerId]);
    final threadId = 'g_$groupId';
    await a.messaging.sendText(threadId, '邀请后立即发送');
    await waitUntil(
      () async => (await b.store.listMessages(threadId)).length == 1,
    );
    await b.messaging.sendText(threadId, '收到');
    await waitUntil(
      () async => (await a.store.listMessages(threadId)).length == 2,
    );
    expect(
      (await b.store.listThreads()).where((t) => t.id == threadId).single.kind,
      'group',
    );
    expect(await c.store.listMessages(threadId), isEmpty);
    await expectLater(
      c.messaging.sendText(threadId, '非成员发送'),
      throwsA(isA<LanFileException>()),
    );
    await expectLater(
      a.messaging.handleFrame(
        c.identity.peerId,
        WsFrame(WsFrame.pull, encodePull(threadId, null)),
      ),
      throwsA(isA<LanFileException>()),
    );

    final savedBId = b.identity.peerId;
    nodes.remove(b);
    await b.stop();
    await a.messaging.sendText(threadId, '离线期间发送');
    nodes.remove(a);
    await a.stop();
    a = await boot('a');
    b = await boot('b');
    expect(b.identity.peerId, savedBId);
    await discover([a, b, c]);
    await waitUntil(
      () async => (await b.store.listMessages(threadId)).length == 3,
    );
    expect((await b.store.listMessages(threadId)).last.body, '离线期间发送');
    expect(
      (await b.store.listMessages(threadId)).map((m) => m.id).toSet(),
      hasLength(3),
    );
    await a.messaging.sendText(threadId, '重启后发送');
    await waitUntil(
      () async => (await b.store.listMessages(threadId)).length == 4,
    );
  });

  test('WS 升级需要签名，重用凭证和篡改消息不能读取或写入聊天', () async {
    final a = await boot('a');
    final b = await boot('b');
    await discover([a, b]);
    final auth = WsPeerAuth(
      identity: a.identity,
      keys: a.keys,
      verifier: Ed25519Signer(),
    );
    final headers = await auth.headers(b.identity.peerId);
    // Each upgrade is a fresh connection, including replayed credentials.
    Future<int> upgrade(Map<String, String> proof) async {
      final client = HttpClient();
      try {
        final req = await client.getUrl(
          Uri.parse('http://127.0.0.1:${b.port}/ws'),
        );
        req.headers.set('connection', 'Upgrade');
        req.headers.set('upgrade', 'websocket');
        req.headers.set('sec-websocket-version', '13');
        req.headers.set('sec-websocket-key', base64Encode(List.filled(16, 2)));
        proof.forEach(req.headers.set);
        final response = await req.close();
        if (response.statusCode == 101) {
          final socket = await response.detachSocket();
          socket.destroy();
        } else {
          await response.drain<void>();
        }
        return response.statusCode;
      } finally {
        client.close(force: true);
      }
    }

    expect(await upgrade({}), 403);
    expect(await upgrade(headers), 101);
    expect(await upgrade(headers), 403);

    final threadId = directThreadId(a.identity.peerId, b.identity.peerId);
    await a.messaging.sendText(threadId, '原始消息');
    await waitUntil(
      () async => (await b.store.listMessages(threadId)).isNotEmpty,
    );
    final original = (await a.store.listMessages(threadId)).single;
    final payload = encodeMessage(original)..['body'] = '篡改正文';
    await expectLater(
      b.messaging.handleFrame(a.identity.peerId, WsFrame(WsFrame.msg, payload)),
      throwsA(isA<LanFileException>()),
    );
    expect((await b.store.listMessages(threadId)).single.body, '原始消息');
    final strangerThread = directThreadId(a.identity.peerId, a.identity.peerId);
    await expectLater(
      b.messaging.handleFrame(
        a.identity.peerId,
        WsFrame(WsFrame.pull, encodePull(strangerThread, null)),
      ),
      throwsA(isA<LanFileException>()),
    );
  });
}
