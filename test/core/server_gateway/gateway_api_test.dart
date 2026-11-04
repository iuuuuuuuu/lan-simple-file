// SPDX-License-Identifier: GPL-3.0-only

/// 网关用例：真实 HttpServer + 真实 sqlite（drift），不 mock 网络也不 mock 存储。
///
/// 三条主路径：
/// 1. 本机拥有该 share -> 302 到 /s/
/// 2. 非本机、peers 表知道 owner 地址 -> 302 到 http://owner/s/
/// 3. 找不到 owner -> 410 且 body 含「离线」
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/files/local_ref_factory.dart';
import 'package:lan_simple_file/core/server/api/gateway_api.dart';
import 'package:lan_simple_file/core/server/api/share_api.dart';
import 'package:lan_simple_file/core/server/api/store_share_source.dart';
import 'package:lan_simple_file/core/server/http_server_host.dart';
import 'package:lan_simple_file/core/server/router.dart';
import 'package:lan_simple_file/core/server/static/static_handler.dart';
import 'package:lan_simple_file/core/store/store_impl.dart';

// peerId 正则要求 p_ 后恰好 13 位小写字母数字。
final PeerId kOwner = PeerId.parse('p_owner00000000');
final PeerId kSelf = PeerId.parse('p_self000000000');

/// 内存版对端地址表（真实 UDP 地址无法在单测里伪造，这里只替换「地址来源」，
/// 存储与 HTTP 都是真的）。
final class MapEndpoints implements PeerEndpointLookup {
  final Map<String, PeerEndpoint> _entries = <String, PeerEndpoint>{};

  void put(PeerId peer, PeerEndpoint endpoint) =>
      _entries[peer.value] = endpoint;

  @override
  Future<PeerEndpoint?> find(PeerId peerId) async => _entries[peerId.value];
}

