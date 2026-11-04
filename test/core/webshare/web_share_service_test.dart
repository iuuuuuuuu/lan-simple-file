// SPDX-License-Identifier: GPL-3.0-only

/// M6 网页会话分享：真 HttpServer + 真 sqlite + 真临时目录。
///
/// 重点覆盖四条产品硬约束：接受前零字节、会话即生命周期、配额、宽限期删除。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/webshare/guest_session_registry.dart';

import 'support/web_share_fixture.dart';

/// 测试里用的浏览器公钥（真实 ECDSA P-256 公钥的 base64url 形态）。
const String kClientPubkey =
    'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEfakePubkeyForTestOnly';

Future<HttpClientResponse> send(
  HttpClient client,
  Uri uri, {
  String method = 'POST',
  Map<String, String> headers = const <String, String>{},
  Object? jsonBody,
  List<int>? bytes,
}) async {
  final HttpClientRequest request = await client.openUrl(method, uri);
  headers.forEach((String name, String value) {
    request.headers.set(name, value);
  });
  if (jsonBody != null) {
    request.headers.contentType = ContentType.json;
    request.add(utf8.encode(jsonEncode(jsonBody)));
  } else if (bytes != null) {
    request.add(bytes);
  }
  return request.close();
}

Future<Map<String, Object?>> bodyJson(HttpClientResponse response) async {
  final List<int> raw = await response.fold<List<int>>(
    <int>[],
    (List<int> acc, List<int> chunk) {
      acc.addAll(chunk);
      return acc;
    },
  );
  if (raw.isEmpty) return <String, Object?>{};
  return jsonDecode(utf8.decode(raw)) as Map<String, Object?>;
}

