// SPDX-License-Identifier: GPL-3.0-only

/// /s/ 系列路由：分享浏览页、单文件流，以及路径穿越的唯一闸门。
///
/// 越界判定复用 relative_path_codec 的 normalizeItemKey / toAbsolutePath，
/// 不在别处用字符串前缀比较自行判断「在不在 root 内」。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/files/relative_path_codec.dart';

import '../response.dart';
import '../router.dart';
import '../static/static_handler.dart';

/// 单段原始路径（百分号编码后）的长度上限。
const int kMaxEncodedPathLength = 4096;

/// 分享标识段的最大长度，与 ShareId 正则上限一致。
const int kMaxShareIdLength = 64;

/// 分享浏览页的模板资源路径（相对 assets/web）。
const String kSharePageAsset = 'share.html';

/// 分享浏览页的注入占位符。
const String kShareIdPlaceholder = '__LSF_SHARE_ID__';
const String kShareNamePlaceholder = '__LSF_SHARE_NAME__';
const String kSharePeerPlaceholder = '__LSF_SHARE_PEER__';
const String kShareOwnerNamePlaceholder = '__LSF_SHARE_OWNER_NAME__';
const String kShareOwnerAvatarPlaceholder = '__LSF_SHARE_OWNER_AVATAR__';

/// 反斜杠的码点（Windows 路径分隔符）。
const int _kBackslash = 0x5c;

/// 一次请求要访问的分享。
final class ShareTarget {
  const ShareTarget({
    required this.id,
    required this.displayName,
    required this.root,
    this.ownerPeerId,
    this.ownerName = '',
    this.ownerAvatar = '',
  });

  final ShareId id;

  /// 给访问者看的名字（分享的显示名，不是磁盘上的目录名）。
  final String displayName;

  /// 分享根句柄；本模块只经由 [FileRef] 契约访问它。
  final FileRef root;

  /// 分享归属者；页面用它展示「谁在分享」。
  final PeerId? ownerPeerId;
  final String ownerName;
  final String ownerAvatar;
}

/// /s/ 路由的分享来源。
///
/// 生产环境由分享服务实现；测试与演示用 [MapShareSource]。
abstract interface class ShareSource {
  /// 按标识查分享；不存在、已停止、已撤销时返回 null。
  Future<ShareTarget?> find(ShareId id);
}

/// 进程内定长表实现，供测试与单机演示使用。
final class MapShareSource implements ShareSource {
  MapShareSource([Map<String, ShareTarget>? entries])
    : _entries = <String, ShareTarget>{...?entries};

  final Map<String, ShareTarget> _entries;

  void put(ShareTarget target) {
    _entries[target.id.value] = target;
  }

  void remove(ShareId id) {
    _entries.remove(id.value);
  }

  @override
  Future<ShareTarget?> find(ShareId id) async => _entries[id.value];
}

/// 按字符串解析分享标识；格式非法时直接拒绝，避免拿任意串去查表。
ShareId parseShareId(String raw) {
  if (raw.isEmpty || raw.length > kMaxShareIdLength) {
    throw const LanFileException(LanFileErrorCode.invalidArgument, '分享标识长度非法');
  }
  final ShareId? id = ShareId.tryParse(raw);
  if (id == null) {
    throw const LanFileException(LanFileErrorCode.invalidArgument, '分享标识格式非法');
  }
  return id;
}

/// 取分享；不存在时给可读提示，而不是裸 404。
Future<ShareTarget> requireShare(ShareSource source, String rawShareId) async {
  final ShareId id = parseShareId(rawShareId);
  final ShareTarget? target = await source.find(id);
  if (target == null) {
    throw LanFileException(
      LanFileErrorCode.notFound,
      '分享 ${id.value} 不存在、已停止或已撤销',
    );
  }
  return target;
}

