// SPDX-License-Identifier: GPL-3.0-only

/// 安卓 SAF 桥：把 MethodChannel 收敛成强类型、错误可判定的对象。
///
/// 通道名固定为 [kSafChannelName]；Kotlin 侧实现见
/// android/app/src/main/kotlin/com/lansimplefile/lan_simple_file/saf/ 。
///
/// 约定：Kotlin 侧一律以 PlatformException(code) 表达失败，本类把它映射为
/// [LanFileException]；Dart 侧发出前先做参数校验，非法参数不会打到通道上。
library;

import 'package:flutter/services.dart';

import '../contracts/errors.dart';
import '../contracts/types.dart';

/// 与 Kotlin 侧约定的通道名。
const String kSafChannelName = 'lan.simple.file/saf';

/// 单次读取块大小：256 KiB。
const int kSafReadChunkBytes = 256 * 1024;

/// 单页最大条目数。
///
/// 通道内部允许多取一条（kSafMaxPageLimit + 1）用于探测是否还有下一页。
const int kSafMaxPageLimit = 1000;

/// ItemKey 的长度上限（与 ItemKey.parse 保持一致）。
const int _kMaxKeyLength = 4096;

/// 安卓 SAF 的 MethodChannel 封装。
final class SafBridge {
  // 私有字段与公开命名参数同名冲突，无法用 initializing formal。
  // ignore: prefer_initializing_formals
  const SafBridge({MethodChannel? channel}) : _channel = channel;

  /// 注入点：测试可传入自定义 channel；生产环境留空即用默认通道。
  final MethodChannel? _channel;

  MethodChannel get _resolved =>
      _channel ?? const MethodChannel(kSafChannelName);

