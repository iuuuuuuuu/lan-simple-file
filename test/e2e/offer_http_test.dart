// SPDX-License-Identifier: GPL-3.0-only

/// Lead 侧端到端：offer 走真实 HTTP 投递 + 真实接收侧路由。
///
/// A 起服务并 propose；B 起服务并暴露 /api/v1/offers。
/// 这条证明「发得出、收得到」，而不是同进程假投递。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/assembly.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/offers/http_offer_transport.dart';
import 'package:lan_simple_file/core/offers/offer_service_impl.dart';
import 'package:lan_simple_file/core/transfer/store_target_resolver.dart';
/// 告诉 A「B 在 127.0.0.1:B Port」。
final class _FixedEndpoints implements PeerEndpointSource {
  _FixedEndpoints(this.peer, this.host, this.port);

  final PeerId peer;
  final String host;
  final int port;

  @override
  Future<({String host, int port})?> findEndpoint(PeerId p) async =>
      p == peer ? (host: host, port: port) : null;
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lsf_offer_e2e_');
  });
  tearDown(() {
    for (int i = 0; i < 8; i++) {
      try {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        sleep(const Duration(milliseconds: 150));
      }
    }
  });

  test('offer 真实 HTTP 投递：A propose -> B 的接收侧路由收到并落库', () async {
    final AppServices b = await AppAssembler.assemble(
      dataDir: Directory('${tmp.path}${Platform.pathSeparator}b'),
      httpPortOverride: 0,
      udpPortOverride: 0,
      enableDiscovery: false,
      name: 'B',
    );
    final AppServices a = await AppAssembler.assemble(
      dataDir: Directory('${tmp.path}${Platform.pathSeparator}a'),
      httpPortOverride: 0,
      udpPortOverride: 0,
      enableDiscovery: false,
      name: 'A',
    );
    try {
      // A 准备一个真实文件作为 offer 内容
      final String srcPath = '${tmp.path}${Platform.pathSeparator}pic.jpg';
      File(srcPath).writeAsBytesSync(List<int>.filled(2048, 7));

      // A 的 offer 服务改成指向 B 的真实地址
      final OfferServiceImpl aOffers = OfferServiceImpl(
        store: a.store,
        identity: a.identity,
        codec: a.codec,
        transport: HttpOfferTransport(
          endpoints: _FixedEndpoints(b.identity.peerId, '127.0.0.1', b.port),
        ),
      );

      final String offerId = await aOffers.propose(
        toPeer: b.identity.peerId,
        localPaths: <String>[srcPath],
        note: '给你一张图',
      );
      expect(offerId, isNotEmpty);

      // B 侧必须真的收到：走真实 HTTP GET /api/v1/offers
      final HttpClient client = HttpClient();
      final HttpClientRequest req = await client.getUrl(
        Uri.parse('http://127.0.0.1:${b.port}/api/v1/offers'),
      );
      final HttpClientResponse res = await req.close();
      expect(res.statusCode, 200);
      final String text = await res.transform(utf8.decoder).join();
      final Map<String, Object?> json =
          jsonDecode(text) as Map<String, Object?>;
      final List<Object?> items = json['items']! as List<Object?>;
      expect(items, isNotEmpty, reason: 'B 必须收到 A 发来的 offer');
      final Map<String, Object?> first = items.first! as Map<String, Object?>;
      expect(first['id'], offerId);
      expect(first['status'], 'pending');
      expect(first['note'], '给你一张图');
      final List<Object?> files = first['files']! as List<Object?>;
      expect(files.length, 1);
      expect((files.first! as Map<String, Object?>)['size'], 2048,
          reason: '必须是真实文件大小，不是编的');

      client.close();
      await aOffers.dispose();
    } finally {
      await a.stop();
      await b.stop();
    }
  });

  test('对端离线：propose 必须 providerOffline，不静默排队', () async {
    final AppServices a = await AppAssembler.assemble(
      dataDir: Directory('${tmp.path}${Platform.pathSeparator}a2'),
      httpPortOverride: 0,
      udpPortOverride: 0,
      enableDiscovery: false,
    );
    try {
      final String srcPath = '${tmp.path}${Platform.pathSeparator}x.txt';
      File(srcPath).writeAsStringSync('hi');
      final OfferServiceImpl aOffers = OfferServiceImpl(
        store: a.store,
        identity: a.identity,
        codec: a.codec,
        transport: HttpOfferTransport(
          // 谁也不认识
          endpoints: _FixedEndpoints(
            PeerId.parse('p_zzzzzzzzzzzzz'),
            '127.0.0.1',
            1,
          ),
        ),
      );
      // 语义澄清：isReachable 判的是「能不能解析到地址」；
      // 解析到了但连不上，属于 network，不是 providerOffline。
      // 这里用一个「完全不认识的 peer」来测 providerOffline。
      await expectLater(
        aOffers.propose(
          toPeer: PeerId.parse('p_aaaaaaaaaaaaa'),
          localPaths: <String>[srcPath],
        ),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.providerOffline,
          ),
        ),
      );
      await aOffers.dispose();
    } finally {
      await a.stop();
    }
  });
}