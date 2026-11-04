// SPDX-License-Identifier: GPL-3.0-only

/// ping / profile 接口的真实 HTTP 测试：真起 server、真 HttpClient。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/server/api/ping_api.dart';
import 'package:lan_simple_file/core/server/api/profile_api.dart';
import 'package:lan_simple_file/core/server/http_server_host.dart';
import 'package:lan_simple_file/core/server/router.dart';

const String kPeerId = 'p_7fk3m9x2a1cdk';

Future<HttpClientResponse> _send(
  HttpClient client,
  Uri uri, {
  String method = 'GET',
  Map<String, String> headers = const <String, String>{},
  Object? jsonBody,
  String? rawBody,
}) async {
  final HttpClientRequest request = await client.openUrl(method, uri);
  headers.forEach((String name, String value) {
    request.headers.set(name, value);
  });
  if (jsonBody != null) {
    request.headers.contentType = ContentType.json;
    request.add(utf8.encode(jsonEncode(jsonBody)));
  } else if (rawBody != null) {
    request.add(utf8.encode(rawBody));
  }
  return request.close();
}

Future<Map<String, Object?>> _jsonOf(HttpClientResponse response) async {
  final List<int> bytes = await response.fold<List<int>>(
    <int>[],
    (List<int> acc, List<int> chunk) {
      acc.addAll(chunk);
      return acc;
    },
  );
  return jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
}