  /// 列出一页子项。
  ///
  /// 返回项已归一化为固定键集：documentId / name / isDirectory /
  /// size / lastModified / mime（未知值为 null）。
  /// [cursor] 为上一页最后一条 documentId。
  Future<List<Map<String, Object?>>> listChildren(
    String treeUri,
    String documentId, {
    String? cursor,
    required int limit,
  }) async {
    _requireTreeUri(treeUri, 'treeUri');
    _requireKey(documentId, 'documentId');
    if (limit < 1 || limit > kSafMaxPageLimit + 1) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        'limit 越界: $limit（允许 1..${kSafMaxPageLimit + 1}）',
      );
    }
    if (cursor != null) {
      _requireKey(cursor, 'cursor');
    }
    final Object? raw = await _invoke('listChildren', <String, Object?>{
      'treeUri': treeUri,
      'documentId': documentId,
      'cursor': cursor,
      'limit': limit,
    });
    if (raw is! List) {
      throw LanFileException(
        LanFileErrorCode.internal,
        'listChildren 返回类型异常: ${raw.runtimeType}',
      );
    }
    final List<Map<String, Object?>> items = <Map<String, Object?>>[];
    for (final Object? row in raw) {
      if (row is! Map) {
        throw LanFileException(
          LanFileErrorCode.internal,
          'listChildren 返回项不是 Map: ${row.runtimeType}',
        );
      }
      items.add(_normalizeItem(row, 'listChildren'));
    }
    return items;
  }

  /// 读取单条文档的属性。
  Future<Map<String, Object?>> statItem(
    String treeUri,
    String documentId,
  ) async {
    _requireTreeUri(treeUri, 'treeUri');
    _requireKey(documentId, 'documentId');
    final Object? raw = await _invoke('statItem', <String, Object?>{
      'treeUri': treeUri,
      'documentId': documentId,
    });
    if (raw is! Map) {
      throw LanFileException(
        LanFileErrorCode.internal,
        'statItem 返回类型异常: ${raw.runtimeType}',
      );
    }
    return _normalizeItem(raw, 'statItem');
  }

  /// 打开 [start, endExclusive) 的字节流。
  ///
  /// Kotlin 侧在打开时完成定位（FileInputStream 通道定位 + 跳过兜底）与长度截断，
  /// 之后按 [kSafReadChunkBytes] 分块拉取；流结束或被取消时都会关闭底层句柄。
  Future<Stream<List<int>>> openRead(
    String treeUri,
    String documentId, {
    int? start,
    int? endExclusive,
  }) async {
    _requireTreeUri(treeUri, 'treeUri');
    _requireKey(documentId, 'documentId');
    final int from = start ?? 0;
    if (from < 0) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        'start 不能为负: $from',
      );
    }
    if (endExclusive != null && endExclusive < from) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        'endExclusive($endExclusive) < start($from)',
      );
    }
    final Object? handle = await _invoke('openRead', <String, Object?>{
      'treeUri': treeUri,
      'documentId': documentId,
      'start': start,
      'endExclusive': endExclusive,
    });
    if (handle is! String || handle.isEmpty) {
      throw LanFileException(
        LanFileErrorCode.internal,
        'openRead 未返回句柄: ${handle.runtimeType}',
      );
    }
    return _readStream(handle);
  }

  /// 源是否仍可访问。
  Future<bool> exists(String treeUri, String documentId) async {
    _requireTreeUri(treeUri, 'treeUri');
    _requireKey(documentId, 'documentId');
    final Object? raw = await _invoke('exists', <String, Object?>{
      'treeUri': treeUri,
      'documentId': documentId,
    });
    if (raw is! bool) {
      throw LanFileException(
        LanFileErrorCode.internal,
        'exists 返回类型异常: ${raw.runtimeType}',
      );
    }
    return raw;
  }

  /// 树 URI 的读权限是否仍在（含 persisted permission 校验）。
  Future<bool> canRead(String treeUri) async {
    _requireTreeUri(treeUri, 'treeUri');
    final Object? raw = await _invoke('canRead', <String, Object?>{
      'treeUri': treeUri,
    });
    if (raw is! bool) {
      throw LanFileException(
        LanFileErrorCode.internal,
        'canRead 返回类型异常: ${raw.runtimeType}',
      );
    }
    return raw;
  }

  /// 分块拉取，句柄生命周期绑定到本流。
  Stream<List<int>> _readStream(String handle) async* {
    try {
      while (true) {
        final Object? chunk = await _invoke('readChunk', <String, Object?>{
          'handle': handle,
          'maxBytes': kSafReadChunkBytes,
        });
        if (chunk == null) {
          return;
        }
        if (chunk is! Uint8List) {
          throw LanFileException(
            LanFileErrorCode.internal,
            'readChunk 返回类型异常: ${chunk.runtimeType}',
          );
        }
        if (chunk.isEmpty) {
          return;
        }
        yield chunk;
      }
    } finally {
      await _closeQuietly(handle);
    }
  }

  /// 关闭句柄；失败不影响上游错误，只吞掉关闭本身的异常。
  Future<void> _closeQuietly(String handle) async {
    try {
      await _invoke('closeRead', <String, Object?>{'handle': handle});
    } on LanFileException {
      // 句柄可能已被 Kotlin 侧在 EOF 时回收，关闭失败无需上抛。
    }
  }

  Future<Object?> _invoke(String method, Map<String, Object?> args) async {
    try {
      return await _resolved.invokeMethod<Object?>(method, args);
    } on MissingPluginException catch (e) {
      throw LanFileException(
        LanFileErrorCode.unsupported,
        'SAF 通道不可用（当前不是安卓运行时）: $method',
        cause: e,
      );
    } on PlatformException catch (e) {
      throw _mapPlatformException(e, method);
    }
  }

  Map<String, Object?> _normalizeItem(
    Map<Object?, Object?> raw,
    String method,
  ) {
    final Object? documentId = raw['documentId'];
    final Object? name = raw['name'];
    final Object? isDirectory = raw['isDirectory'];
    final Object? size = raw['size'];
    final Object? lastModified = raw['lastModified'];
    final Object? mime = raw['mime'];
    if (documentId is! String || documentId.isEmpty) {
      throw LanFileException(
        LanFileErrorCode.internal,
        '$method 返回项缺少 documentId',
      );
    }
    if (name is! String) {
      throw LanFileException(
        LanFileErrorCode.internal,
        '$method 返回项缺少 name: $documentId',
      );
    }
    if (isDirectory is! bool) {
      throw LanFileException(
        LanFileErrorCode.internal,
        '$method 返回项缺少 isDirectory: $documentId',
      );
    }
    if (size != null && size is! int) {
      throw LanFileException(
        LanFileErrorCode.internal,
        '$method 返回 size 类型异常: ${size.runtimeType}',
      );
    }
    if (lastModified != null && lastModified is! int) {
      throw LanFileException(
        LanFileErrorCode.internal,
        '$method 返回 lastModified 类型异常: ${lastModified.runtimeType}',
      );
    }
    if (mime != null && mime is! String) {
      throw LanFileException(
        LanFileErrorCode.internal,
        '$method 返回 mime 类型异常: ${mime.runtimeType}',
      );
    }
    return <String, Object?>{
      'documentId': documentId,
      'name': name,
      'isDirectory': isDirectory,
      'size': size,
      'lastModified': lastModified,
      'mime': mime,
    };
  }

  void _requireTreeUri(String treeUri, String field) {
    if (treeUri.isEmpty) {
      throw LanFileException(LanFileErrorCode.invalidArgument, '$field 不能为空');
    }
    if (!treeUri.startsWith('content://') || !treeUri.contains('/tree/')) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '$field 不是 SAF 树 URI: $treeUri',
      );
    }
  }

  void _requireKey(String value, String field) {
    if (value.isEmpty || value.length > _kMaxKeyLength) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '$field 长度非法: ${value.length}',
      );
    }
    for (final int unit in value.codeUnits) {
      if (unit < 0x20) {
        throw LanFileException(
          LanFileErrorCode.invalidArgument,
          '$field 含控制字符',
        );
      }
    }
    try {
      ItemKey.parse(value);
    } on FormatException catch (e) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '$field 非法: ${e.message}',
        cause: e,
      );
    }
  }

  LanFileException _mapPlatformException(PlatformException e, String method) {
    final LanFileErrorCode code = switch (e.code) {
      'invalidArgument' => LanFileErrorCode.invalidArgument,
      'notFound' || 'fileNotFound' => LanFileErrorCode.notFound,
      'accessDenied' || 'security' => LanFileErrorCode.accessDenied,
      'providerOffline' => LanFileErrorCode.providerOffline,
      'unsupported' => LanFileErrorCode.unsupported,
      'conflict' => LanFileErrorCode.conflict,
      'cancelled' => LanFileErrorCode.cancelled,
      'quotaExceeded' => LanFileErrorCode.quotaExceeded,
      'io' => LanFileErrorCode.io,
      _ => LanFileErrorCode.internal,
    };
    return LanFileException(
      code,
      'SAF $method 失败[${e.code}]: ${e.message ?? '(无消息)'}',
      cause: e,
    );
  }
}
