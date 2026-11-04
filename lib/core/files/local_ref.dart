// SPDX-License-Identifier: GPL-3.0-only

/// 桌面端 FileRef 实现：分享根是真实目录，itemKey 是相对 POSIX 路径。
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../contracts/constants.dart';
import '../contracts/errors.dart';
import '../contracts/file_ref.dart';
import '../contracts/types.dart';
import 'relative_path_codec.dart';

/// 单次读取块大小；100 GB 级文件也走这同一条分块路径。
const int _readChunkBytes = 256 * 1024;

/// 目录项在列举阶段的轻量记录（尚未 stat 体积与时间）。
final class _Candidate {
  const _Candidate({
    required this.name,
    required this.key,
    required this.isDirectory,
  });

  final String name;
  final String key;
  final bool isDirectory;
}

/// 以绝对目录为根的 [FileRef] 实现。
///
/// 不变量：
/// - [itemKey] 是相对 root 的 POSIX 路径，root 自身为 [rootItemKey]；
/// - 构造时就把越界拒掉：只要 relativePath 含双点段、是绝对路径、带盘符，
///   或解析后（跟随符号链接 / junction）落在 root 之外，立即抛
///   [LanFileException] 的 invalidArgument，句柄根本不会被创建；
/// - 所有 dart:io 调用都经过 [toIoPath] 加扩展长度前缀，因此超长路径可用；
/// - 体积与偏移全程 int（64 位），不做任何 32 位截断。
final class LocalRef implements FileRef {
  /// [relativePath] 是相对 [rootPath] 的 itemKey；根自身传 [rootItemKey]。
  ///
  /// 越界一律抛 [LanFileException]（invalidArgument）。
  LocalRef({required String rootPath, required String relativePath})
    : _rootPath = normalizeRootPath(rootPath),
      _itemKey = ItemKey.parse(normalizeItemKey(relativePath)),
      _absolutePath = toAbsolutePath(
        normalizeRootPath(rootPath),
        ItemKey.parse(normalizeItemKey(relativePath)),
      );

  /// 打开分享根本身。
  static LocalRef root(String rootPath) =>
      LocalRef(rootPath: rootPath, relativePath: rootItemKey);

  final String _rootPath;
  final ItemKey _itemKey;
  final String _absolutePath;

  /// 分享根的绝对路径（不带扩展长度前缀）。
  String get rootPath => _rootPath;

  /// 本句柄的绝对路径（不带扩展长度前缀）。
  ///
  /// 仅桌面端可用；跨端代码必须只依赖 [FileRef] 契约。
  String get absolutePath => _absolutePath;

  @override
  ItemKey get itemKey => _itemKey;

  @override
  String get displayName {
    if (_itemKey.value == rootItemKey) {
      return p.basename(_rootPath);
    }
    final int cut = _itemKey.value.lastIndexOf('/');
    return cut < 0 ? _itemKey.value : _itemKey.value.substring(cut + 1);
  }

  @override
  bool get isDirectory {
    try {
      return FileSystemEntity
              .typeSync(toIoPath(_absolutePath), followLinks: true) ==
          FileSystemEntityType.directory;
    } catch (_) {
      // 类型探测失败（不存在、权限不足、路径非法）一律当作不是目录。
      return false;
    }
  }

  @override
  Future<bool> exists() async {
    try {
      final FileSystemEntityType type = FileSystemEntity.typeSync(
        toIoPath(_absolutePath),
        followLinks: true,
      );
      return type != FileSystemEntityType.notFound;
    } catch (_) {
      // 契约要求：文件被删除或权限不足返回 false，不得抛异常。
      return false;
    }
  }

  @override
  Future<int> length() async {
    if (isDirectory) {
      return 0;
    }
    try {
      return await File(toIoPath(_absolutePath)).length();
    } on FileSystemException catch (e) {
      throw _mapIoError(e, '取文件长度失败');
    }
  }

  @override
  Future<DateTime?> lastModified() async {
    try {
      final FileStat stat = await FileStat.stat(toIoPath(_absolutePath));
      if (stat.type == FileSystemEntityType.notFound) {
        return null;
      }
      return stat.modified;
    } catch (_) {
      return null;
    }
  }