void main() {
  group('ping / profile API', () {
    late MemoryProfileSource profile;
    late HttpServerHost host;
    late HttpClient client;
    late int port;

    setUp(() async {
      profile = MemoryProfileSource(
        peerId: PeerId.parse(kPeerId),
        name: 'YG 的台式机',
        avatarHash: 'sha256:0123456789abcdef0123456789abcdef',
      );
      final Router router = Router();
      registerPingRoutes(
        router,
        peerId: profile.peerId,
        nameReader: () => profile.name,
      );
      registerProfileRoutes(router, profile);

      host = HttpServerHost(
        router: router,
        bindAddress: InternetAddress.loopbackIPv4,
        preferredPort: 0,
      );
      port = await host.start();
      client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    });

    tearDown(() async {
      client.close(force: true);
      await host.stop();
    });

    Uri path(String p) => Uri.parse('http://127.0.0.1:$port$p');

    test('ping 返回 peerId/name/proto 三个字段，proto 取契约常量', () async {
      final HttpClientResponse response = await _send(client, path('/api/v1/ping'));
      expect(response.statusCode, 200);
      final Map<String, Object?> json = await _jsonOf(response);
      expect(json, <String, Object?>{
        'peerId': kPeerId,
        'name': 'YG 的台式机',
        'proto': LanFileConstants.protocolVersion,
      });
    });

    test('ping 每次现取名字，PUT 改名后立刻可见', () async {
      final HttpClientResponse before = await _send(client, path('/api/v1/ping'));
      expect((await _jsonOf(before))['name'], 'YG 的台式机');

      final HttpClientResponse put = await _send(
        client,
        path('/api/v1/profile'),
        method: 'PUT',
        jsonBody: <String, Object?>{'name': '新名字'},
      );
      expect(put.statusCode, 200);

      final HttpClientResponse after = await _send(client, path('/api/v1/ping'));
      expect((await _jsonOf(after))['name'], '新名字');
    });

    test('GET profile 返回 peerId/name/avatarHash', () async {
      final HttpClientResponse response =
          await _send(client, path('/api/v1/profile'));
      expect(response.statusCode, 200);
      final Map<String, Object?> json = await _jsonOf(response);
      expect(json['peerId'], kPeerId);
      expect(json['name'], 'YG 的台式机');
      expect(json['avatarHash'], 'sha256:0123456789abcdef0123456789abcdef');
    });

    test('PUT profile 写入名字与头像哈希并回显', () async {
      final HttpClientResponse response = await _send(
        client,
        path('/api/v1/profile'),
        method: 'PUT',
        jsonBody: <String, Object?>{
          'name': '  带空白的名字  ',
          'avatarHash': 'sha256:ffffffffffffffff',
        },
      );
      expect(response.statusCode, 200);
      final Map<String, Object?> json = await _jsonOf(response);
      expect(json['name'], '带空白的名字', reason: '应去掉首尾空白');
      expect(json['avatarHash'], 'sha256:ffffffffffffffff');
      expect(profile.name, '带空白的名字');
      expect(profile.avatarHash, 'sha256:ffffffffffffffff');
    });

    test('PUT profile 只改一个字段时另一个保持', () async {
      final HttpClientResponse response = await _send(
        client,
        path('/api/v1/profile'),
        method: 'PUT',
        jsonBody: <String, Object?>{'name': '只改名字'},
      );
      expect(response.statusCode, 200);
      expect(profile.name, '只改名字');
      expect(
        profile.avatarHash,
        'sha256:0123456789abcdef0123456789abcdef',
      );
    });

    test('PUT profile 空体返回 400 + invalidArgument', () async {
      final HttpClientResponse response = await _send(
        client,
        path('/api/v1/profile'),
        method: 'PUT',
      );
      expect(response.statusCode, 400);
      final Map<String, Object?> json = await _jsonOf(response);
      expect(json['code'], LanFileErrorCode.invalidArgument.name);
    });

    test('PUT profile 非法 JSON 返回 400 而不是 500', () async {
      final HttpClientResponse response = await _send(
        client,
        path('/api/v1/profile'),
        method: 'PUT',
        rawBody: '{not json',
      );
      expect(response.statusCode, 400);
      expect(
        (await _jsonOf(response))['code'],
        LanFileErrorCode.invalidArgument.name,
      );
    });

    test('PUT profile 名字为空 / 含控制字符 / 超长都返回 400', () async {
      for (final String bad in <String>['   ', 'a\u0000b', 'x' * 65]) {
        final HttpClientResponse response = await _send(
          client,
          path('/api/v1/profile'),
          method: 'PUT',
          jsonBody: <String, Object?>{'name': bad},
        );
        expect(response.statusCode, 400, reason: 'bad name: ${bad.length}');
        expect(
          (await _jsonOf(response))['code'],
          LanFileErrorCode.invalidArgument.name,
        );
      }
    });

    test('PUT profile 非法 avatarHash 返回 400，空串表示清除', () async {
      final HttpClientResponse bad = await _send(
        client,
        path('/api/v1/profile'),
        method: 'PUT',
        jsonBody: <String, Object?>{'avatarHash': 'not-a-hash'},
      );
      expect(bad.statusCode, 400);

      final HttpClientResponse cleared = await _send(
        client,
        path('/api/v1/profile'),
        method: 'PUT',
        jsonBody: <String, Object?>{'avatarHash': ''},
      );
      expect(cleared.statusCode, 200);
      expect((await _jsonOf(cleared))['avatarHash'], '');
    });

    test('PUT profile 的 name 不是字符串时返回 400', () async {
      final HttpClientResponse response = await _send(
        client,
        path('/api/v1/profile'),
        method: 'PUT',
        jsonBody: <String, Object?>{'name': 123},
      );
      expect(response.statusCode, 400);
    });

    test('profile 请求体超过上限时客户端能完整收到 413（不是连接被重置）', () async {
      // 回归用例：历史上的实现在 request 流没读完时就 throw，
      // 结果是 HttpException: Connection closed before full header was received，
      // 客户端拿不到任何响应。这里既断言状态码，也断言响应头与 JSON 体真的到了。
      final HttpClientRequest request =
          await client.openUrl('PUT', path('/api/v1/profile'));
      request.headers.contentType = ContentType.json;
      request.add(
        utf8.encode(jsonEncode(<String, Object?>{
          'name': 'x' * (kMaxProfileBodyBytes + 10),
        })),
      );
      final HttpClientResponse response = await request.close();

      expect(response.statusCode, HttpStatus.requestEntityTooLarge);
      expect(response.headers.contentType?.mimeType, 'application/json');
      final Map<String, Object?> json = await _jsonOf(response);
      expect(json['code'], LanFileErrorCode.invalidArgument.name);
      expect(json['message'], isA<String>());
    });

    test('超大 body（远超排空上限）也不会把连接拖死', () async {
      // 2 MB：超过 4 KB 的解析上限，但仍在 8 MB 排空上限内，必须拿到可读 413。
      final HttpClientRequest request =
          await client.openUrl('PUT', path('/api/v1/profile'));
      request.headers.contentType = ContentType.json;
      final List<int> filler = utf8.encode('y' * 2000);
      request.add(utf8.encode('{"name":"'));
      for (int i = 0; i < 1000; i++) {
        request.add(filler);
      }
      request.add(utf8.encode('"}'));
      final HttpClientResponse response = await request.close();

      expect(response.statusCode, HttpStatus.requestEntityTooLarge);
      expect(
        (await _jsonOf(response))['code'],
        LanFileErrorCode.invalidArgument.name,
      );
    });

    test('超限请求不影响后续请求（连接未被打死）', () async {
      final HttpClientRequest big =
          await client.openUrl('PUT', path('/api/v1/profile'));
      big.headers.contentType = ContentType.json;
      big.add(utf8.encode(jsonEncode(<String, Object?>{
        'name': 'x' * (kMaxProfileBodyBytes + 10),
      })));
      final HttpClientResponse rejected = await big.close();
      expect(rejected.statusCode, HttpStatus.requestEntityTooLarge);
      await _jsonOf(rejected);

      final HttpClientResponse after =
          await _send(client, path('/api/v1/ping'));
      expect(after.statusCode, 200);
      expect((await _jsonOf(after))['peerId'], kPeerId);
    });
  });
}