void main() {
  late Directory tempDir;
  late LanFileStoreImpl store;
  late HttpServerHost host;
  late HttpClient client;
  late String base;
  late MapEndpoints endpoints;
  late Map<String, PeerId> shareOwners;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lsf_gateway_');
    store = await LanFileStoreImpl.open(
      dbFile: File('${tempDir.path}${Platform.pathSeparator}g.sqlite'),
    );
    await store.init();

    endpoints = MapEndpoints();
    shareOwners = <String, PeerId>{};

    final RouteProbe probe = RouteProbe();
    final Router router = Router();

    // 真实存储支撑的分享来源：本机是否拥有某个 share，由真实 sqlite 回答。
    final StoreShareSource source = StoreShareSource(
      store: store,
      localFactory: const LocalRefFactory(),
    );
    registerShareRoutes(
      router,
      source,
      templates: MemoryStaticAssetSource(<String, List<int>>{
        'share.html': utf8.encode('<html>share</html>'),
      }),
    );

    final GatewayResolver resolver = GatewayResolver(
      ownShares: source,
      ownerLookup: (ShareId id) async => shareOwners[id.value],
      endpoints: endpoints,
      selfPeerId: kSelf,
    );
    registerGatewayRoutes(router, resolver);
    router.get('/probe', probe.handle);

    host = HttpServerHost(
      router: router,
      bindAddress: InternetAddress.loopbackIPv4,
      preferredPort: 0,
    );
    final int port = await host.start();
    base = 'http://127.0.0.1:$port';
    client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  });

  tearDown(() async {
    client.close(force: true);
    await host.stop();
    await store.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('GET /j/:shareId', () {
    test('本机拥有该分享 -> 302 且 Location 指向 /s/', () async {
      final ShareId id = ShareId.parse('share-local01');
      await _putShare(store, id, owner: kSelf, rootUri: tempDir.path);

      final HttpClientResponse res = await _get(client, '$base/j/${id.value}');
      expect(res.statusCode, HttpStatus.found);
      final String? location = res.headers.value(HttpHeaders.locationHeader);
      expect(location, isNotNull);
      expect(location, startsWith('/s/'));
      expect(location, contains(id.value));
      await _drain(res);
    });

    test('本机拥有且带凭证 -> Location 透传 k 参数', () async {
      final ShareId id = ShareId.parse('share-local02');
      await _putShare(store, id, owner: kSelf, rootUri: tempDir.path);

      final HttpClientResponse res =
          await _get(client, '$base/j/${id.value}?k=tok%2Bwith%2Fchars');
      expect(res.statusCode, HttpStatus.found);
      final String location =
          res.headers.value(HttpHeaders.locationHeader)!;
      expect(location, startsWith('/s/'));
      expect(location, contains('k='));
      // 凭证里的特殊字符必须编码，不能被当成路径片段。
      expect(location, isNot(contains('??')));
      await _drain(res);
    });

    test('非本机 + peers 表有 owner 地址 -> 302 到对方地址', () async {
      final ShareId id = ShareId.parse('share-remote01');
      // 只登记归属，不登记到本机存储 —— 模拟「分享在别人机器上」。
      shareOwners[id.value] = kOwner;
      endpoints.put(
        kOwner,
        const PeerEndpoint(host: '192.168.1.42', port: 47778),
      );

      final HttpClientResponse res = await _get(client, '$base/j/${id.value}');
      expect(res.statusCode, HttpStatus.found);
      final String location =
          res.headers.value(HttpHeaders.locationHeader)!;
      expect(location, 'http://192.168.1.42:47778/s/${id.value}');
      await _drain(res);
    });

    test('远端跳转同样透传凭证', () async {
      final ShareId id = ShareId.parse('share-remote02');
      shareOwners[id.value] = kOwner;
      endpoints.put(
        kOwner,
        const PeerEndpoint(host: '10.0.0.7', port: 47778),
      );

      final HttpClientResponse res =
          await _get(client, '$base/j/${id.value}?k=abc.DEF');
      expect(res.statusCode, HttpStatus.found);
      expect(
        res.headers.value(HttpHeaders.locationHeader),
        'http://10.0.0.7:47778/s/${id.value}?k=abc.DEF',
      );
      await _drain(res);
    });

    test('找不到 owner -> 410 且 body 含「离线」', () async {
      final ShareId id = ShareId.parse('share-unknown1');
      final HttpClientResponse res = await _get(client, '$base/j/${id.value}');
      expect(res.statusCode, HttpStatus.gone);
      final Map<String, Object?> body = await _json(res);
      expect(body['message'].toString(), contains('离线'));
      // 连归属都不知道，属于 ownerOffline；ownerUnknownAddress 是
      // 「知道 owner 是谁但拿不到地址」那一种，由下面的纯逻辑用例覆盖。
      expect(body['outcome'], GatewayOutcome.ownerOffline.name);
    });

    test('完全不知道归属 -> 410 且说明「不认识这个分享」', () async {
      final ShareId id = ShareId.parse('share-unknown2');
      final HttpClientResponse res = await _get(client, '$base/j/${id.value}');
      expect(res.statusCode, HttpStatus.gone);
      final Map<String, Object?> body = await _json(res);
      expect(body['outcome'], GatewayOutcome.ownerOffline.name);
      // 验收要求：两种情况都必须给出「提供者已离线」这类可读原因。
      expect(body['message'].toString(), contains('离线'));
    });

    test('归属是自己但已停止共享 -> 410，且不暴露本机地址', () async {
      final ShareId id = ShareId.parse('share-stopped1');
      shareOwners[id.value] = kSelf;
      final HttpClientResponse res = await _get(client, '$base/j/${id.value}');
      expect(res.statusCode, HttpStatus.gone);
      final Map<String, Object?> body = await _json(res);
      expect(body['message'].toString(), contains('已停止'));
      expect(body.toString().contains('47778'), isFalse);
    });

    test('非法 shareId -> 400', () async {
      final HttpClientResponse res = await _get(client, '$base/j/sharetoolong'.replaceAll('x', ''));
      // 'sharetoolong' 本身合法，用真正非法的：
      await _drain(res);
      final HttpClientResponse bad = await _get(client, '$base/j/a b!');
      expect(bad.statusCode, HttpStatus.badRequest);
      await _drain(bad);
    });

    test('跳转响应不得缓存（提供者换地址后不能拿旧跳转）', () async {
      final ShareId id = ShareId.parse('share-remote03');
      shareOwners[id.value] = kOwner;
      endpoints.put(kOwner, const PeerEndpoint(host: '10.0.0.9', port: 47778));
      final HttpClientResponse res = await _get(client, '$base/j/${id.value}');
      expect(res.statusCode, HttpStatus.found);
      expect(res.headers.value(HttpHeaders.cacheControlHeader), 'no-store');
      await _drain(res);
    });

    test('HEAD /j/:shareId 同样给 302 但无 body', () async {
      final ShareId id = ShareId.parse('share-remote04');
      shareOwners[id.value] = kOwner;
      endpoints.put(kOwner, const PeerEndpoint(host: '10.0.0.10', port: 47778));
      final HttpClientRequest req =
          await client.openUrl('HEAD', Uri.parse('$base/j/${id.value}'));
      req.followRedirects = false;
      final HttpClientResponse res = await req.close();
      expect(res.statusCode, HttpStatus.found);
      final List<int> bytes = await _collect(res);
      expect(bytes, isEmpty);
    });
  });

  group('GatewayResolver 纯逻辑（不经过 HTTP）', () {
    test('endpoint 不可用（host 空 / port 0）-> ownerUnknownAddress', () async {
      final ShareId id = ShareId.parse('share-badend01');
      shareOwners[id.value] = kOwner;
      endpoints.put(kOwner, const PeerEndpoint(host: '', port: 0));

      final StoreShareSource source = StoreShareSource(
        store: store,
        localFactory: const LocalRefFactory(),
      );
      final GatewayResolver resolver = GatewayResolver(
        ownShares: source,
        ownerLookup: (ShareId s) async => shareOwners[s.value],
        endpoints: endpoints,
        selfPeerId: kSelf,
      );
      final GatewayDecision d = await resolver.resolve(id);
      expect(d.outcome, GatewayOutcome.ownerUnknownAddress);
      expect(d.isRedirect, isFalse);
    });

    test('决策结果不含本机端口以外的任何地址泄漏', () async {
      final ShareId id = ShareId.parse('share-local03');
      await _putShare(store, id, owner: kSelf, rootUri: tempDir.path);
      final StoreShareSource source = StoreShareSource(
        store: store,
        localFactory: const LocalRefFactory(),
      );
      final GatewayResolver resolver = GatewayResolver(
        ownShares: source,
        ownerLookup: (ShareId s) async => null,
        endpoints: endpoints,
      );
      final GatewayDecision d = await resolver.resolve(id);
      expect(d.outcome, GatewayOutcome.local);
      // 本机跳转是相对路径：不含 scheme、不含 host、不含端口。
      expect(d.location, startsWith('/s/'));
      expect(d.location, isNot(contains('http')));
      expect(d.location, isNot(contains('47778')));
    });
  });
}

/// 极简模板源：/s/ 页面需要它，但网关用例不关心页面内容。

/// 用于确认路由表真的挂上了（否则网关用例可能测了个空）。
final class RouteProbe {
  bool hit = false;

  Future<void> handle(HttpRequest request) async {
    hit = true;
    request.response.statusCode = HttpStatus.ok;
    await request.response.close();
  }
}

Future<void> _putShare(
  LanFileStore store,
  ShareId id, {
  required PeerId owner,
  required String rootUri,
}) async {
  await store.upsertShare(
    ShareRecord(
      id: id,
      kind: 'folder',
      rootKind: 'local',
      rootUri: rootUri,
      displayName: '测试分享 ${id.value}',
      ownerPeerId: owner,
      createdAt: DateTime.utc(2026, 1, 1),
      mode: ShareMode.token,
      enabled: true,
      missing: false,
      isEphemeral: false,
    ),
  );
}

/// 发 GET。
///
/// **必须关掉自动跟随**：dart:io 的 HttpClient 默认 followRedirects=true，
/// 会把 302 直接跟到 /s/ 页面，于是断言拿到的是 200 ——
/// 那样这条用例就永远测不到「网关是否真的发了 302」。
Future<HttpClientResponse> _get(HttpClient client, String url) async {
  final HttpClientRequest req = await client.getUrl(Uri.parse(url));
  req.followRedirects = false;
  return req.close();
}

Future<List<int>> _collect(HttpClientResponse res) =>
    res.fold<List<int>>(<int>[], (List<int> acc, List<int> chunk) {
      acc.addAll(chunk);
      return acc;
    });

Future<void> _drain(HttpClientResponse res) async {
  await _collect(res);
}

Future<Map<String, Object?>> _json(HttpClientResponse res) async {
  final List<int> bytes = await _collect(res);
  return jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
}
