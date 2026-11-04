// SPDX-License-Identifier: GPL-3.0-only

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/assembly.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/messaging/peer_chat_connections.dart';

void main() {
  test('建链失败后清理任务，不抛后台异常，并允许下一次重新连接', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'lsf_connect_failure_',
    );
    final services = await AppAssembler.assemble(
      dataDir: temporary,
      httpPortOverride: 0,
      udpPortOverride: 0,
      enableDiscovery: false,
    );
    final endpoint = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var attempts = 0;
    endpoint.listen((request) async {
      attempts++;
      request.response.statusCode = 403;
      await request.response.close();
    });
    final connections = PeerChatConnections(
      self: services.identity.peerId,
      messaging: services.messaging,
      endpointFor: (_) async => (host: '127.0.0.1', port: endpoint.port),
      nameReader: () => '本机',
      avatarReader: () => '',
      headersFor: (_) async => {},
    );
    addTearDown(() async {
      await connections.dispose();
      await endpoint.close(force: true);
      await services.stop();
      await temporary.delete(recursive: true);
    });
    final peer = PeerId.parse('p_localdevice00');
    await expectLater(
      connections.connect(peer),
      throwsA(isA<LanFileException>()),
    );
    await expectLater(
      connections.connect(peer),
      throwsA(isA<LanFileException>()),
    );
    expect(attempts, 2);
  });
}