  @override
  FileEntry toEntry() {
    final FileStat? stat = _statOrNull();
    if (isDirectory) {
      return FileEntry(
        itemKey: _itemKey,
        name: displayName,
        kind: EntryKind.directory,
        modifiedAt: stat?.modified,
      );
    }
    return FileEntry(
      itemKey: _itemKey,
      name: displayName,
      kind: EntryKind.file,
      size: stat?.size,
      modifiedAt: stat?.modified,
    );
  }

  @override
  Future<FileEntryPage> list({
    String? cursor,
    int limit = LanFileConstants.treePageSize,
  }) async {
    if (!isDirectory) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '只有目录可以列举：${_itemKey.value}',
      );
    }
    if (limit <= 0) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '分页大小必须为正数，实际为 $limit',
      );
    }
    final List<_Candidate> candidates = _collectChildren();
    // 契约要求「按 name 排序后稳定分页」。字符串比较基于 UTF-16 码元，
    // 桌面与安卓完全一致，因此游标跨端可复现。
    candidates.sort((_Candidate a, _Candidate b) => a.name.compareTo(b.name));

    int begin = 0;
    if (cursor != null && cursor.isNotEmpty) {
      // 游标是上一页最后一条的 itemKey；键不大于它的一律跳过。
      while (begin < candidates.length &&
          candidates[begin].key.compareTo(cursor) <= 0) {
        begin++;
      }
    }
    final int end = begin + limit < candidates.length
        ? begin + limit
        : candidates.length;
    final List<FileEntry> entries = <FileEntry>[
      for (int i = begin; i < end; i++) _toEntry(candidates[i]),
    ];
    // 只有真还有下一页时才给游标，避免调用方多打一次空请求。
    final String? nextCursor = end < candidates.length && end > begin
        ? candidates[end - 1].key
        : null;
    return FileEntryPage(entries: entries, nextCursor: nextCursor);
  }

  @override
  Future<FileRef> child(ItemKey childKey) async {
    // 契约（file_ref.dart）已焊死：childKey 只有一个合法坐标系，即根锚定的
    // 完整 itemKey，与 list() 产出的 FileEntry.itemKey 完全一致。这里不做
    // 任何「相对本节点的名字」的二次解释——双解释会让同一个入参在不同节点
    // 上解析出不同路径。越界与非法键由 LocalRef 构造器拒绝。
    return LocalRef(rootPath: _rootPath, relativePath: childKey.value);
  }

  @override
  Stream<List<int>> openRead({int? start, int? endExclusive}) async* {
    final int from = start ?? 0;
    if (from < 0) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        'start 不能为负：$from',
      );
    }
    if (endExclusive != null && endExclusive < from) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        'endExclusive($endExclusive) 不能小于 start($from)',
      );
    }
    if (isDirectory) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '目录不支持字节读取：${_itemKey.value}',
      );
    }
    final int total = await length();
    if (from > total) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        'start($from) 超出文件长度($total)',
      );
    }
    if (endExclusive != null && endExclusive > total) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        'endExclusive($endExclusive) 超出文件长度($total)',
      );
    }
    final int stop = endExclusive ?? total;
    if (stop == from) {
      return;
    }
    final RandomAccessFile raf;
    try {
      raf = await File(toIoPath(_absolutePath)).open();
    } on FileSystemException catch (e) {
      throw _mapIoError(e, '打开文件失败');
    }
    try {
      int position = from;
      while (position < stop) {
        final int remaining = stop - position;
        final int want = remaining > _readChunkBytes
            ? _readChunkBytes
            : remaining;
        await raf.setPosition(position);
        final List<int> chunk = await raf.read(want);
        if (chunk.isEmpty) {
          // 契约要求产出长度恰为 endExclusive - start；读不满就是被截断。
          throw LanFileException(
            LanFileErrorCode.io,
            '文件在读取期间被截断：${_itemKey.value}'
            '（已读 $position，目标 $stop）',
          );
        }
        yield chunk;
        position += chunk.length;
      }
    } on FileSystemException catch (e) {
      throw _mapIoError(e, '读取文件失败');
    } finally {
      await raf.close();
    }
  }

  @override
  Future<String> fingerprint() async {
    final FileStat stat;
    try {
      stat = await FileStat.stat(toIoPath(_absolutePath));
    } on FileSystemException catch (e) {
      throw _mapIoError(e, '读取文件属性失败');
    }
    if (stat.type == FileSystemEntityType.notFound) {
      throw LanFileException(
        LanFileErrorCode.notFound,
        '文件已不存在：${_itemKey.value}',
      );
    }
    final int size = stat.type == FileSystemEntityType.directory
        ? 0
        : stat.size;
    return '$size-${stat.modified.millisecondsSinceEpoch}';
  }

  @override
  String toString() => 'LocalRef($_rootPath :: ${_itemKey.value})';

  // -------------------------------------------------------------------------
  // 内部实现
  // -------------------------------------------------------------------------

  FileStat? _statOrNull() {
    try {
      final FileStat stat = FileStat.statSync(toIoPath(_absolutePath));
      return stat.type == FileSystemEntityType.notFound ? null : stat;
    } catch (_) {
      return null;
    }
  }

  /// 列举直接子项；逃出 root 的符号链接 / junction 直接跳过，不让一条外链
  /// 把整个目录变成不可浏览。
  List<_Candidate> _collectChildren() {
    final List<_Candidate> result = <_Candidate>[];
    final Directory directory = Directory(toIoPath(_absolutePath));
    final List<FileSystemEntity> entities;
    try {
      entities = directory.listSync();
    } on FileSystemException catch (e) {
      throw _mapIoError(e, '列举目录失败');
    }
    for (final FileSystemEntity entity in entities) {
      final String childPath = stripExtendedPrefix(entity.path);
      final String name = p.basename(childPath);
      final String key;
      try {
        key = toItemKey(_rootPath, childPath);
      } on LanFileException {
        // 越界（符号链接 / junction 指向 root 之外）：不暴露给分享。
        continue;
      }
      final bool isDir;
      try {
        isDir =
            FileSystemEntity.typeSync(childPath, followLinks: true) ==
            FileSystemEntityType.directory;
      } on FileSystemException {
        continue;
      }
      result.add(
        _Candidate(name: name, key: key, isDirectory: isDir),
      );
    }
    return result;
  }

  FileEntry _toEntry(_Candidate candidate) {
    final String absolute = p.join(_rootPath, candidate.key);
    if (candidate.isDirectory) {
      return FileEntry(
        itemKey: ItemKey.parse(candidate.key),
        name: candidate.name,
        kind: EntryKind.directory,
        modifiedAt: _statOf(absolute)?.modified,
      );
    }
    final FileStat? stat = _statOf(absolute);
    return FileEntry(
      itemKey: ItemKey.parse(candidate.key),
      name: candidate.name,
      kind: EntryKind.file,
      size: stat?.size,
      modifiedAt: stat?.modified,
    );
  }

  /// 页内某项恰好被删掉时返回 null：体积与时间留空，不炸掉整页。
  FileStat? _statOf(String absolutePath) {
    try {
      final FileStat stat = FileStat.statSync(toIoPath(absolutePath));
      return stat.type == FileSystemEntityType.notFound ? null : stat;
    } catch (_) {
      return null;
    }
  }
}

/// 把 dart:io 的原始错误映射成带错误码的 [LanFileException]。
LanFileException _mapIoError(FileSystemException e, String what) {
  final int? code = e.osError?.errorCode;
  final LanFileErrorCode mapped;
  switch (code) {
    case 2:
    case 3:
      mapped = LanFileErrorCode.notFound;
    case 5:
    case 32:
      mapped = LanFileErrorCode.accessDenied;
    default:
      mapped = LanFileErrorCode.io;
  }
  return LanFileException(
    mapped,
    '$what：${e.path}（${e.message}）',
    cause: e,
  );
}