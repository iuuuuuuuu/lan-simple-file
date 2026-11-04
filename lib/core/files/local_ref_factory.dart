// SPDX-License-Identifier: GPL-3.0-only

/// 桌面端 FileRefFactory：rootUri 是本地绝对目录路径。
library;

import 'dart:io';

import '../contracts/errors.dart';
import '../contracts/file_ref.dart';
import '../contracts/types.dart';
import 'local_ref.dart';
import 'relative_path_codec.dart';

/// Windows / Linux / macOS 上把绝对目录路径当作分享根。
///
/// rootUri 一律按绝对路径解释（Windows 的 D:\share、POSIX 的 /srv/share，
/// 以及扩展长度形式），相对路径直接拒绝，否则「在不在 root 内」会随进程
/// 工作目录漂移。
final class LocalRefFactory implements FileRefFactory {
  const LocalRefFactory();

  @override
  ShareRootKind get rootKind => ShareRootKind.localPath;

  @override
  Future<FileRef> openRoot(String rootUri) async {
    final String root = normalizeRootPath(rootUri);
    if (!Directory(toIoPath(root)).existsSync()) {
      throw LanFileException(
        LanFileErrorCode.notFound,
        '分享根不存在或不是目录：$rootUri',
      );
    }
    return LocalRef.root(root);
  }

  @override
  Future<FileRef> resolve(String rootUri, ItemKey itemKey) async {
    final String root = normalizeRootPath(rootUri);
    // LocalRef 构造时就走了 toAbsolutePath 的越界闸门，这里不重复校验；
    // 但要区分「root 下没有这项」与「itemKey 越界」两种错误码。
    final LocalRef ref = LocalRef(rootPath: root, relativePath: itemKey.value);
    if (itemKey.value != rootItemKey && !await ref.exists()) {
      throw LanFileException(
        LanFileErrorCode.notFound,
        '分享根下不存在该项：${itemKey.value}',
      );
    }
    return ref;
  }

  @override
  Future<bool> canRead(String rootUri) async {
    try {
      final String root = normalizeRootPath(rootUri);
      if (!Directory(toIoPath(root)).existsSync()) {
        return false;
      }
      // 真列一次才能确认权限还在：existsSync 对无读权限的目录也可能返回 true。
      Directory(toIoPath(root)).listSync().take(1).toList();
      return true;
    } on LanFileException {
      return false;
    } on FileSystemException {
      return false;
    }
  }

  @override
  String toString() => 'LocalRefFactory';
}
