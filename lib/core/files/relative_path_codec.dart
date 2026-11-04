// SPDX-License-Identifier: GPL-3.0-only

/// 相对 itemKey 与桌面绝对路径的双向编解码，外加越界判定。
///
/// 这里是唯一的越界闸门：LocalRef、LocalRefFactory 以及后续的 HTTP 路由
/// 都必须经过本文件，不允许在别处用字符串前缀比较自行判断「在不在 root 内」。
///
/// 不变量：
/// - itemKey 永远是 POSIX 风格（分隔符固定为斜杠），相对分享根，可含中文与空格；
/// - 分享根自身的 itemKey 是 [rootItemKey]（点号），因为 ItemKey.parse 拒绝空串；
/// - 任何双点段、绝对路径、盘符、UNC 前缀，以及 canonicalize 之后逃出 root 的路径
///   （符号链接 / junction 逃逸）一律抛 LanFileException 的 invalidArgument。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../contracts/errors.dart';
import '../contracts/types.dart';

/// 分享根自身的 itemKey。
///
/// ItemKey.parse 不接受长度为 0 的键，因此用 POSIX 的「当前目录」表示根。
/// 真实目录项永远不可能叫这个，所以不会与子项冲突。
const String rootItemKey = '.';

const String _bs = '\\';

/// Windows 扩展长度路径前缀（绕过 MAX_PATH = 260 的限制）。
const String _extendedPrefix = '\\\\?\\';

/// Windows 扩展长度 UNC 前缀。
const String _extendedUncPrefix = '\\\\?\\UNC\\';

/// Windows 设备路径前缀。
const String _devicePrefix = '\\\\.\\';

/// 盘符模式，例如 C: 。
final RegExp _drivePattern = RegExp(r'^[A-Za-z]:');

/// 把绝对路径转成可以安全交给 dart:io 的形式。
///
/// Windows 上统一加扩展长度前缀：不加前缀时超过 260 字符的路径在
/// Directory.list 一类调用上会直接失败（本机实测抛 PathNotFoundException，
/// 而同一路径加上前缀就能正常列举）。
String toIoPath(String absolutePath) {
  final String plain = stripExtendedPrefix(absolutePath);
  if (!Platform.isWindows) {
    return plain;
  }
  if (!p.isAbsolute(plain)) {
    throw LanFileException(
      LanFileErrorCode.invalidArgument,
      '路径必须是绝对路径：$absolutePath',
    );
  }
  final String normalized = p.normalize(plain);
  if (normalized.startsWith(_bs + _bs)) {
    // UNC 形式（两个反斜杠开头）转成扩展 UNC 形式。
    return _extendedUncPrefix + normalized.substring(2);
  }
  return _extendedPrefix + normalized;
}

/// 去掉 Windows 的扩展长度前缀与设备前缀，还原成普通绝对路径。
///
/// 非 Windows 上是恒等变换。用于把「I/O 用的路径」换算成「比较用的路径」：
/// package:path 认为带前缀的路径与不带前缀的路径不是同一个路径（前缀会让
/// relative 直接返回原样的绝对路径），所以比较前必须先拆掉。
String stripExtendedPrefix(String path) {
  if (!Platform.isWindows) {
    return path;
  }
  if (path.startsWith(_extendedUncPrefix)) {
    return _bs + _bs + path.substring(_extendedUncPrefix.length);
  }
  if (path.startsWith(_extendedPrefix)) {
    return path.substring(_extendedPrefix.length);
  }
  if (path.startsWith(_devicePrefix)) {
    return path.substring(_devicePrefix.length);
  }
  return path;
}

