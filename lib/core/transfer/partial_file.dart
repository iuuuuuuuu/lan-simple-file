// SPDX-License-Identifier: GPL-3.0-only

/// `.part` + `.partmeta` 续传载体。
///
/// 关键不变量：
/// - 区间一律左闭右开 `[start, endExclusive)`；
/// - [mergeIntervals] 同时合并**重叠**与**相邻**区间，否则 `[0,1024)+[1024,2048)`
///   会被当成两段，续传时重复下载同一片；
/// - partmeta 里记录 etag，etag 变了就拒绝续传（内容已换，旧断点无意义）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lan_simple_file/core/contracts/contracts.dart';

/// 左闭右开的字节区间。
final class ByteInterval implements Comparable<ByteInterval> {
  const ByteInterval(this.start, this.endExclusive);

  /// 单字节区间。
  const ByteInterval.single(int offset)
      : start = offset,
        endExclusive = offset + 1;

  final int start;
  final int endExclusive;

  int get length => endExclusive - start;

  bool get isEmpty => endExclusive <= start;

  /// 是否与 [other] 重叠或首尾相接。
  bool touches(ByteInterval other) =>
      start <= other.endExclusive && other.start <= endExclusive;

  /// 合并两个相交或相邻的区间。
  ByteInterval union(ByteInterval other) => ByteInterval(
        start < other.start ? start : other.start,
        endExclusive > other.endExclusive ? endExclusive : other.endExclusive,
      );

  List<int> toJson() => <int>[start, endExclusive];

  static ByteInterval fromJson(Object? raw) {
    if (raw is! List || raw.length != 2) {
      throw const FormatException('区间必须是 [start, endExclusive]');
    }
    final Object? a = raw[0];
    final Object? b = raw[1];
    if (a is! int || b is! int || a < 0 || b < a) {
      throw const FormatException('区间端点非法');
    }
    return ByteInterval(a, b);
  }

  @override
  int compareTo(ByteInterval other) {
    final int byStart = start.compareTo(other.start);
    if (byStart != 0) return byStart;
    return endExclusive.compareTo(other.endExclusive);
  }

  @override
  String toString() => '[$start, $endExclusive)';

  @override
  bool operator ==(Object other) =>
      other is ByteInterval &&
      other.start == start &&
      other.endExclusive == endExclusive;

  @override
  int get hashCode => Object.hash(start, endExclusive);
}

/// 合并重叠与相邻区间，输出按起点升序且互不相接的列表。
///
/// 例：`[0,10) [10,20) [5,15) [50,60)` → `[0,20) [50,60)`。
List<ByteInterval> mergeIntervals(Iterable<ByteInterval> input) {
  final List<ByteInterval> sorted = input
      .where((ByteInterval interval) => !interval.isEmpty)
      .toList()
    ..sort();
  if (sorted.isEmpty) return <ByteInterval>[];

  final List<ByteInterval> merged = <ByteInterval>[sorted.first];
  for (int i = 1; i < sorted.length; i++) {
    final ByteInterval current = sorted[i];
    final ByteInterval last = merged.last;
    if (last.touches(current)) {
      merged[merged.length - 1] = last.union(current);
    } else {
      merged.add(current);
    }
  }
  return merged;
}

/// 在 `[0, total)` 内扣除 [completed]，返回还需下载的区间。
List<ByteInterval> missingIntervals(
  int total,
  Iterable<ByteInterval> completed,
) {
  if (total <= 0) return <ByteInterval>[];
  final List<ByteInterval> done = mergeIntervals(completed);
  final List<ByteInterval> missing = <ByteInterval>[];
  int cursor = 0;
  for (final ByteInterval interval in done) {
    final int start = interval.start > total ? total : interval.start;
    final int end = interval.endExclusive > total ? total : interval.endExclusive;
    if (start > cursor) {
      missing.add(ByteInterval(cursor, start));
    }
    if (end > cursor) cursor = end;
    if (cursor >= total) break;
  }
  if (cursor < total) missing.add(ByteInterval(cursor, total));
  return missing;
}

/// 把 [completed] 裁剪到 `[0, total)` 内并合并；用于清理脏元数据。
List<ByteInterval> clampIntervals(
  int total,
  Iterable<ByteInterval> completed,
) {
  final List<ByteInterval> clamped = <ByteInterval>[];
  for (final ByteInterval interval in completed) {
    if (interval.start >= total) continue;
    final int end =
        interval.endExclusive > total ? total : interval.endExclusive;
    if (end > interval.start) {
      clamped.add(ByteInterval(interval.start, end));
    }
  }
  return mergeIntervals(clamped);
}

/// `.partmeta` 的线上形态。
final class PartMeta {
  const PartMeta({
    required this.total,
    required this.etag,
    required this.completedRanges,
    this.algorithm,
    this.expectedChecksum,
  });

  final int total;

