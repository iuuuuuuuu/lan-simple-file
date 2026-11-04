// SPDX-License-Identifier: GPL-3.0-only

/// webshare 测试夹具：真实 sqlite + 真实临时目录 + 真实 HttpServer。
///
/// 不用 mock 顶替存储与文件系统：配额、落盘、删除都必须在真实磁盘上验证，
/// 否则「10 分钟后文件真的消失」这类断言等于没测。
library;

import 'dart:io';

import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/server/http_server_host.dart';
import 'package:lan_simple_file/core/server/router.dart';
import 'package:lan_simple_file/core/server/static/static_handler.dart';
import 'package:lan_simple_file/core/store/store_impl.dart';
import 'package:lan_simple_file/core/webshare/guest_session_registry.dart';
import 'package:lan_simple_file/core/webshare/session_sweeper.dart';
import 'package:lan_simple_file/core/webshare/staging_area.dart';
import 'package:lan_simple_file/core/webshare/web_share_service_impl.dart';

import 'package:path/path.dart' as p;

import 'package:lan_simple_file/core/server/api/guest_api.dart';

/// 可推进的假时钟：所有「15s / 30s / 10min」判定都靠它，不 sleep。
final class FakeClock {
  FakeClock(this._now);

  DateTime _now;

  DateTime now() => _now;

  void advance(Duration by) {
    _now = _now.add(by);
  }

  void set(DateTime value) {
    _now = value;
  }
}

/// 一套完整的 webshare 夹具。
final class WebShareFixture {
  WebShareFixture._({
    required this.sandbox,
    required this.stagingRoot,
    required this.store,
    required this.clock,
    required this.registry,
    required this.staging,
    required this.sweeper,
    required this.service,
  });

  static Future<WebShareFixture> create({
    DateTime? startAt,
    int quotaBytes = LanFileConstants.webShareQuotaBytes,
  }) async {
    final Directory sandbox = await Directory.systemTemp.createTemp(
      'lsf_webshare_',
    );
    final File dbFile = File(p.join(sandbox.path, 'webshare.db'));
    final LanFileStoreImpl store = await LanFileStoreImpl.open(dbFile: dbFile);

    final String stagingPath = p.join(sandbox.path, 'web-share');
    final Directory stagingRoot = Directory(stagingPath);
    await stagingRoot.create(recursive: true);

    final PeerId host = PeerId.parse('p_7fk3m9x2a1cdk');
    final FakeClock clock = FakeClock(startAt ?? DateTime.utc(2026, 11, 4, 12));
    final GuestSessionRegistry registry = GuestSessionRegistry(
      hostPeer: host,
      clock: GuestClock(now: clock.now),
      quotaBytes: quotaBytes,
    );
    final StagingArea staging = StagingArea(
      rootPath: stagingPath,
      quotaBytes: quotaBytes,
    );
    // 用「延迟读取」打破 service ↔ sweeper 的循环引用：
    // sweeper 需要知道会话名下的 share，而 share 登记在 service 里。
    late final WebShareServiceImpl service;
    final SessionSweeper sweeper = SessionSweeper(
      registry: registry,
      staging: staging,
      store: store,
      revokeSharesOf: (String sessionId) async {
        final List<String> ids = service.sharesOf(sessionId);
        for (final String id in ids) {
          await store.revokeShare(ShareId.parse(id), at: clock.now());
        }
        return ids;
      },
    );
    service = WebShareServiceImpl(
      registry: registry,
      staging: staging,
      sweeper: sweeper,
      store: store,
      hostPeer: host,
    );

    return WebShareFixture._(
      sandbox: sandbox,
      stagingRoot: stagingRoot,
      store: store,
      clock: clock,
      registry: registry,
      staging: staging,
      sweeper: sweeper,
      service: service,
    );
  }

  final Directory sandbox;
  final Directory stagingRoot;
  final LanFileStoreImpl store;
  final FakeClock clock;
  final GuestSessionRegistry registry;
  final StagingArea staging;
  final SessionSweeper sweeper;
  final WebShareServiceImpl service;

  /// 会话目录下是否**一个文件都没有**（「零字节」断言用）。
  Future<int> stagingFileCount(String sessionId) async {
    final Directory dir = Directory(p.join(stagingRoot.path, sessionId));
    if (!await dir.exists()) return 0;
    int count = 0;
    await for (final FileSystemEntity entity in dir.list(recursive: true)) {
      if (entity is File) count++;
    }
    return count;
  }

  /// 临时区里所有文件路径（诊断用）。
  Future<List<String>> stagingFiles(String sessionId) async {
    final Directory dir = Directory(p.join(stagingRoot.path, sessionId));
    if (!await dir.exists()) return <String>[];
    final List<String> paths = <String>[];
    await for (final FileSystemEntity entity in dir.list(recursive: true)) {
      if (entity is File) paths.add(entity.path);
    }
    paths.sort();
    return paths;
  }

  Future<void> dispose() async {
    await service.dispose();
    await store.close();
    if (sandbox.existsSync()) {
      try {
        await sandbox.delete(recursive: true);
      } on FileSystemException {
        // 收尾失败不掩盖真实断言失败。
      }
    }
  }
}

/// 起一个真实 HttpServer，挂上 /w/ 路由。
final class GuestHttpServer {
  GuestHttpServer._(this.host, this.port);

  final HttpServerHost host;
  final int port;

  static Future<GuestHttpServer> start({
    required WebShareServiceImpl service,
    StaticAssetSource? templates,
  }) async {
    final Router router = Router();
    registerGuestRoutes(router, service: service, templates: templates);
    final HttpServerHost host = HttpServerHost(
      router: router,
      bindAddress: InternetAddress.loopbackIPv4,
      preferredPort: 0,
    );
    final int port = await host.start();
    return GuestHttpServer._(host, port);
  }

  Uri url(String path) => Uri.parse('http://127.0.0.1:$port$path');

  Future<void> stop() => host.stop();
}