/// 把 /s/:shareId/f/ 之后的原始路径解码成分享内的 itemKey。
///
/// 空路径表示分享根本身（itemKey 为 rootItemKey）。
/// 解出的键仍要经 [normalizeItemKey] 复核一次，双保险。
ItemKey decodeSharePath(String rawTail, {bool alreadyDecoded = false}) {
  if (rawTail.length > kMaxEncodedPathLength) {
    throw const LanFileException(LanFileErrorCode.invalidArgument, '路径过长');
  }
  final String decoded;
  try {
    // decodeFull 不做 '+' -> ' ' 的表单式转换，路径里 '+' 是普通字符。
    decoded = alreadyDecoded ? rawTail : Uri.decodeFull(rawTail);
  } on ArgumentError {
    throw const LanFileException(LanFileErrorCode.invalidArgument, '路径百分号编码非法');
  } on FormatException {
    throw const LanFileException(LanFileErrorCode.invalidArgument, '路径百分号编码非法');
  }
  requireNotTraversal(decoded);
  final String key;
  try {
    key = normalizeItemKey(decoded);
  } on LanFileException catch (error) {
    throw LanFileException(
      LanFileErrorCode.invalidArgument,
      '路径非法: ${error.message}',
      cause: error,
    );
  }
  return ItemKey.parse(key);
}

/// 穿越闸门：命中任一形态即 403，绝不落到文件系统。
///
/// 三种形态都要拦：绝对路径、盘符/UNC、含双点段。
void requireNotTraversal(String decoded) {
  if (decoded.isEmpty) {
    return;
  }
  if (decoded.startsWith('/') ||
      decoded.startsWith(String.fromCharCode(_kBackslash))) {
    throw const LanFileException(
      LanFileErrorCode.accessDenied,
      '拒绝访问：路径不得是绝对路径',
      httpStatus: HttpStatus.forbidden,
    );
  }
  if (RegExp(r'^[A-Za-z]:').hasMatch(decoded)) {
    throw const LanFileException(
      LanFileErrorCode.accessDenied,
      '拒绝访问：路径不得携带盘符',
      httpStatus: HttpStatus.forbidden,
    );
  }
  for (final int unit in decoded.codeUnits) {
    if (unit < 0x20) {
      throw const LanFileException(
        LanFileErrorCode.accessDenied,
        '拒绝访问：路径含控制字符',
        httpStatus: HttpStatus.forbidden,
      );
    }
  }
  final String unified = decoded.replaceAll(
    String.fromCharCode(_kBackslash),
    '/',
  );
  for (final String segment in unified.split('/')) {
    if (segment == '..') {
      throw const LanFileException(
        LanFileErrorCode.accessDenied,
        '拒绝访问：路径不得包含双点段',
        httpStatus: HttpStatus.forbidden,
      );
    }
  }
}

/// 按 itemKey 取分享内的句柄；越界与不存在给不同错误码。
Future<FileRef> resolveShareItem(ShareTarget target, ItemKey key) async {
  try {
    return await _resolve(target.root, key);
  } on LanFileException catch (error) {
    if (error.code == LanFileErrorCode.invalidArgument) {
      throw LanFileException(
        LanFileErrorCode.accessDenied,
        '拒绝访问：${error.message}',
        httpStatus: HttpStatus.forbidden,
        cause: error,
      );
    }
    rethrow;
  }
}

Future<FileRef> _resolve(FileRef root, ItemKey key) {
  final String rootKey = root.itemKey.value;
  // The public root sentinel also addresses provider roots such as primary:1.
  if (key.value == rootItemKey) {
    return Future<FileRef>.value(root);
  }
  if (key.value == rootKey) {
    return Future<FileRef>.value(root);
  }
  // 契约里 child() 的坐标系是「根锚定的完整 itemKey」，因此判定必须与
  // rootKey 的真实形态一致：根键为 '.' 时任何非 '.' 键都是后代，
  // 不能因为 rootKey == '.' 就把所有键都当成根。
  if (rootKey == rootItemKey) {
    return root.child(key);
  }
  if (!key.value.startsWith('$rootKey/')) {
    throw LanFileException(
      LanFileErrorCode.invalidArgument,
      '${key.value} 不在分享根 $rootKey 之下',
    );
  }
  return root.child(key);
}

/// 计算 [itemKey] 相对分享根 [rootKey] 的路径；不在其下时返回 null。
String? shareRelativeKey(String rootKey, String itemKey) {
  if (itemKey == rootKey) {
    return '';
  }
  if (rootKey == rootItemKey) {
    return itemKey;
  }
  final String prefix = '$rootKey/';
  if (!itemKey.startsWith(prefix)) {
    return null;
  }
  return itemKey.substring(prefix.length);
}

