// SPDX-License-Identifier: GPL-3.0-only
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/assembly.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/messaging/messaging_service_impl.dart';

void main() {
  test('HTTP discovery keeps concurrent target addresses separate', () async {
    final temp = await Directory.systemTemp.createTemp('lsf_direct_targets_');
    final nodes = <AppServices>[];
    addTearDown(() async {
      for (final node in nodes.reversed) {
        await node.stop();
      }
      await temp.delete(recursive: true);
    });
    for (var index = 0; index < 3; index++) {
      nodes.add(
        await AppAssembler.assemble(
          dataDir: Directory('${temp.path}/$index'),
          enableDiscovery: false,
          httpPortOverride: 0,
          udpPortOverride: 0,
        ),
      );
    }
    final source = nodes.first;
    final ids = await Future.wait([
      source.httpDiscovery!.exchange('127.0.0.1', nodes[1].port),
      source.httpDiscovery!.exchange('127.0.0.1', nodes[2].port),
    ]);
    expect(ids, [nodes[1].identity.peerId, nodes[2].identity.peerId]);
    await source.discovery.addByAddress('127.0.0.1', nodes[2].port);
    expect(await source.discovery.findEndpoint(nodes[2].identity.peerId), (
      host: '127.0.0.1',
      port: nodes[2].port,
    ));
    await expectLater(
      source.discovery.addByAddress('8.8.8.8', 80),
      throwsA(isA<LanFileException>()),
    );
  });
  test('广播隔离时HTTP交换双向发现，建立认证聊天并同步消息和撤回', () async {
    final temp = await Directory.systemTemp.createTemp('lsf_nat_discovery_');
    final a = await AppAssembler.assemble(
      dataDir: Directory('${temp.path}/a'),
      name: '桌面',
      enableDiscovery: false,
      httpPortOverride: 0,
      udpPortOverride: 0,
    );
    final b = await AppAssembler.assemble(
      dataDir: Directory('${temp.path}/b'),
      name: '模拟器',
      enableDiscovery: false,
      httpPortOverride: 0,
      udpPortOverride: 0,
    );
    addTearDown(() async {
      await b.stop();
      await a.stop();
      await temp.delete(recursive: true);
    });
    final id = await b.httpDiscovery!.exchange('127.0.0.1', a.port);
    expect(id, a.identity.peerId, reason: b.httpDiscovery!.lastError);
    expect((await b.store.findDevice(a.identity.peerId))!.name, '桌面');
    expect((await a.store.findDevice(b.identity.peerId))!.name, '模拟器');
    expect(
      (await b.store.findDevice(a.identity.peerId))!.os,
      Platform.operatingSystem,
    );
    expect(
      a.discovery.currentPeers
          .singleWhere((p) => p.peerId == b.identity.peerId)
          .os,
      Platform.operatingSystem,
    );
    expect(await b.discovery.findEndpoint(a.identity.peerId), (
      host: '127.0.0.1',
      port: a.port,
    ));
    await b.chatConnections!.connect(a.identity.peerId);
    final thread = directThreadId(a.identity.peerId, b.identity.peerId);
    await b.messaging.sendText(thread, '模拟器发给桌面');
    Future<void> waitFor(Future<bool> Function() condition) async {
      final end = DateTime.now().add(const Duration(seconds: 5));
      while (!await condition()) {
        if (DateTime.now().isAfter(end)) fail('消息未同步');
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
    }

    await waitFor(() async => (await a.store.listMessages(thread)).length == 1);
    await a.messaging.sendText(thread, '桌面回复');
    await waitFor(() async => (await b.store.listMessages(thread)).length == 2);
    final message = (await b.store.listMessages(thread)).first;
    await b.messaging.revoke(message.id);
    await waitFor(
      () async => (await a.store.listMessages(thread)).first.isRevoked,
    );
    await a.renameSelf('改名桌面');
    await b.httpDiscovery!.exchange('127.0.0.1', a.port);
    expect((await b.store.findDevice(a.identity.peerId))!.name, '改名桌面');
  });
  test('HTTP发现拒绝改名篡改、公钥错配、过期和公网端点，不写入设备表', () async {
    final temp = await Directory.systemTemp.createTemp('lsf_nat_bad_');
    final a = await AppAssembler.assemble(
      dataDir: Directory('${temp.path}/a'),
      enableDiscovery: false,
      httpPortOverride: 0,
      udpPortOverride: 0,
    );
    final b = await AppAssembler.assemble(
      dataDir: Directory('${temp.path}/b'),
      enableDiscovery: false,
      httpPortOverride: 0,
      udpPortOverride: 0,
    );
    addTearDown(() async {
      await b.stop();
      await a.stop();
      await temp.delete(recursive: true);
    });
    final body = await a.httpDiscovery!.envelope();
    final bad = Map<String, Object?>.from(jsonDecode(jsonEncode(body)) as Map);
    (bad['packet'] as Map)['name'] = '伪造';
    await expectLater(
      b.httpDiscovery!.receive(bad, '127.0.0.1', a.port),
      throwsA(isA<LanFileException>()),
    );
    final badPlatform = Map<String, Object?>.from(
      jsonDecode(jsonEncode(body)) as Map,
    );
    (badPlatform['packet'] as Map)['caps'] = ['os:android'];
    await expectLater(
      b.httpDiscovery!.receive(badPlatform, '127.0.0.1', a.port),
      throwsA(isA<LanFileException>()),
    );
    final wrong = Map<String, Object?>.from(body)
      ..['publicKey'] = base64Url.encode(b.identity.publicKey);
    await expectLater(
      b.httpDiscovery!.receive(wrong, '127.0.0.1', a.port),
      throwsA(isA<LanFileException>()),
    );
    final expired = Map<String, Object?>.from(
      jsonDecode(jsonEncode(body)) as Map,
    );
    (expired['packet'] as Map)['ts'] = 0;
    await expectLater(
      b.httpDiscovery!.receive(expired, '127.0.0.1', a.port),
      throwsA(isA<LanFileException>()),
    );
    await expectLater(
      b.httpDiscovery!.receive(body, '8.8.8.8', a.port),
      throwsA(isA<LanFileException>()),
    );
    expect(await b.store.findDevice(a.identity.peerId), isNull);
  });
}
