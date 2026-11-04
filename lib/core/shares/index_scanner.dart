// SPDX-License-Identifier: GPL-3.0-only

/// 分享索引扫描器：把 FileRef 树写进 share_item 表。
///
/// 契约硬约束：create 不得阻塞返回，所以扫描永远在后台跑。这里给出的是
/// 「可被 create 排进后台、也能在测试里 await 完成」的显式句柄，
/// 而不是躲在方法体里的 fire-and-forget —— 后者没法断言，也没法等。
library;

import '../contracts/constants.dart';
import '../contracts/errors.dart';
import '../contracts/file_ref.dart';
import '../contracts/store.dart';
import '../contracts/types.dart';
import 'share_guard.dart';

/// 一轮扫描的结果。
final class ScanResult {
  const ScanResult({
    required this.directoriesVisited,
    required this.itemsIndexed,
    required this.truncated,
    required this.failures,
  });

  /// 实际走过的目录数。
  final int directoriesVisited;

  /// 实际写入索引的条目数。
  final int itemsIndexed;

  /// 是否因为上限而提前收手（超大树不强扫，留给实时列举）。
  final bool truncated;

  /// 过程中被跳过的子树数量（越界链接、列举失败、权限不足）。
  final int failures;

  @override
  String toString() =>
      'ScanResult(dirs=$directoriesVisited, items=$itemsIndexed, '
      'truncated=$truncated, failures=$failures)';
}

/// 把一棵 [FileRef] 树扫进 share_item 表。
///
/// 不分页、不阻塞：调用方拿到 Future 自己决定是 await（测试）还是丢到后台（create）。
final class IndexScanner {
  IndexScanner({
    required this.store,
    this.guard = const ShareGuard(),
    this.maxItems = defaultMaxItems,
    this.maxDirectories = defaultMaxDirectories,
    this.batchSize = defaultBatchSize,
  });

  /// 单次扫描写入的条目上限；超大树不强扫，剩下交给实时列举兜底。
  static const int defaultMaxItems = 200000;

  /// 单次扫描访问的目录上限。
  static const int defaultMaxDirectories = 20000;

  /// 每累计多少条刷一次盘；避免几十万条都攒在内存里。
  static const int defaultBatchSize = 500;

  /// 索引写入目标。
  final LanFileStore store;

  /// 准入闸门；扫描时逐条校验 itemKey。
  final ShareGuard guard;

  /// 条目上限。
  final int maxItems;

  /// 目录上限。
  final int maxDirectories;

  /// 批量落盘大小。
  final int batchSize;

  /// 扫描整棵树并写入 [shareId] 的索引。
  ///
  /// 子项键一律由 [FileRef.list] 给出，与 browse 用的是同一坐标系。
  Future<ScanResult> scan({
    required ShareId shareId,
    required FileRef root,
  }) async {
    var visited = 0;
    var indexed = 0;
    var failures = 0;
    var truncated = false;
    final List<ShareItemRecord> batch = <ShareItemRecord>[];

    Future<void> flush() async {
      if (batch.isEmpty) return;
      await store.putItems(List<ShareItemRecord>.unmodifiable(batch));
      batch.clear();
    }

    final List<FileRef> stack = <FileRef>[root];
    while (stack.isNotEmpty) {
      final FileRef directory = stack.removeLast();
      if (visited >= maxDirectories) {
        truncated = true;
        break;
      }
      visited++;

      String? cursor;
      while (true) {
        final FileEntryPage page;
        try {
          page = await directory.list(
            cursor: cursor,
            limit: LanFileConstants.treePageSize,
          );
        } on LanFileException {
          failures++;
          break;
        }
        for (final FileEntry entry in page.entries) {
          if (indexed >= maxItems) {
            truncated = true;
            break;
          }
          try {
            guard.rejectEscapingRelative(entry.itemKey.value);
          } on LanFileException {
            failures++;
            continue;
          }
          batch.add(
            ShareItemRecord(
              shareId: shareId,
              itemKey: entry.itemKey,
              size: entry.isDirectory ? 0 : (entry.size ?? 0),
              isDir: entry.isDirectory,
              mtime: entry.modifiedAt,
              mime: entry.mime,
            ),
          );
          indexed++;
          if (entry.isDirectory) {
            try {
              stack.add(await directory.child(entry.itemKey));
            } on LanFileException {
              failures++;
            }
          }
          if (batch.length >= batchSize) {
            await flush();
          }
        }
        if (truncated) break;
        cursor = page.nextCursor;
        if (cursor == null) break;
      }
      if (truncated) break;
    }
    await flush();
    return ScanResult(
      directoriesVisited: visited,
      itemsIndexed: indexed,
      truncated: truncated,
      failures: failures,
    );
  }
}