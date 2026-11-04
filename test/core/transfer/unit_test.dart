// SPDX-License-Identifier: GPL-3.0-only

/// 纯函数与组件级测试：区间合并、分片规划、调度重试、校验、限速。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/transfer/checksum.dart';
import 'package:lan_simple_file/core/transfer/chunk_scheduler.dart';
import 'package:lan_simple_file/core/transfer/partial_file.dart';
import 'package:lan_simple_file/core/transfer/speed_limiter.dart';

void main() {
  group('mergeIntervals', () {
    test('相邻区间必须合并（[0,10)+[10,20) → [0,20)）', () {
      final List<ByteInterval> merged = mergeIntervals(<ByteInterval>[
        const ByteInterval(0, 10),
        const ByteInterval(10, 20),
      ]);
      expect(merged, <ByteInterval>[const ByteInterval(0, 20)]);
    });

    test('重叠区间合并取并集', () {
      final List<ByteInterval> merged = mergeIntervals(<ByteInterval>[
        const ByteInterval(0, 15),
        const ByteInterval(5, 20),
      ]);
      expect(merged, <ByteInterval>[const ByteInterval(0, 20)]);
    });

    test('乱序输入先排序再合并', () {
      final List<ByteInterval> merged = mergeIntervals(<ByteInterval>[
        const ByteInterval(50, 60),
        const ByteInterval(0, 10),
        const ByteInterval(10, 20),
        const ByteInterval(5, 15),
      ]);
      expect(merged, <ByteInterval>[
        const ByteInterval(0, 20),
        const ByteInterval(50, 60),
      ]);
    });

    test('完全包含的区间被吸收', () {
      final List<ByteInterval> merged = mergeIntervals(<ByteInterval>[
        const ByteInterval(0, 100),
        const ByteInterval(10, 20),
      ]);
      expect(merged, <ByteInterval>[const ByteInterval(0, 100)]);
    });

    test('空区间被丢弃，空输入返回空', () {
      expect(mergeIntervals(<ByteInterval>[]), isEmpty);
      expect(
        mergeIntervals(<ByteInterval>[const ByteInterval(5, 5)]),
        isEmpty,
      );
    });
  });

  group('missingIntervals', () {
    test('无进度时整份缺失', () {
      expect(
        missingIntervals(100, <ByteInterval>[]),
        <ByteInterval>[const ByteInterval(0, 100)],
      );
    });

    test('中间缺口被正确切出', () {
      expect(
        missingIntervals(100, <ByteInterval>[
          const ByteInterval(0, 20),
          const ByteInterval(60, 80),
        ]),
        <ByteInterval>[
          const ByteInterval(20, 60),
          const ByteInterval(80, 100),
        ],
      );
    });

    test('全部完成返回空', () {
      expect(
        missingIntervals(100, <ByteInterval>[const ByteInterval(0, 100)]),
        isEmpty,
      );
    });

    test('超出 total 的区间被裁剪', () {
      expect(
        missingIntervals(50, <ByteInterval>[const ByteInterval(0, 999)]),
        isEmpty,
      );
      expect(
        missingIntervals(50, <ByteInterval>[const ByteInterval(40, 999)]),
        <ByteInterval>[const ByteInterval(0, 40)],
      );
    });
  });

  group('planChunks', () {
    test('按 chunkBytes 切片，末片可短', () {
      final List<ChunkTask> tasks = planChunks(
        missing: <ByteInterval>[const ByteInterval(0, 250)],
        chunkBytes: 100,
      );
      expect(tasks.map((ChunkTask t) => '${t.start}-${t.endExclusive}'),
          <String>['0-100', '100-200', '200-250']);
      expect(tasks.every((ChunkTask t) => t.length > 0), isTrue);
    });

    test('多段缺口各自切片且序号连续', () {
      final List<ChunkTask> tasks = planChunks(
        missing: <ByteInterval>[
          const ByteInterval(0, 60),
          const ByteInterval(200, 260),
        ],
        chunkBytes: 50,
      );
      expect(tasks.map((ChunkTask t) => t.index), <int>[0, 1, 2, 3]);
      expect(tasks.map((ChunkTask t) => '${t.start}-${t.endExclusive}'),
          <String>['0-50', '50-60', '200-250', '250-260']);
    });

    test('空缺口返回空计划', () {
      expect(
        planChunks(missing: <ByteInterval>[], chunkBytes: 100),
        isEmpty,
      );
    });

    test('非正分片大小直接抛 ArgumentError', () {
      expect(
        () => planChunks(missing: <ByteInterval>[], chunkBytes: 0),
        throwsArgumentError,
      );
    });

    test('大文件不溢出（100GB 级，i64）', () {
      const int huge = 100 * 1024 * 1024 * 1024;
      final List<ChunkTask> tasks = planChunks(
        missing: <ByteInterval>[const ByteInterval(0, huge)],
        chunkBytes: 4 * 1024 * 1024,
      );
      expect(tasks.length, huge ~/ (4 * 1024 * 1024));
      expect(tasks.last.endExclusive, huge);
      expect(tasks.last.start, greaterThan(0x7FFFFFFF),
          reason: '末端偏移必须越过 int32 上限');
    });
  });

  group('ChunkScheduler', () {
    test('并发受 concurrency 限制', () async {
      final ConcurrencyProbe probe = ConcurrencyProbe();
      final ChunkScheduler scheduler = ChunkScheduler(concurrency: 3);
      final List<ChunkTask> tasks = planChunks(
        missing: <ByteInterval>[const ByteInterval(0, 30)],
        chunkBytes: 1,
      );
      await scheduler.run(
        tasks: tasks,
        worker: (ChunkTask task, int attempt) async {
          probe.enter();
          await Future<void>.delayed(const Duration(milliseconds: 5));
          probe.leave();
        },
      );
      expect(probe.peak, lessThanOrEqualTo(3));
      expect(probe.peak, greaterThan(1), reason: '应真的并行，不是串行');
    });

    test('失败分片重下，且最终成功', () async {
      int attemptsForSecond = 0;
      final ChunkScheduler scheduler =
          ChunkScheduler(concurrency: 1, maxAttempts: 3);
      final List<ChunkTask> tasks = planChunks(
        missing: <ByteInterval>[const ByteInterval(0, 2)],
        chunkBytes: 1,
      );
      await scheduler.run(
        tasks: tasks,
        worker: (ChunkTask task, int attempt) async {
          if (task.start == 1) {
            attemptsForSecond++;
            if (attemptsForSecond < 3) {
              throw StateError('第一次失败');
            }
          }
        },
      );
      expect(attemptsForSecond, 3, reason: '失败分片应被重下');
      expect(scheduler.attempts, 4); // task0 一次 + task1 三次
    });

    test('超过 maxAttempts 后抛出最后一个错误', () async {
      final ChunkScheduler scheduler =
          ChunkScheduler(concurrency: 2, maxAttempts: 2);
      final List<ChunkTask> tasks = planChunks(
        missing: <ByteInterval>[const ByteInterval(0, 1)],
        chunkBytes: 1,
      );
      await expectLater(
        scheduler.run(
          tasks: tasks,
          worker: (ChunkTask task, int attempt) async {
            throw StateError('总是失败');
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(scheduler.failures, 2);
    });

    test('isCancelled 生效后不再派工', () async {
      bool cancelled = false;
      int ran = 0;
      final ChunkScheduler scheduler = ChunkScheduler(concurrency: 1);
      final List<ChunkTask> tasks = planChunks(
        missing: <ByteInterval>[const ByteInterval(0, 100)],
        chunkBytes: 1,
      );
      await scheduler.run(
        tasks: tasks,
        isCancelled: () => cancelled,
        worker: (ChunkTask task, int attempt) async {
          ran++;
          if (ran == 3) cancelled = true;
        },
      );
      expect(ran, lessThan(tasks.length));
    });
  });

  group('ChecksumAccumulator', () {
    test('xxh3 流式与一次性结果一致', () {
      final List<int> data = List<int>.generate(1000, (int i) => i % 251);
      final ChecksumAccumulator acc =
          ChecksumAccumulator(ChecksumAlgorithm.xxh3);
      // 故意用不对齐的分块，验证流式累加。
      acc.add(data.sublist(0, 3));
      acc.add(data.sublist(3, 500));
      acc.add(data.sublist(500));
      expect(acc.byteCount, 1000);
      final String streamed = acc.digest();

      final ChecksumAccumulator once =
          ChecksumAccumulator(ChecksumAlgorithm.xxh3)
            ..add(data);
      expect(streamed, once.digest());
      expect(streamed.length, 16);
    });

    test('sha256 流式与 crypto 一次性一致', () {
      final List<int> data = List<int>.generate(4096, (int i) => i % 256);
      final ChecksumAccumulator acc =
          ChecksumAccumulator(ChecksumAlgorithm.sha256);
      for (int i = 0; i < data.length; i += 777) {
        acc.add(data.sublist(i, i + 777 > data.length ? data.length : i + 777));
      }
      expect(acc.digest(), sha256.convert(data).toString());
    });

    test('空输入也有确定摘要', () {
      expect(
        ChecksumAccumulator(ChecksumAlgorithm.sha256).digest(),
        sha256.convert(<int>[]).toString(),
      );
      expect(
        ChecksumAccumulator(ChecksumAlgorithm.xxh3).digest(),
        isNotEmpty,
      );
    });

    test('未知算法名抛 unsupported', () {
      expect(
        () => parseChecksumAlgorithm('md5'),
        throwsA(isA<Exception>()),
      );
    });

    test('checksumEquals 忽略大小写', () {
      expect(checksumEquals('ABCD', 'abcd'), isTrue);
      expect(checksumEquals('abcd', 'abce'), isFalse);
    });

    test('normalizeChecksum 校验长度与字符集', () {
      expect(
        normalizeChecksum('A' * 64, ChecksumAlgorithm.sha256),
        'a' * 64,
      );
      expect(
        () => normalizeChecksum('abc', ChecksumAlgorithm.sha256),
        throwsA(isA<Exception>()),
      );
      expect(
        () => normalizeChecksum('z' * 64, ChecksumAlgorithm.sha256),
        throwsA(isA<Exception>()),
      );
    });

    test('checksumOfFile 与直接读字节一致', () async {
      final Directory dir =
          await Directory.systemTemp.createTemp('lsf_sum_');
      try {
        final File file = File('${dir.path}/a.bin');
        final Uint8List bytes =
            Uint8List.fromList(List<int>.generate(10000, (int i) => i % 256));
        await file.writeAsBytes(bytes);
        expect(
          await checksumOfFile(file, ChecksumAlgorithm.sha256),
          sha256.convert(bytes).toString(),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('TokenBucket / SpeedLimiter', () {
    test('不限速时不产生等待', () async {
      int sleeps = 0;
      final TokenBucket bucket = TokenBucket(
        rateBytesPerSecond: 0,
        clock: () => Duration.zero,
        sleeper: (Duration d) async => sleeps++,
      );
      await bucket.acquire(10 * 1024 * 1024);
      expect(sleeps, 0);
      expect(bucket.isUnlimited, isTrue);
    });

    test('假时钟下按缺口睡眠，总时长约等于 deficit/rate', () async {
      Duration now = Duration.zero;
      final List<Duration> waits = <Duration>[];
      final TokenBucket bucket = TokenBucket(
        rateBytesPerSecond: 1000, // 1000 B/s
        clock: () => now,
        sleeper: (Duration d) async {
          waits.add(d);
          now += d; // 假时钟随睡眠推进
        },
      );
      // 桶从空起步：4000 B @1000B/s 需要整整 4s 的令牌补充时间。
      await bucket.acquire(4000);
      final int totalMicros =
          waits.fold<int>(0, (int s, Duration d) => s + d.inMicroseconds);
      expect(totalMicros, closeTo(4000000, 150000)); // 4s ± 0.15s
    });

    test('真实时钟：限速后耗时不低于理论下限', () async {
      // 4 MB 限速 1 MB/s → 理论 4s，断言不低于 3.5s（留调度误差余量）。
      final SpeedLimiter limiter = SpeedLimiter(globalBytesPerSecond: 1024 * 1024);
      final Stopwatch sw = Stopwatch()..start();
      const int total = 4 * 1024 * 1024;
      const int step = 256 * 1024;
      for (int sent = 0; sent < total; sent += step) {
        await limiter.acquire(step);
      }
      sw.stop();
      expect(
        sw.elapsedMilliseconds,
        greaterThanOrEqualTo(3500),
        reason: '4MB @ 1MB/s 不应快于 3.5s，实测 ${sw.elapsedMilliseconds}ms',
      );
      expect(
        sw.elapsedMilliseconds,
        lessThan(12000),
        reason: '不该慢到离谱，实测 ${sw.elapsedMilliseconds}ms',
      );
    });

    test('按 key 限速比全局更严格时以 key 为准', () async {
      final SpeedLimiter limiter = SpeedLimiter(globalBytesPerSecond: 1000000);
      limiter.setKeyBytesPerSecond('share-a', 200000);
      expect(limiter.keyBytesPerSecond('share-a'), 200000);
      expect(limiter.isKeyLimited('share-a'), isTrue);

      limiter.setKeyBytesPerSecond('share-a', null);
      expect(limiter.keyBytesPerSecond('share-a'), isNull);
    });

    test('两级令牌桶都扣减（key 与全局各过一遍）', () async {
      int keySleeps = 0;
      int globalSleeps = 0;
      Duration now = Duration.zero;
      final SpeedLimiter limiter = SpeedLimiter(
        globalBytesPerSecond: 1000,
        clock: () => now,
        sleeper: (Duration d) async {
          globalSleeps++;
          now += d;
        },
      );
      limiter.setKeyBytesPerSecond('k', 500);
      await limiter.acquire(2000, key: 'k');
      expect(globalSleeps, greaterThan(0));
      expect(keySleeps, 0); // 该用例只统计全局
    });

    test('isCancelled 能中断等待', () async {
      final SpeedLimiter limiter = SpeedLimiter(globalBytesPerSecond: 1);
      bool cancelled = false;
      final Future<void> waiting =
          limiter.acquire(100000, isCancelled: () => cancelled);
      cancelled = true;
      // 不应永远挂住。
      await waiting.timeout(const Duration(seconds: 2));
    });
  });
}
