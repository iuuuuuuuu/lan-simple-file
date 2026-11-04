// SPDX-License-Identifier: GPL-3.0-only

/// 文件访问抽象：桌面与安卓差异全部收敛在此，业务层不得直接碰路径。
library;

import 'types.dart';

/// 分享根的形态。
enum ShareRootKind {
  /// 桌面：绝对路径。
  localPath,

  /// 安卓：SAF 树 URI。
  safTree,

  /// 安卓：MediaStore 查询（后续版本）。
  mediaStore,
}

/// 目录项类型。
enum EntryKind { file, directory }

/// 一条文件系统条目。体积与时间允许未知（安卓部分 provider 不返回）。
final class FileEntry {
  const FileEntry({
    required this.itemKey,
    required this.name,
    required this.kind,
    this.size,
    this.modifiedAt,
    this.mime,
  });

  final ItemKey itemKey;
  final String name;
  final EntryKind kind;
  final int? size;
  final DateTime? modifiedAt;
  final String? mime;

  bool get isDirectory => kind == EntryKind.directory;
}

/// 一页目录项；[nextCursor] 为 null 表示已到末尾。
final class FileEntryPage {
  const FileEntryPage({required this.entries, this.nextCursor});

  final List<FileEntry> entries;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

/// 一个可读的文件或目录句柄。
///
/// 所有实现必须满足：
/// - [itemKey] 在同一个 root 内稳定；
/// - [openRead] 的产出总长度等于 `endExclusive - start`（省略 end 时为文件尾）；
/// - 读取越界或文件已消失时抛 LanFileException。
abstract interface class FileRef {
  /// 在 root 内的稳定键。
  ItemKey get itemKey;

  /// 展示用名称（不含路径）。
  String get displayName;

  bool get isDirectory;

  /// 源已失效（被移动、删除、权限撤销）时返回 false。
  Future<bool> exists();

  /// 文件字节数；目录返回 0。
  Future<int> length();

  /// 修改时间；不可得时返回 null。
  Future<DateTime?> lastModified();

  /// 转成可序列化的目录项。
  FileEntry toEntry();

  /// 列出一页子项；对文件调用应抛 LanFileException。
  Future<FileEntryPage> list({String? cursor, int limit});

  /// 取得子项句柄。
  ///
  /// [childKey] 只有一个合法坐标系：**根锚定的完整 itemKey**，与
  /// [list] 产出的 [FileEntry.itemKey] 完全一致。实现不得额外接受
  /// 「相对本节点的名字」这类第二种解释——双解释会让同一入参在不同
  /// 节点上解析出不同路径，是歧义而不是便利。
  Future<FileRef> child(ItemKey childKey);

  /// 流式读取 `[start, endExclusive)`，end 省略读到文件尾。
  Stream<List<int>> openRead({int? start, int? endExclusive});

  /// 用于 ETag 的稳定指纹，形如 `size-mtime`。
  Future<String> fingerprint();
}

/// 由分享根构造 [FileRef] 的工厂；平台各注册一个。
abstract interface class FileRefFactory {
  ShareRootKind get rootKind;

  /// 打开 root 本身。
  Future<FileRef> openRoot(String rootUri);

  /// 解析 root 下某个 itemKey。
  Future<FileRef> resolve(String rootUri, ItemKey itemKey);

  /// root 当前是否仍可读（权限是否被撤回）。
  Future<bool> canRead(String rootUri);
}