/// 校验并规范化分享根，返回不带前缀的绝对路径。
///
/// 分享根必须是绝对路径；相对路径一律拒绝，否则「在不在 root 内」这个问题
/// 会随进程工作目录漂移。
String normalizeRootPath(String rootPath) {
  if (rootPath.isEmpty) {
    throw const LanFileException(LanFileErrorCode.invalidArgument, '分享根不能为空');
  }
  final String plain = stripExtendedPrefix(rootPath);
  if (!p.isAbsolute(plain)) {
    throw LanFileException(
      LanFileErrorCode.invalidArgument,
      '分享根必须是绝对路径：$rootPath',
    );
  }
  return p.normalize(plain);
}

/// 校验并规范化一个 itemKey（相对路径），返回 POSIX 风格的标准形式。
///
/// 空串与单个点号都归一成 [rootItemKey]；双点段、绝对路径、盘符、UNC、
/// 控制字符，以及 Windows 上的冒号（NTFS 备用数据流）一律抛 invalidArgument。
String normalizeItemKey(String rawKey) {
  final List<String> segments = _keySegments(rawKey);
  if (segments.isEmpty) {
    return rootItemKey;
  }
  return segments.join('/');
}

/// 把父 itemKey 与子 itemKey 拼成一个新的 itemKey。
///
/// 两个入参都会先各自经过 [normalizeItemKey] 校验，因此越界子键在拼接之前
/// 就已经被拒绝。
String joinItemKey(String parentKey, String childKey) {
  final String parent = normalizeItemKey(parentKey);
  final String child = normalizeItemKey(childKey);
  if (parent == rootItemKey) {
    return child;
  }
  if (child == rootItemKey) {
    return parent;
  }
  return '$parent/$child';
}

/// 绝对路径 → 相对 root 的 itemKey。
///
/// 越出分享根（含跨盘符、符号链接逃逸）抛 invalidArgument。
String toItemKey(String rootPath, String absolutePath) {
  final String root = normalizeRootPath(rootPath);
  final String plain = stripExtendedPrefix(absolutePath);
  if (!p.isAbsolute(plain)) {
    throw LanFileException(
      LanFileErrorCode.invalidArgument,
      '路径必须是绝对路径：$absolutePath',
    );
  }
  final String realRoot = _canonicalize(root);
  final String target = _canonicalize(p.normalize(plain));
  if (!_isWithin(realRoot, target)) {
    throw LanFileException(
      LanFileErrorCode.invalidArgument,
      '路径越出分享根：$absolutePath 不在 $rootPath 之内',
    );
  }
  final String relative = p.relative(target, from: realRoot);
  if (relative == '.' || relative.isEmpty) {
    return rootItemKey;
  }
  if (p.isAbsolute(relative)) {
    // canonicalize 之后仍然拿不到相对路径，说明两边不同卷。
    throw LanFileException(
      LanFileErrorCode.invalidArgument,
      '路径越出分享根：$absolutePath 与 $rootPath 不在同一卷',
    );
  }
  return _keySegments(relative).join('/');
}

/// itemKey → 绝对路径，返回不带扩展长度前缀的普通绝对路径。
///
/// 只要 itemKey 含双点段、是绝对路径、带盘符或 UNC、或 canonicalize 之后
/// 落在 root 之外（符号链接 / junction 逃逸），一律抛 invalidArgument。
String toAbsolutePath(String rootPath, ItemKey itemKey) {
  final String root = normalizeRootPath(rootPath);
  final String rawKey = itemKey.value;
  final List<String> segments = _keySegments(rawKey);
  final String literal = segments.isEmpty
      ? root
      : p.joinAll(<String>[root, ...segments]);
  final String candidate = p.normalize(literal);
  final String realRoot = _canonicalize(root);
  final String realTarget = _canonicalize(candidate);
  if (!_isWithin(realRoot, realTarget)) {
    throw LanFileException(
      LanFileErrorCode.invalidArgument,
      '路径越出分享根：$rawKey 解析为 $realTarget，不在 $rootPath 之内',
    );
  }
  return candidate;
}

