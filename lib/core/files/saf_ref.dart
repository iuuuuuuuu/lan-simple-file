// SPDX-License-Identifier: GPL-3.0-only

/// 安卓 SAF 的 FileRef 实现。
///
/// itemKey 用 SAF 的 documentId（形如 primary:DCIM/Camera），不是文件系统路径。
/// 首次异步访问会把属性缓存下来，供 toEntry()、displayName、isDirectory 等同步接口使用。
library;

import '../contracts/constants.dart';
import '../contracts/errors.dart';
import '../contracts/file_ref.dart';
import '../contracts/types.dart';
import 'saf_bridge.dart';
import 'directory_order.dart';

/// 一条 SAF 文档句柄。
final class SafRef implements FileRef {
  SafRef({
    required this.bridge,
    required String treeUri,
    required String documentId,
  }) : _treeUri = _requireTreeUri(treeUri),
       _documentId = _requireDocumentId(documentId),
       _itemKey = _toItemKey(documentId);

  /// 内部种子构造：list()/child() 已经拿到属性，避免再打一次通道。
  SafRef._seeded({
    required this.bridge,
    required String treeUri,
    required String documentId,
    required String name,
    required bool isDirectory,
    int? size,
    DateTime? modifiedAt,
    String? mime,
  }) : // 私有字段无法写成命名 initializing formal，只能在此赋值。
       // ignore: prefer_initializing_formals
       _treeUri = treeUri,
       _documentId = documentId,
       _itemKey = ItemKey(documentId),
       _cachedName = name,
       _cachedIsDirectory = isDirectory,
       _cachedSize = size,
       _cachedModifiedAt = modifiedAt,
       _cachedMime = mime,
       _statLoaded = true;

  /// MethodChannel 封装。
  final SafBridge bridge;
  final String _treeUri;
  final String _documentId;
  final ItemKey _itemKey;

  String? _cachedName;
  bool? _cachedIsDirectory;
  int? _cachedSize;
  DateTime? _cachedModifiedAt;
  String? _cachedMime;

  bool _statLoaded = false;
  Future<void>? _statInFlight;

  /// SAF 树 URI。
  String get treeUri => _treeUri;

  /// SAF documentId，同时是 [itemKey] 的取值。
  String get documentId => _documentId;

  @override
  ItemKey get itemKey => _itemKey;

  @override
  String get displayName => _cachedName ?? _nameFromDocumentId(_documentId);

  @override
  bool get isDirectory => _cachedIsDirectory ?? false;

  @override
  Future<bool> exists() async {
    try {
      return await bridge.exists(_treeUri, _documentId);
    } on LanFileException catch (e) {
      if (e.code == LanFileErrorCode.notFound ||
          e.code == LanFileErrorCode.accessDenied) {
        return false;
      }
      rethrow;
    }
  }

  @override
  Future<int> length() async {
    await _ensureStat();
    if (_cachedIsDirectory ?? false) {
      return 0;
    }
    return _cachedSize ?? 0;
  }

  @override
  Future<DateTime?> lastModified() async {
    await _ensureStat();
    return _cachedModifiedAt;
  }

  @override
  FileEntry toEntry() => FileEntry(
    itemKey: _itemKey,
    name: displayName,
    kind: (_cachedIsDirectory ?? false) ? EntryKind.directory : EntryKind.file,
    size: _cachedSize,
    modifiedAt: _cachedModifiedAt,
    mime: _cachedMime,
  );

