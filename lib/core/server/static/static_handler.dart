// SPDX-License-Identifier: GPL-3.0-only

/// 内置网页静态资源的读取与响应。
///
/// M0 阶段资源走内存表（测试与无 Flutter 绑定环境可直接喂字节）；
/// 后续接 asset bundle 时只换 [StaticAssetSource] 的实现，响应逻辑不变。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:lan_simple_file/core/contracts/contracts.dart';

import '../router.dart';

/// 内置网页在路由上的挂载点。
const String kWebMountPath = '/web';

/// 静态资源的来源。
abstract interface class StaticAssetSource {
  /// 读取相对路径（不含前导斜杠）对应的字节；不存在返回 null。
  Future<Uint8List?> load(String path);
}

/// 进程内静态资源表，用于测试与后续内联打包。
final class MemoryStaticAssetSource implements StaticAssetSource {
  MemoryStaticAssetSource([Map<String, List<int>>? assets])
      : _assets = <String, Uint8List>{
          for (final MapEntry<String, List<int>> entry
              in (assets ?? const <String, List<int>>{}).entries)
            normalizeAssetPath(entry.key): Uint8List.fromList(entry.value),
        };

  final Map<String, Uint8List> _assets;

  /// 已加载的资源路径。
  Iterable<String> get paths => _assets.keys;

  void put(String path, List<int> bytes) {
    _assets[normalizeAssetPath(path)] = Uint8List.fromList(bytes);
  }

  @override
  Future<Uint8List?> load(String path) async => _assets[normalizeAssetPath(path)];
}

/// 归一化资源路径：去掉前导斜杠、折叠 `..` 与重复斜杠。
///
/// 目录穿越在查表之前就被折叠掉，因此 `../` 不可能命中资源表以外的键。
String normalizeAssetPath(String path) {
  final List<String> segments = <String>[];
  for (final String segment in path.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (segments.isNotEmpty) segments.removeLast();
      continue;
    }
    segments.add(segment);
  }
  return segments.join('/');
}

/// 静态资源响应器。
final class StaticHandler {
  StaticHandler({required this.source, this.cacheControl = 'no-cache'});

  final StaticAssetSource source;

  /// 静态页不缓存，避免升级后浏览器仍用旧 JS。
  final String cacheControl;

  /// 默认入口页。
  static const String indexPath = 'index.html';

  /// 按路径提供资源；未知路径按入口页处理（单页应用回退）。
  Future<void> handle(HttpRequest request, {String? assetPath}) async {
    final String raw = assetPath ?? request.uri.path;
    final String relative = normalizeAssetPath(raw);
    final String target = relative.isEmpty ? indexPath : relative;
    await serveAsset(request, target);
  }

  /// 直接提供一个资源；不存在时抛 404。
  Future<void> serveAsset(HttpRequest request, String path) async {
    final String relative = normalizeAssetPath(path);
    final Uint8List? bytes = await source.load(relative);
    if (bytes == null) {
      throw LanFileException(
        LanFileErrorCode.notFound,
        '没有这个资源: $relative',
      );
    }
    final HttpResponse response = request.response;
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = contentTypeForAsset(relative);
    response.headers.set(HttpHeaders.cacheControlHeader, cacheControl);
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.contentLength = bytes.length;
    if (request.method == 'HEAD' || bytes.isEmpty) {
      await response.close();
      return;
    }
    response.add(bytes);
    await response.close();
  }
}

/// 把静态路由注册到 [router] 上：`/` 与 `/web/**` 都指向静态资源。
///
/// 注意 `/web` 本身不是合法挂载，访问时按入口页回退。
void registerStaticRoutes(
  Router router,
  StaticHandler handler, {
  String mountPath = kWebMountPath,
}) {
  router.get('/', (HttpRequest request) async {
    await handler.handle(request, assetPath: StaticHandler.indexPath);
  });
  router.get('$mountPath/*', (HttpRequest request) async {
    final String path = request.uri.path;
    final String relative = path.length > mountPath.length
        ? path.substring(mountPath.length + 1)
        : StaticHandler.indexPath;
    await handler.handle(
      request,
      assetPath: relative.isEmpty ? StaticHandler.indexPath : relative,
    );
  });
}

/// 按扩展名推断 Content-Type；未知一律 application/octet-stream。
ContentType contentTypeForAsset(String path) {
  final int dot = path.lastIndexOf('.');
  final String ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  switch (ext) {
    case 'html':
    case 'htm':
      return ContentType('text', 'html', charset: 'utf-8');
    case 'js':
    case 'mjs':
      return ContentType('text', 'javascript', charset: 'utf-8');
    case 'css':
      return ContentType('text', 'css', charset: 'utf-8');
    case 'json':
      return ContentType.json;
    case 'svg':
      return ContentType('image', 'svg+xml');
    case 'png':
      return ContentType('image', 'png');
    case 'jpg':
    case 'jpeg':
      return ContentType('image', 'jpeg');
    case 'webp':
      return ContentType('image', 'webp');
    case 'ico':
      return ContentType('image', 'x-icon');
    case 'txt':
      return ContentType('text', 'plain', charset: 'utf-8');
    case 'woff2':
      return ContentType('font', 'woff2');
    default:
      return ContentType.binary;
  }
}