void main() {
  group('握手与心跳', () {
    test('POST /w/session 返回 guestSessionId 与心跳参数', () async {
      final WebShareFixture f = await WebShareFixture.create();
      addTearDown(f.dispose);
      final GuestHttpServer server =
          await GuestHttpServer.start(service: f.service);
      addTearDown(server.stop);
      final HttpClient client = HttpClient();
      addTearDown(() => client.close(force: true));

      final HttpClientResponse response = await send(
        client,
        server.url('/w/session'),
        jsonBody: <String, Object?>{'pubkey': kClientPubkey},
      );
      expect(response.statusCode, 200);
      final Map<String, Object?> json = await bodyJson(response);
      final String sessionId = json['guestSessionId']! as String;
      expect(sessionId, isNotEmpty);
      expect(json['hostPeer'], 'p_7fk3m9x2a1cdk');
      expect(json['heartbeatSeconds'], 15);
      expect(json['quotaBytes'], LanFileConstants.webShareQuotaBytes);
      expect(json['gracePeriodSeconds'], 600);

      // 会话必须真的落库（重启后能被识别成「已结束」而不是不存在）。
      final GuestSessionRecord? stored =
          await f.store.findGuestSession(sessionId);
      expect(stored, isNotNull);
      expect(stored!.hostPeer.value, 'p_7fk3m9x2a1cdk');
    });

    test('握手缺 pubkey 返回 400', () async {
      final WebShareFixture f = await WebShareFixture.create();
      addTearDown(f.dispose);
      final GuestHttpServer server =
          await GuestHttpServer.start(service: f.service);
      addTearDown(server.stop);
      final HttpClient client = HttpClient();
      addTearDown(() => client.close(force: true));

      final HttpClientResponse response = await send(
        client,
        server.url('/w/session'),
        jsonBody: <String, Object?>{},
      );
      expect(response.statusCode, 400);
    });

    test('心跳成功；会话结束后心跳返回 410', () async {
      final WebShareFixture f = await WebShareFixture.create();
      addTearDown(f.dispose);
      final GuestHttpServer server =
          await GuestHttpServer.start(service: f.service);
      addTearDown(server.stop);
      final HttpClient client = HttpClient();
      addTearDown(() => client.close(force: true));

      final String sessionId = await f.service.openSession(
        clientPubkey: kClientPubkey,
      );
      f.clock.advance(const Duration(seconds: 14));
      final HttpClientResponse beat = await send(
        client,
        server.url('/w/session/$sessionId/beat'),
      );
      expect(beat.statusCode, 200);

      await f.service.revokeSession(sessionId);
      final HttpClientResponse after = await send(
        client,
        server.url('/w/session/$sessionId/beat'),
      );
      expect(after.statusCode, 410);
    });
  });

  group('接受前零字节（核心约束）', () {
    test('未获接受就上传 → 403，且 staging 下不出现任何文件', () async {
      final WebShareFixture f = await WebShareFixture.create();
      addTearDown(f.dispose);
      final GuestHttpServer server =
          await GuestHttpServer.start(service: f.service);
      addTearDown(server.stop);
      final HttpClient client = HttpClient();
      addTearDown(() => client.close(force: true));

      final String sessionId = await f.service.openSession(
        clientPubkey: kClientPubkey,
      );
      // 关键：没有 acknowledgeAcceptedOffer，因此没有任何 grant。
      final HttpClientResponse response = await send(
        client,
        server.url('/w/session/$sessionId/upload/up01'),
        headers: <String, String>{
          'x-lsf-offer': 'offer-1',
          'x-lsf-name': Uri.encodeComponent('evil.bin'),
          'x-lsf-size': '16',
          'x-lsf-offset': '0',
        },
        bytes: List<int>.filled(16, 7),
      );
      expect(response.statusCode, 403);
      final Map<String, Object?> json = await bodyJson(response);
      expect(json['code'], LanFileErrorCode.accessDenied.name);

      // 零字节承诺：连目录都不该建。
      expect(await f.stagingFileCount(sessionId), 0);
      final Directory dir =
          Directory('${f.stagingRoot.path}${Platform.pathSeparator}$sessionId');
      expect(dir.existsSync(), isFalse, reason: '未授权时不得创建会话目录');
    });

    test('伪造 grant 同样 403，且不落任何文件', () async {
      final WebShareFixture f = await WebShareFixture.create();
      addTearDown(f.dispose);
      final GuestHttpServer server =
          await GuestHttpServer.start(service: f.service);
      addTearDown(server.stop);
      final HttpClient client = HttpClient();
      addTearDown(() => client.close(force: true));

      final String sessionId = await f.service.openSession(
        clientPubkey: kClientPubkey,
      );
      final HttpClientResponse response = await send(
        client,
        server.url('/w/session/$sessionId/upload/up02'),
        headers: <String, String>{
          'x-lsf-grant': 'forged-token',
          'x-lsf-offer': 'offer-1',
          'x-lsf-name': Uri.encodeComponent('evil.bin'),
          'x-lsf-size': '16',
          'x-lsf-offset': '0',
        },
        bytes: List<int>.filled(16, 7),
      );
      expect(response.statusCode, 403);
      expect(await f.stagingFileCount(sessionId), 0);
    });

    test('service 层同样零字节：绕过路由直接调 beginAuthorizedUpload 也拒', () async {
      // 这一条不经过 HTTP，专门覆盖「授权闸门在 service 里而非路由里」。
      // 若有人把校验挪走或放宽，这里会立刻变红。
      final WebShareFixture f = await WebShareFixture.create();
      addTearDown(f.dispose);
      final String sessionId = await f.service.openSession(
        clientPubkey: kClientPubkey,
      );

      await expectLater(
        f.service.beginAuthorizedUpload(
          sessionId: sessionId,
          offerId: 'offer-never-accepted',
          fileName: 'secret.bin',
          declaredSize: 1024,
          token: 'no-such-token',
          uploadId: 'up9999',
        ),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.accessDenied,
          ),
        ),
      );
      expect(await f.stagingFileCount(sessionId), 0);
      final Directory unauthDir = Directory(
        '${f.stagingRoot.path}${Platform.pathSeparator}$sessionId',
      );
      expect(unauthDir.existsSync(), isFalse, reason: '未授权时 service 也不得创建目录');
    });

    test('接受后才放行：acknowledgeAcceptedOffer → 上传成功', () async {
      final WebShareFixture f = await WebShareFixture.create();
      addTearDown(f.dispose);
      final GuestHttpServer server =
          await GuestHttpServer.start(service: f.service);
      addTearDown(server.stop);
      final HttpClient client = HttpClient();
      addTearDown(() => client.close(force: true));

      final String sessionId = await f.service.openSession(
        clientPubkey: kClientPubkey,
      );
      const int size = 4096;
      final List<int> payload =
          List<int>.generate(size, (int i) => (i * 7 + 3) & 0xFF);
      final UploadGrant grant = f.service.acknowledgeAcceptedOffer(
        sessionId: sessionId,
        offerId: 'offer-ok',
        fileName: 'photo.bin',
        declaredSize: size,
      );

      final HttpClientResponse chunk = await send(
        client,
        server.url('/w/session/$sessionId/upload/up03'),
        headers: <String, String>{
          'x-lsf-grant': grant.token,
          'x-lsf-offer': 'offer-ok',
          'x-lsf-name': Uri.encodeComponent('photo.bin'),
          'x-lsf-size': '$size',
          'x-lsf-offset': '0',
        },
        bytes: payload,
      );
      expect(chunk.statusCode, 200);
      final Map<String, Object?> chunkJson = await bodyJson(chunk);
      expect(chunkJson['received'], size);

      final HttpClientResponse finish = await send(
        client,
        server.url('/w/session/$sessionId/upload/up03/finish'),
        jsonBody: <String, Object?>{'displayName': '照片'},
      );
      expect(finish.statusCode, 200);
      final Map<String, Object?> finished = await bodyJson(finish);
      final String shareId = finished['shareId']! as String;
      expect(finished['mode'], 'session');
      expect(finished['isEphemeral'], true);
      expect(finished['sessionId'], sessionId);

      // 磁盘上应真的有这份文件，且内容与服务端收到的一致。
      final List<String> files = await f.stagingFiles(sessionId);
      expect(files, hasLength(1));
      expect(await File(files.single).readAsBytes(), payload);

      // 落成 mode=session 的临时 share。
      final ShareRecord? record = await f.store.findShare(
        ShareId.parse(shareId),
      );
      expect(record, isNotNull);
      expect(record!.mode, ShareMode.session);
      expect(record.isEphemeral, isTrue);
      expect(record.sessionId, sessionId);
    });
  });
}