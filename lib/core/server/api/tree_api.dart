// SPDX-License-Identifier: GPL-3.0-only

/// `GET /s/:shareId/tree`：分享内目录的 JSON 分页。
///
/// 分页游标包含上一项的类型与 itemKey；文件夹排在文件前，
/// 因此翻页不重不漏。
library;

import 'dart:io';

import 'package:lan_simple_file/core/contracts/contracts.dart';

import '../../files/relative_path_codec.dart' show rootItemKey;

import '../response.dart';
import '../router.dart';
import 'share_api.dart';

/// 单页默认条目数，取契约里的目录分页大小。
const int kTreeDefaultLimit = LanFileConstants.treePageSize;

/// 单页允许的最大条目数；超过按上限裁剪，不报错。
const int kTreeMaxLimit = 1000;

/// 一页目录项。
final class TreePage {
  const TreePage({required this.entries, required this.nextCursor});

  final List<FileEntry> entries;

  /// 下一页游标；null 表示已到末尾。
  final String? nextCursor;

  /// 线上投影：字段名与前端 JS 约定一致。
  Map<String, Object?> toJson() => <String, Object?>{
    'entries': <Map<String, Object?>>[
      for (final FileEntry entry in entries) _entryJson(entry),
    ],
    'nextCursor': nextCursor,
  };

  static Map<String, Object?> _entryJson(FileEntry entry) => <String, Object?>{
    'key': entry.itemKey.value,
    'name': entry.name,
    'isDir': entry.isDirectory,
    'size': entry.size,
    'modifiedAt': entry.modifiedAt?.millisecondsSinceEpoch,
    'mime': entry.mime,
  };
}

/// 解析 limit 查询参数；缺省用 [kTreeDefaultLimit]，非法或越界给 400。
int parseTreeLimit(String? raw) {
  if (raw == null || raw.isEmpty) {
    return kTreeDefaultLimit;
  }
  final int? parsed = int.tryParse(raw);
  if (parsed == null) {
    throw const LanFileException(
      LanFileErrorCode.invalidArgument,
      'limit 必须是整数',
    );
  }
  if (parsed < 1) {
    throw const LanFileException(
      LanFileErrorCode.invalidArgument,
      'limit 必须大于 0',
    );
  }
  return parsed > kTreeMaxLimit ? kTreeMaxLimit : parsed;
}

/// 解析 cursor 查询参数；空串视为「从头开始」。
String? parseTreeCursor(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  return raw;
}

/// 列出 [target] 下 [key] 指向目录的一页子项。
Future<TreePage> listSharePage(
  ShareTarget target,
  ItemKey key, {
  String? cursor,
  required int limit,
}) async {
  final FileRef ref = await resolveShareItem(target, key);
  if (!ref.isDirectory) {
    if (!target.root.isDirectory && key.value == rootItemKey) {
      return TreePage(
        entries: cursor == null
            ? <FileEntry>[ref.toEntry()]
            : const <FileEntry>[],
        nextCursor: null,
      );
    }
    throw const LanFileException(
      LanFileErrorCode.invalidArgument,
      '该路径不是目录，不能列举',
    );
  }
  final FileEntryPage page = await ref.list(cursor: cursor, limit: limit);
  return TreePage(entries: page.entries, nextCursor: page.nextCursor);
}

/// `GET /s/:shareId/tree?path=&cursor=&limit=`。
Handler shareTreeHandler(ShareSource source) {
  return (HttpRequest request) async {
    final String shareId = _segment(request.uri, 2);
    final ShareTarget target = await requireShare(source, shareId);
    final ItemKey key = decodeSharePath(
      request.uri.queryParameters['path'] ?? '',
      alreadyDecoded: true,
    );
    final TreePage page = await listSharePage(
      target,
      key,
      cursor: parseTreeCursor(request.uri.queryParameters['cursor']),
      limit: parseTreeLimit(request.uri.queryParameters['limit']),
    );
    await jsonResponse(request.response, HttpStatus.ok, {
      ...page.toJson(),
      'rootKey': target.root.itemKey.value,
    });
  };
}

/// 把树形接口注册到 [router] 上。
void registerTreeRoutes(Router router, ShareSource source) {
  router.get('/s/:shareId/tree', shareTreeHandler(source));
}

String _segment(Uri uri, int index) {
  final List<String> parts = uri.path.split('/');
  return index < parts.length ? parts[index] : '';
}