  @override
  Future<FileEntryPage> list({
    String? cursor,
    int limit = LanFileConstants.treePageSize,
  }) async {
    if (limit < 1 || limit > kSafMaxPageLimit) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        'limit 越界: $limit（允许 1..$kSafMaxPageLimit）',
      );
    }
    await _ensureStat();
    if (!(_cachedIsDirectory ?? false)) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '对文件调用 list: $_documentId',
      );
    }
    final List<Map<String, Object?>> rows = await bridge.listChildren(
      _treeUri,
      _documentId,
      cursor: cursor,
      limit: limit + 1,
    );
    final bool hasMore = rows.length > limit;
    final List<Map<String, Object?>> page = hasMore
        ? rows.sublist(0, limit)
        : rows;
    final List<FileEntry> entries = <FileEntry>[];
    for (final Map<String, Object?> row in page) {
      entries.add(
        SafRef._seeded(
          bridge: bridge,
          treeUri: _treeUri,
          documentId: row['documentId']! as String,
          name: row['name']! as String,
          isDirectory: row['isDirectory']! as bool,
          size: row['size'] as int?,
          modifiedAt: _toDateTime(row['lastModified'] as int?),
          mime: row['mime'] as String?,
        ).toEntry(),
      );
    }
    return FileEntryPage(
      entries: entries,
      nextCursor: hasMore
          ? directoryCursor(
              page.last['documentId'] as String,
              page.last['isDirectory'] as bool,
            )
          : null,
    );
  }

  @override
  Future<FileRef> child(ItemKey childKey) async {
    final String childId = childKey.value;
    if (!childId.startsWith('$_documentId/')) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '不是 $_documentId 的直接子项: $childId',
      );
    }
    final Map<String, Object?> stat = await bridge.statItem(_treeUri, childId);
    return SafRef._seeded(
      bridge: bridge,
      treeUri: _treeUri,
      documentId: childId,
      name: stat['name']! as String,
      isDirectory: stat['isDirectory']! as bool,
      size: stat['size'] as int?,
      modifiedAt: _toDateTime(stat['lastModified'] as int?),
      mime: stat['mime'] as String?,
    );
  }

  @override
  Stream<List<int>> openRead({int? start, int? endExclusive}) async* {
    await _ensureStat();
    if (_cachedIsDirectory ?? false) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '对目录调用 openRead: $_documentId',
      );
    }
    final int from = start ?? 0;
    final int? known = _cachedSize;
    if (known != null) {
      if (from > known) {
        throw LanFileException(
          LanFileErrorCode.invalidArgument,
          'start($from) 超出文件长度($known)',
        );
      }
      if (endExclusive != null && endExclusive > known) {
        throw LanFileException(
          LanFileErrorCode.invalidArgument,
          'endExclusive($endExclusive) 超出文件长度($known)',
        );
      }
    }
    final Stream<List<int>> stream = await bridge.openRead(
      _treeUri,
      _documentId,
      start: start,
      endExclusive: endExclusive,
    );
    yield* stream;
  }

  @override
  Future<String> fingerprint() async {
    await _ensureStat();
    final int size = _cachedSize ?? 0;
    final int mtimeMs = _cachedModifiedAt?.millisecondsSinceEpoch ?? 0;
    return '$size-$mtimeMs';
  }

  Future<void> _ensureStat() {
    if (_statLoaded) {
      return Future<void>.value();
    }
    final Future<void>? inFlight = _statInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final Future<void> future = _loadStat();
    _statInFlight = future;
    return future;
  }

  Future<void> _loadStat() async {
    try {
      final Map<String, Object?> stat = await bridge.statItem(
        _treeUri,
        _documentId,
      );
      _cachedName = stat['name']! as String;
      _cachedIsDirectory = stat['isDirectory']! as bool;
      _cachedSize = stat['size'] as int?;
      _cachedModifiedAt = _toDateTime(stat['lastModified'] as int?);
      _cachedMime = stat['mime'] as String?;
      _statLoaded = true;
    } finally {
      _statInFlight = null;
    }
  }

  static DateTime? _toDateTime(int? millis) {
    if (millis == null || millis <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  static String _nameFromDocumentId(String documentId) {
    final int slash = documentId.lastIndexOf('/');
    if (slash >= 0 && slash + 1 < documentId.length) {
      return documentId.substring(slash + 1);
    }
    final int colon = documentId.indexOf(':');
    if (colon >= 0 && colon + 1 < documentId.length) {
      return documentId.substring(colon + 1);
    }
    return documentId;
  }

  static String _requireTreeUri(String treeUri) {
    if (treeUri.isEmpty) {
      throw LanFileException(LanFileErrorCode.invalidArgument, 'treeUri 不能为空');
    }
    if (!treeUri.startsWith('content://') || !treeUri.contains('/tree/')) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        'treeUri 不是 SAF 树 URI: $treeUri',
      );
    }
    return treeUri;
  }

  static String _requireDocumentId(String documentId) {
    if (documentId.isEmpty) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        'documentId 不能为空',
      );
    }
    for (final int unit in documentId.codeUnits) {
      if (unit < 0x20) {
        throw LanFileException(
          LanFileErrorCode.invalidArgument,
          'documentId 含控制字符',
        );
      }
    }
    return documentId;
  }

  static ItemKey _toItemKey(String documentId) {
    try {
      return ItemKey.parse(documentId);
    } on FormatException catch (e) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        'documentId 非法: ${e.message}',
        cause: e,
      );
    }
  }

  @override
  String toString() => 'SafRef($_documentId)';
}