  /// 下载开始时服务端给的 ETag；空串表示服务端未提供。
  final String etag;
  final List<ByteInterval> completedRanges;
  final String? algorithm;
  final String? expectedChecksum;

  Map<String, Object?> toJson() => <String, Object?>{
        'total': total,
        'etag': etag,
        'completedRanges': completedRanges
            .map((ByteInterval interval) => interval.toJson())
            .toList(),
        if (algorithm != null) 'algorithm': algorithm,
        if (expectedChecksum != null) 'expectedChecksum': expectedChecksum,
      };

  static PartMeta fromJson(Map<String, Object?> json) {
    final Object? total = json['total'];
    if (total is! int || total < 0) {
      throw const FormatException('partmeta 缺少合法 total');
    }
    final Object? etag = json['etag'];
    final Object? ranges = json['completedRanges'];
    final List<ByteInterval> parsed = <ByteInterval>[];
    if (ranges is List) {
      for (final Object? entry in ranges) {
        parsed.add(ByteInterval.fromJson(entry));
      }
    }
    return PartMeta(
      total: total,
      etag: etag is String ? etag : '',
      completedRanges: mergeIntervals(parsed),
      algorithm: json['algorithm'] as String?,
      expectedChecksum: json['expectedChecksum'] as String?,
    );
  }
}

/// etag 不一致时抛出，调用方据此放弃旧断点。
final class EtagMismatchException implements Exception {
  const EtagMismatchException({required this.expected, required this.actual});

  final String expected;
  final String actual;

  @override
  String toString() => 'EtagMismatchException(expected: $expected, actual: $actual)';
}

/// 一个正在下载的文件的磁盘状态。
final class PartialFile {
  PartialFile._({
    required this.targetPath,
    required this.total,
    required String etag,
    List<ByteInterval> completed = const <ByteInterval>[],
  })  : _etag = etag, // ignore: prefer_initializing_formals
        _completed = mergeIntervals(completed);


  /// `.part` 文件路径（目标路径 + `.part`）。
  final String targetPath;

  String get partPath => '$targetPath.part';

  String get metaPath => '$targetPath.partmeta';

  /// 实体总长度；恢复时可不一致，故非 final。
  int total;

  final String _etag;
  List<ByteInterval> _completed;
  RandomAccessFile? _handle;

  String get etag => _etag;

  /// 已完成区间（已合并，只读视图）。
  List<ByteInterval> get completedIntervals => List<ByteInterval>.unmodifiable(_completed);

  /// 已落盘字节数。
  int get completedBytes =>
      _completed.fold<int>(0, (int sum, ByteInterval i) => sum + i.length);

  /// 0 字节实体天然完整：不能要求 completedBytes>0，否则空文件永远完成不了。
  bool get isComplete => completedBytes >= total;

  /// 剩余待下载区间。
  List<ByteInterval> get missing => missingIntervals(total, _completed);

  /// 打开（或新建）`.part` 与元数据。
  ///
  /// [etag] 与已有 partmeta 不一致时抛 [EtagMismatchException]，
  /// 且**不**改动磁盘上的旧断点——是否清除由调用方决定。
  static Future<PartialFile> open({
    required String targetPath,
    required int total,
    required String etag,
  }) async {
    final PartialFile file = PartialFile._(
      targetPath: targetPath,
      total: total,
      etag: etag,
    );
    final File meta = File(file.metaPath);
    if (await meta.exists()) {
      final PartMeta? existing = await file._readMeta();
      if (existing != null) {
        if (existing.etag.isNotEmpty && etag.isNotEmpty && existing.etag != etag) {
          throw EtagMismatchException(expected: existing.etag, actual: etag);
        }
        if (existing.total != total) {
          // 长度变了同样视为不同实体。
          throw EtagMismatchException(expected: existing.etag, actual: etag);
        }
        file._completed = clampIntervals(total, existing.completedRanges);
      }
    }
    return file;
  }

  /// 不读旧元数据，直接构造一个干净断点；调用方负责清掉旧文件。
  factory PartialFile.fresh({
    required String targetPath,
    required int total,
    required String etag,
  }) =>
      PartialFile._(targetPath: targetPath, total: total, etag: etag);

  /// 只读地探测已有断点；没有则返回 null。
  static Future<PartMeta?> peekMeta(String targetPath) async {
    final File meta = File('$targetPath.partmeta');
    if (!await meta.exists()) return null;
    try {
      final String raw = await meta.readAsString();
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;
      return PartMeta.fromJson(decoded);
    } on FormatException {
      return null;
    }
  }

