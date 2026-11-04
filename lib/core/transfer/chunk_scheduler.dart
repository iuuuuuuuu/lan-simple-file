// SPDX-License-Identifier: GPL-3.0-only

/// 分片调度：把待下载区间切成不超过 chunkBytes 的任务，按并发上限派工。
///
/// 只负责「切分 + 排队 + 并发闸门」，不关心 HTTP 细节；因此可脱离网络单测。
library;

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:lan_simple_file/core/contracts/contracts.dart';

import 'partial_file.dart';

/// 一个待下载分片，左闭右开。
final class ChunkTask {
  const ChunkTask({
    required this.index,
    required this.start,
    required this.endExclusive,
  });

  /// 全局序号，从 0 开始，便于日志与重试定位。
  final int index;
  final int start;
  final int endExclusive;

  int get length => endExclusive - start;

  ByteInterval get interval => ByteInterval(start, endExclusive);

  @override
  String toString() => 'ChunkTask(#$index, [$start, $endExclusive))';

  @override
  bool operator ==(Object other) =>
      other is ChunkTask &&
      other.index == index &&
      other.start == start &&
      other.endExclusive == endExclusive;

  @override
  int get hashCode => Object.hash(index, start, endExclusive);
}

/// 把待下载区间按 [chunkBytes] 切片。
///
/// 末尾不足一片时给一个短分片；绝不产生 0 长度分片。
List<ChunkTask> planChunks({
  required List<ByteInterval> missing,
  required int chunkBytes,
  int startIndex = 0,
}) {
  if (chunkBytes <= 0) {
    throw ArgumentError.value(chunkBytes, 'chunkBytes', '分片大小必须为正');
  }
  final List<ChunkTask> tasks = <ChunkTask>[];
  int index = startIndex;
  for (final ByteInterval interval in missing) {
    int cursor = interval.start;
    while (cursor < interval.endExclusive) {
      final int end = math.min(cursor + chunkBytes, interval.endExclusive);
      tasks.add(ChunkTask(index: index, start: cursor, endExclusive: end));
      index++;
      cursor = end;
    }
  }
  return tasks;
}

/// 并发调度器：把队列里的任务压到 [concurrency] 个在飞。
///
/// 失败分片会被重新入队（[maxAttempts] 次后放弃），因此「重下该片」
/// 是调度层的能力，而不是调用方手工拼的补丁。
final class ChunkScheduler {
  ChunkScheduler({
    required this.concurrency,
    this.maxAttempts = 3,
    this.onAttemptFailed,
  }) : assert(concurrency > 0);

  /// 同时在飞的分片数；契约要求 8。
  final int concurrency;

  /// 单个分片最多尝试次数（含首次）。
  final int maxAttempts;

  /// 失败回调；用于日志/指标，不影响调度。
  final void Function(ChunkTask task, Object error, int attempt)?
      onAttemptFailed;

  int _attemptsMade = 0;
  int _failures = 0;

  /// 累计尝试次数（含重试），供测试断言「确实重下了」。
  int get attempts => _attemptsMade;

  /// 失败次数（不含最终成功前的重试）。
  int get failures => _failures;

  /// 跑完所有任务；任一任务超过重试上限即抛该任务的最后一个错误。
  ///
  /// [isCancelled] 返回 true 时立即停止派工，未开始的任务不再执行。
  Future<void> run({
    required List<ChunkTask> tasks,
    required Future<void> Function(ChunkTask task, int attempt) worker,
    bool Function()? isCancelled,
  }) async {
    if (tasks.isEmpty) return;
    final Queue<ChunkTask> pending = Queue<ChunkTask>.of(tasks);
    final Map<ChunkTask, int> attemptOf = <ChunkTask, int>{};
    Object? fatal;
    StackTrace? fatalStack;

    Future<void> pump() async {
      while (pending.isNotEmpty) {
        if (isCancelled != null && isCancelled()) return;
        if (fatal != null) return;
        final ChunkTask task = pending.removeFirst();
        final int attempt = (attemptOf[task] ?? 0) + 1;
        attemptOf[task] = attempt;
        _attemptsMade++;
        try {
          await worker(task, attempt);
        } catch (error, stackTrace) {
          _failures++;
          onAttemptFailed?.call(task, error, attempt);
          if (attempt >= maxAttempts) {
            fatal ??= error;
            fatalStack ??= stackTrace;
            return;
          }
          // 重下该片：重新入队尾部，避免立刻打回同一个坏片。
          pending.add(task);
        }
      }
    }

    final List<Future<void>> lanes = <Future<void>>[
      for (int i = 0; i < math.min(concurrency, tasks.length); i++) pump(),
    ];
    await Future.wait(lanes);
    final Object? failure = fatal;
    if (failure != null) {
      Error.throwWithStackTrace(failure, fatalStack ?? StackTrace.current);
    }
  }
}

/// 单次调度里在飞分片数的峰值记录，供测试断言并发真的打满了。
final class ConcurrencyProbe {
  int _active = 0;
  int _peak = 0;

  int get active => _active;

  int get peak => _peak;

  void enter() {
    _active++;
    if (_active > _peak) _peak = _active;
  }

  void leave() {
    if (_active > 0) _active--;
  }

  void reset() {
    _active = 0;
    _peak = 0;
  }
}

/// 校验分片大小不超过契约允许的上限。
void assertChunkWithinContract(int chunkBytes) {
  if (chunkBytes <= 0 || chunkBytes > LanFileConstants.rangeChunkBytes) {
    throw LanFileException(
      LanFileErrorCode.invalidArgument,
      '分片大小 $chunkBytes 超出契约范围 (0, '
      '${LanFileConstants.rangeChunkBytes}]',
    );
  }
}
