// SPDX-License-Identifier: GPL-3.0-only

/// 测试夹具：用真实磁盘文件实现冻结的 [FileRef] 契约。
///
/// 这不是被测逻辑的 mock——它按契约真读磁盘（[LocalFileRef.openRead] 走
/// `dart:io` 的 RandomAccessFile），从而让 [fileRangeResponse] 的端到端测试
/// 面对真实字节流、真实长度与真实偏移。
library;

import 'dart:async';
import 'dart:io';

import 'package:lan_simple_file/core/contracts/contracts.dart';

/// 以绝对路径定位单个文件的 [FileRef] 实现。
final class LocalFileRef implements FileRef {
  LocalFileRef(String absolutePath)
      : _file = File(absolutePath),
        itemKey = ItemKey(absolutePath);

  final File _file;

  @override
  final ItemKey itemKey;

  @override
  String get displayName => _file.uri.pathSegments.isEmpty
      ? _file.path
      : _file.uri.pathSegments.last;

  @override
  bool get isDirectory => false;

  @override
  Future<bool> exists() async => _file.exists();

  @override
  Future<int> length() async {
    if (!await _file.exists()) {
      throw LanFileException(
        LanFileErrorCode.notFound,
        '文件不存在: ${_file.path}',
      );
    }
    return _file.length();
  }

  @override
  Future<DateTime?> lastModified() async {
    if (!await _file.exists()) return null;
    return _file.lastModified();
  }

  @override
  FileEntry toEntry() => FileEntry(
        itemKey: itemKey,
        name: displayName,
        kind: EntryKind.file,
        mime: 'application/octet-stream',
      );

  @override
  Future<FileEntryPage> list({String? cursor, int limit = 200}) {
    throw const LanFileException(
      LanFileErrorCode.unsupported,
      '文件不支持列目录',
    );
  }

  @override
  Future<FileRef> child(ItemKey childKey) {
    throw const LanFileException(
      LanFileErrorCode.unsupported,
      '文件不支持取得子项',
    );
  }

  @override
  Stream<List<int>> openRead({int? start, int? endExclusive}) {
    final int offset = start ?? 0;
    if (offset < 0) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        'start 不能为负',
      );
    }
    final int total = _file.lengthSync();
    if (offset > total) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        'start $offset 超出文件长度 $total',
      );
    }
    int end = endExclusive ?? total;
    if (end > total) end = total;
    if (end < offset) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        'endExclusive $end 小于 start $offset',
      );
    }
    return _file.openRead(offset, end);
  }

  @override
  Future<String> fingerprint() async {
    final int size = await length();
    final FileStat stat = await _file.stat();
    return '$size-${stat.modified.millisecondsSinceEpoch}';
  }
}