  Future<PartMeta?> _readMeta() async {
    try {
      final String raw = await File(metaPath).readAsString();
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;
      return PartMeta.fromJson(decoded);
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  /// 串行化句柄上的所有操作。
  ///
  /// RandomAccessFile 的「设位置 + 写」是两步，8 个分片并发写同一个句柄会互相
  /// 踩位置，表现为 "An async operation is currently pending"。磁盘操作必须排队。
  Future<void>? _ioChain;

  Future<T> _serialize<T>(Future<T> Function() action) {
    final Future<void> previous = _ioChain ?? Future<void>.value();
    final Completer<void> gate = Completer<void>();
    _ioChain = gate.future;
    return previous.then((_) async {
      try {
        return await action();
      } finally {
        if (!gate.isCompleted) gate.complete();
      }
    });
  }

  Future<RandomAccessFile> _ensureHandle() async {
    final RandomAccessFile? existing = _handle;
    if (existing != null) return existing;
    final File part = File(partPath);
    await part.parent.create(recursive: true);
    final RandomAccessFile handle = await part.open(mode: FileMode.append);
    // 保证文件长度至少为 total，后续按偏移随机写。
    final int length = await handle.length();
    if (length < total) {
      await handle.truncate(total);
    }
    _handle = handle;
    return handle;
  }

  /// 写入一段字节并记录区间。
  ///
  /// 数据长度决定区间末端；越界视为编码错误直接拒绝。
  Future<void> writeAt(int start, List<int> data) async {
    if (data.isEmpty) return;
    final int end = start + data.length;
    if (start < 0 || end > total) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '写入区间 [$start, $end) 超出实体长度 $total',
      );
    }
    await _serialize(() async {
      final RandomAccessFile handle = await _ensureHandle();
      await handle.setPosition(start);
      await handle.writeFrom(data);
      _completed = mergeIntervals(<ByteInterval>[
        ..._completed,
        ByteInterval(start, end),
      ]);
    });
  }

  /// 把进度写回 `.partmeta`（先写临时文件再改名，避免半截 JSON）。
  Future<void> flushMeta({
    String? algorithm,
    String? expectedChecksum,
  }) async {
    final PartMeta meta = PartMeta(
      total: total,
      etag: _etag,
      completedRanges: _completed,
      algorithm: algorithm,
      expectedChecksum: expectedChecksum,
    );
    await _serialize(() async {
      // .part 与 .partmeta 必须成对存在：只有元数据、没有数据文件时，
      // 下一次 open() 读到「无文件 + 零已完成区间」，两种状态自相矛盾。
      await _ensureHandle();
      final File metaFile = File(metaPath);
      await metaFile.parent.create(recursive: true);
      final File temp = File('$metaPath.tmp');
      await temp.writeAsString(jsonEncode(meta.toJson()), flush: true);
      await temp.rename(metaPath);
    });
  }

  /// 关闭底层句柄（不删除文件）。
  Future<void> closeHandle() async {
    await _serialize(_closeHandleInline);
  }

  /// 串行链内部用的关闭动作；调用方必须已在 [_serialize] 里。
  Future<void> _closeHandleInline() async {
    final RandomAccessFile? handle = _handle;
    _handle = null;
    if (handle != null) {
      await handle.flush();
      await handle.close();
    }
  }

  /// 完成下载：把 `.part` 改名为目标文件并删掉 `.partmeta`。
  ///
  /// 「关句柄 + rename」必须在同一个串行任务里完成：分成两步时，
  /// 中间若有别处再次打开句柄，rename 就会撞上文件占用。
  Future<File> finalize() async {
    return _serialize(() async {
      await _closeHandleInline();
      final File part = File(partPath);
      // 用 RandomAccessFile.truncate 收尾，File 没有 truncate 方法。
      final RandomAccessFile handle = await part.open(mode: FileMode.append);
      await handle.truncate(total);
      await handle.close();
      final File target = File(targetPath);
      await target.parent.create(recursive: true);
      if (await target.exists()) {
        await target.delete();
      }
      final File result = await part.rename(targetPath);
      final File meta = File(metaPath);
      if (await meta.exists()) await meta.delete();
      return result;
    });
  }

  /// 丢弃断点（取消时用）。
  Future<void> discard() async {
    await _serialize(() async {
      await _closeHandleInline();
      for (final String path in <String>[partPath, metaPath, '$metaPath.tmp']) {
        final File file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
    });
  }

  /// 重置进度但保留文件（etag 变化后从头下）。
  Future<void> resetProgress() async {
    await _serialize(() async {
      await _closeHandleInline();
      _completed = <ByteInterval>[];
      final File part = File(partPath);
      if (await part.exists()) {
        await part.delete();
      }
      final File meta = File(metaPath);
      if (await meta.exists()) {
        await meta.delete();
      }
    });
  }

  /// 供测试与恢复用：直接注入已完成区间。
  void restoreIntervals(Iterable<ByteInterval> intervals) {
    _completed = clampIntervals(total, intervals);
  }

  /// 供测试用：调整总量。
  void overrideTotal(int next) {
    total = next;
    _completed = clampIntervals(next, _completed);
  }
}