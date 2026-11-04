// SPDX-License-Identifier: GPL-3.0-only

/// 分享根的准入闸门：create 与 relocate 都必须先过这里。
///
/// 这一层的职责是把「用户选了一个目录」变成「一个可以安全分享的根」，
/// 三条硬线全部在此拒绝，绝不放到业务层各写一遍：
/// 1. 分享根本身必须是绝对路径（桌面）或 tree URI（安卓），相对路径一律拒；
/// 2. itemKey 不得含双点段、盘符、UNC 前缀；
/// 3. 任何解析后（跟随符号链接 / junction）落在根之外的目标一律拒。
library;

import '../contracts/errors.dart';
import '../contracts/file_ref.dart';
import '../contracts/types.dart';
import '../files/relative_path_codec.dart';

/// 分享根的校验器。
///
/// 无状态、纯函数式：同样的输入永远得到同样的结论，便于在 create、relocate、
/// 以及后续 HTTP 路由三处复用同一套判定，不出现「这里拦了那里没拦」。
final class ShareGuard {
  const ShareGuard();

  /// 规范化分享根；不合法时抛 [LanFileException]（invalidArgument）。
  ///
  /// 桌面：必须是绝对路径，且规范化后不得包含双点段。
  /// 安卓：必须是 content:// 树 URI（形如
  /// content://com.android.externalstorage.documents/tree/primary%3ADCIM）。
  String normalizeRoot({required ShareRootKind kind, required String rootUri}) {
    final String trimmed = rootUri.trim();
    if (trimmed.isEmpty) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        '分享根不能为空',
      );
    }
    switch (kind) {
      case ShareRootKind.localPath:
        // normalizeRootPath 会拒绝相对路径（含 ..\..\x 这类穿越写法）。
        return normalizeRootPath(trimmed);
      case ShareRootKind.safTree:
        final Uri uri;
        try {
          uri = Uri.parse(trimmed);
        } on FormatException catch (e) {
          throw LanFileException(
            LanFileErrorCode.invalidArgument,
            '分享根不是合法 URI：$trimmed',
            cause: e,
          );
        }
        if (uri.scheme != 'content') {
          throw LanFileException(
            LanFileErrorCode.invalidArgument,
            'SAF 分享根必须是 content:// 树 URI，实际为 $trimmed',
          );
        }
        if (trimmed.contains('..')) {
          throw LanFileException(
            LanFileErrorCode.invalidArgument,
            'SAF 分享根不得包含双点段：$trimmed',
          );
        }
        return trimmed;
      case ShareRootKind.mediaStore:
        throw const LanFileException(
          LanFileErrorCode.unsupported,
          'MediaStore 分享根尚未实现',
        );
    }
  }

  /// 校验 rootUri 下某个 itemKey 能否安全解析。
  ///
  /// 桌面走 [toAbsolutePath]，因此符号链接 / junction 逃逸会在这里被拒；
  /// 安卓只做键本身的形态校验（SAF 的越界由 documentId 前缀约束，
  /// 具体判定在 SafRefFactory.resolve）。
  String normalizeItemKey({
    required ShareRootKind kind,
    required String rootUri,
    required ItemKey itemKey,
  }) {
    rejectEscapingRelative(itemKey.value);
    switch (kind) {
      case ShareRootKind.localPath:
        // 会抛：含双点段 / 绝对路径 / 盘符 / canonicalize 后越界。
        toAbsolutePath(normalizeRoot(kind: kind, rootUri: rootUri), itemKey);
        return itemKey.value;
      case ShareRootKind.safTree:
        return itemKey.value;
      case ShareRootKind.mediaStore:
        throw const LanFileException(
          LanFileErrorCode.unsupported,
          'MediaStore 分享根尚未实现',
        );
    }
  }

  /// 单看一段相对路径是否含越界写法；与平台无关，任何 rootKind 都先过这一关。
  void rejectEscapingRelative(String raw) {
    if (raw.isEmpty) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        'itemKey 不能为空',
      );
    }
    // 统一分隔符后再判：Windows 攻击面同时存在 ..\ 与 ../ 两种写法。
    final String unified = raw.replaceAll('\u005C', '/');
    for (final String segment in unified.split('/')) {
      if (segment == '..') {
        throw LanFileException(
          LanFileErrorCode.invalidArgument,
          'itemKey 不得包含双点段：$raw',
        );
      }
    }
    if (unified.startsWith('/')) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        'itemKey 不得是绝对路径：$raw',
      );
    }
    if (RegExp(r'^[A-Za-z]:').hasMatch(unified)) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        'itemKey 不得携带盘符：$raw',
      );
    }
    if (unified.startsWith('//')) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        'itemKey 不得携带 UNC 前缀：$raw',
      );
    }
  }

  /// 判定分享根当前是否仍然可读；不可读返回 false，不抛异常。
  Future<bool> canRead(
    FileRefFactory factory,
    ShareRootKind kind,
    String rootUri,
  ) async {
    try {
      return await factory.canRead(normalizeRoot(kind: kind, rootUri: rootUri));
    } on LanFileException {
      return false;
    }
  }
}