/// 纯判定：[absolutePath] 是否落在分享根之内（含分享根本身），不抛异常。
///
/// 无法判定（root 不合法、路径不是绝对路径、解析失败）时返回 false——
/// 对安全闸门来说「判不出来」必须等于「不安全」。
bool isInside(String rootPath, String absolutePath) {
  final String root;
  try {
    root = normalizeRootPath(rootPath);
  } on LanFileException {
    return false;
  }
  final String plain = stripExtendedPrefix(absolutePath);
  if (!p.isAbsolute(plain)) {
    return false;
  }
  final String realRoot = _canonicalize(root);
  final String realTarget = _canonicalize(p.normalize(plain));
  return _isWithin(realRoot, realTarget);
}

// ---------------------------------------------------------------------------
// 内部实现
// ---------------------------------------------------------------------------

/// 把 itemKey 拆成段并逐段校验；返回空列表表示「就是根」。
List<String> _keySegments(String rawKey) {
  if (rawKey.isEmpty) {
    return const <String>[];
  }
  final String unified = rawKey.replaceAll(_bs, '/');
  if (unified.startsWith('/')) {
    throw LanFileException(
      LanFileErrorCode.invalidArgument,
      'itemKey 不得是绝对路径：$rawKey',
    );
  }
  if (unified.startsWith('//')) {
    throw LanFileException(
      LanFileErrorCode.invalidArgument,
      'itemKey 不得携带 UNC 前缀：$rawKey',
    );
  }
  if (_drivePattern.hasMatch(unified)) {
    throw LanFileException(
      LanFileErrorCode.invalidArgument,
      'itemKey 不得携带盘符：$rawKey',
    );
  }
  final List<String> segments = <String>[];
  for (final String segment in unified.split('/')) {
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        'itemKey 不得包含双点段：$rawKey',
      );
    }
    for (final int unit in segment.codeUnits) {
      if (unit < 0x20) {
        throw LanFileException(
          LanFileErrorCode.invalidArgument,
          'itemKey 含控制字符：$rawKey',
        );
      }
    }
    if (Platform.isWindows && segment.contains(':')) {
      // file.txt 加两个冒号再跟 DATA 就是 NTFS 备用数据流，名义上仍在 root 内，
      // 但读到的是另一份内容，不作为分享项暴露。
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        'itemKey 不得包含冒号（Windows 数据流）：$rawKey',
      );
    }
    segments.add(segment);
  }
  return segments;
}

/// 尽量取到真实的规范路径；目标不存在时退化为「最深的已存在祖先 + 剩余段」。
///
/// 这是符号链接 / junction 逃逸的唯一可靠判据：resolveSymbolicLinks
/// 会跟随全部重解析点，返回操作系统认定的真实位置。
String _canonicalize(String plainPath) {
  final String normalized = p.normalize(plainPath);
  try {
    return stripExtendedPrefix(File(normalized).resolveSymbolicLinksSync());
  } on FileSystemException {
    // 目标本身不存在：继续往下找最深的已存在祖先。
  }
  final List<String> split = p.split(normalized);
  for (int take = split.length - 1; take >= 1; take--) {
    final String ancestor = p.joinAll(split.take(take));
    try {
      final String realAncestor = stripExtendedPrefix(
        File(ancestor).resolveSymbolicLinksSync(),
      );
      return p.joinAll(<String>[realAncestor, ...split.skip(take)]);
    } on FileSystemException {
      continue;
    }
  }
  // 连根都解析不了：按字面处理，调用方随后仍会做越界判定。
  return normalized;
}

/// [realTarget] 是否等于或在 [realRoot] 之内。
///
/// package:path 在 Windows 上对 equals / isWithin 已做大小写不敏感比较，
/// 因此 8.3 短名与长名混用时也能正确判等。
bool _isWithin(String realRoot, String realTarget) {
  if (p.equals(realRoot, realTarget)) {
    return true;
  }
  return p.isWithin(realRoot, realTarget);
}