/// 把 /s/:shareId/f/:tail 解析成（分享, 键）。
Future<({ShareTarget target, ItemKey key})> resolveSharePath(
  ShareSource source,
  String rawShareId,
  String rawTail,
) async {
  final ShareTarget target = await requireShare(source, rawShareId);
  final ItemKey key = decodeSharePath(rawTail);
  return (target: target, key: key);
}

/// 从请求路径里切出 /s/:shareId/f/ 之后的原始（未解码）片段。
String rawFileTail(Uri uri) {
  final List<String> parts = uri.path.split('/');
  // 形如 ['', 's', '<id>', 'f', ...tail]
  if (parts.length <= 4) {
    return '';
  }
  return parts.sublist(4).join('/');
}

/// 从请求路径里切出 /s/:shareId/zip 之后的原始片段（可空）。
String rawZipTail(Uri uri) => rawFileTail(uri);

/// `GET /s/:shareId/f/*`：单文件流，Range / ETag / HEAD 全部交给
/// [fileRangeResponse]。
Handler shareFileHandler(ShareSource source) {
  return (HttpRequest request) async {
    final String shareId = _segment(request.uri, 2);
    final ({ShareTarget target, ItemKey key}) resolved = await resolveSharePath(
      source,
      shareId,
      rawFileTail(request.uri),
    );
    final FileRef ref = await resolveShareItem(resolved.target, resolved.key);
    if (ref.isDirectory) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        '目录请走 /s/:shareId 浏览页',
      );
    }
    if (!await ref.exists()) {
      throw LanFileException(
        LanFileErrorCode.notFound,
        '文件已失效或已被移走: ${ref.displayName}',
      );
    }
    await fileRangeResponse(request.response, ref, request);
  };
}

/// `GET /s/:shareId`：返回注入了分享信息的浏览页。
Handler sharePageHandler(ShareSource source, StaticAssetSource templates) {
  return (HttpRequest request) async {
    final ShareTarget target = await requireShare(
      source,
      _segment(request.uri, 2),
    );
    final Uint8List? template = await templates.load(kSharePageAsset);
    if (template == null) {
      throw const LanFileException(
        LanFileErrorCode.notFound,
        '缺少页面模板: $kSharePageAsset',
      );
    }
    final String html = utf8
        .decode(template)
        .replaceAll(kShareIdPlaceholder, _escapeHtml(target.id.value))
        .replaceAll(kShareNamePlaceholder, _escapeHtml(target.displayName))
        .replaceAll(kShareOwnerNamePlaceholder, _escapeHtml(target.ownerName))
        .replaceAll(
          kShareOwnerAvatarPlaceholder,
          _escapeHtml(target.ownerAvatar),
        )
        .replaceAll(
          kSharePeerPlaceholder,
          _escapeHtml(target.ownerPeerId?.value ?? ''),
        );
    final List<int> bytes = utf8.encode(html);
    final HttpResponse response = request.response;
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.html;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.contentLength = bytes.length;
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }
    response.add(bytes);
    await response.close();
  };
}

/// 把 /s/ 路由注册到 [router] 上。
void registerShareRoutes(
  Router router,
  ShareSource source, {
  required StaticAssetSource templates,
}) {
  router.get('/s/:shareId', sharePageHandler(source, templates));
  router.get('/s/:shareId/f/*', shareFileHandler(source));
}

String _segment(Uri uri, int index) {
  final List<String> parts = uri.path.split('/');
  return index < parts.length ? parts[index] : '';
}

String _escapeHtml(String raw) {
  final StringBuffer buffer = StringBuffer();
  for (final int rune in raw.runes) {
    switch (rune) {
      case 0x26:
        buffer.write('&amp;');
      case 0x3c:
        buffer.write('&lt;');
      case 0x3e:
        buffer.write('&gt;');
      case 0x22:
        buffer.write('&quot;');
      case 0x27:
        buffer.write('&#39;');
      default:
        buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}
