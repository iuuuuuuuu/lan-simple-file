// SPDX-License-Identifier: GPL-3.0-only

/// pause / cancel / resume 与中断判定：全部对真实 HttpServer 跑。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/transfer/transfer_service_impl.dart';

import 'support/range_test_server.dart';

/// 永远连不上的地址，用于只测「未知 id」这类不触网的分支。
final Uri neverReachableUri = Uri.parse('http://127.0.0.1:1/x');

PeerId _peer() => PeerId.parse('p_7fk3m9x2a1cdk');
ShareId _share() => ShareId.parse('share-abc123');
ItemKey _key() => ItemKey.parse('big.bin');

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lsf_ctrl_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException {
        // 极端情况下句柄未释放；不掩盖真实断言失败。
      }
    }
  });

  group('pause / cancel / resume', () {
    test('pause 打断进行中的连接，状态变 paused 且断点保留', () async {
      const int size = 4 * 1024 * 1024;
      final RangeTestServer server = await RangeTestServer.start(size)
        ..delayPerChunk = const Duration(milliseconds: 40);
      final TransferServiceImpl service = TransferServiceImpl(
        resolver: StaticTargetResolver(server.urlFor('f.bin')),
        chunkBytes: 512 * 1024,
      );
      addTearDown(() async {
        await service.dispose();
        await server.stop();
      });

      final Future<TransferRecord> downloading = service.download(
        peer: _peer(),
        share: _share(),
        itemKey: _key(),
        targetDir: tempDir.path,
        fileName: 'out.bin',
      );
      await server.waitFirstRequest();
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final String id = service.taskIds.single;
      await service.pause(id);

      final TransferRecord paused = service.recordOf(id)!;
      expect(paused.status, TransferStatus.paused);
      expect(service.handleOf(id)!.phase, TransferPhase.paused);
      expect(paused.bytesDone, lessThan(size));
      // 断点在。
      expect(File('${tempDir.path}/out.bin.partmeta').existsSync(), isTrue);

      // download 的 Future 应已正常收尾（不是永远挂着）。
      final TransferRecord settled = await downloading.timeout(
        const Duration(seconds: 10),
      );
      expect(settled.status, TransferStatus.paused);
    });

    test('pause 后 resume 能续完，且不重下已完成部分', () async {
      // 用 16MB + 慢速，确保「暂停」发生时一定还没下完（否则用例退化成无效）。
      const int size = 16 * 1024 * 1024;
      final RangeTestServer server = await RangeTestServer.start(size)
        ..delayPerChunk = const Duration(milliseconds: 30);
      final TransferServiceImpl service = TransferServiceImpl(
        resolver: StaticTargetResolver(server.urlFor('f.bin')),
        chunkBytes: 256 * 1024,
      );
      addTearDown(() async {
        await service.dispose();
        await server.stop();
      });

      final Future<TransferRecord> downloading = service.download(
        peer: _peer(),
        share: _share(),
        itemKey: _key(),
        targetDir: tempDir.path,
        fileName: 'out.bin',
      );
      // 任务在探测请求发出之后才入列，因此不能只等「首个请求」——
      // 探测响应也可能被 delayPerChunk 拖住。这里直接轮询任务表。
      final Stopwatch waitBudget = Stopwatch()..start();
      while (service.taskIds.isEmpty &&
          waitBudget.elapsed < const Duration(seconds: 10)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(service.taskIds, hasLength(1), reason: '下载任务应已建立');
      final String id = service.taskIds.single;

      // 等到「有进展但远未完成」再暂停，确保测的是真正的续传路径。
      while (service.recordOf(id)!.bytesDone == 0 &&
          waitBudget.elapsed < const Duration(seconds: 10)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(
        service.recordOf(id)!.bytesDone,
        lessThan(size),
        reason: '暂停前必须还没下完',
      );
      await service.pause(id);
      await downloading;

      final int doneAtPause = service.recordOf(id)!.bytesDone;
      expect(doneAtPause, greaterThan(0), reason: '暂停前应已写下去一些字节');
      expect(doneAtPause, lessThan(size), reason: '暂停时不应已经下完');

      // 提速后续传。
      server.delayPerChunk = Duration.zero;
      server.requests.clear();
      final TransferRecord resumed = await service.resume(id);
      expect(resumed.status, TransferStatus.done);
      expect(resumed.bytesDone, size);

      // 续传阶段的请求字节 = 剩余部分 + 1 字节探测。
      // 关键在于它明显小于「整份再下一遍」的 size*2。
      expect(
        server.totalRequestedBytes,
        lessThan(size + 1 + (size - doneAtPause)),
        reason: 'resume 不应把已完成部分再下一遍',
      );
      expect(
        server.totalRequestedBytes,
        greaterThanOrEqualTo(size - doneAtPause),
        reason: '剩余部分必须真的下完',
      );
      expect(
        await File('${tempDir.path}/out.bin').length(),
        size,
      );
    });

    test('cancel 打断连接、保留断点、标记 failed 且 err=cancelled', () async {
      const int size = 4 * 1024 * 1024;
      final RangeTestServer server = await RangeTestServer.start(size)
        ..delayPerChunk = const Duration(milliseconds: 40);
      final TransferServiceImpl service = TransferServiceImpl(
        resolver: StaticTargetResolver(server.urlFor('f.bin')),
        chunkBytes: 512 * 1024,
      );
      addTearDown(() async {
        await service.dispose();
        await server.stop();
      });

      final Future<TransferRecord> downloading = service.download(
        peer: _peer(),
        share: _share(),
        itemKey: _key(),
        targetDir: tempDir.path,
        fileName: 'out.bin',
      );
      await server.waitFirstRequest();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final String id = service.taskIds.single;
      await service.cancel(id);
      await downloading.timeout(const Duration(seconds: 10));

      final TransferRecord cancelled = service.recordOf(id)!;
      expect(cancelled.status, TransferStatus.failed,
          reason: '契约的 TransferStatus 无 cancelled 值');
      expect(cancelled.err, 'cancelled');
      expect(service.handleOf(id)!.phase, TransferPhase.cancelled);
      // 取消不删断点：之后还能 resume。
      expect(File('${tempDir.path}/out.bin.partmeta').existsSync(), isTrue);
    });

    test('取消后仍可 resume 完成', () async {
      const int size = 1024 * 1024;
      final RangeTestServer server = await RangeTestServer.start(size)
        ..delayPerChunk = const Duration(milliseconds: 30);
      final TransferServiceImpl service = TransferServiceImpl(
        resolver: StaticTargetResolver(server.urlFor('f.bin')),
        chunkBytes: 256 * 1024,
      );
      addTearDown(() async {
        await service.dispose();
        await server.stop();
      });

      final Future<TransferRecord> downloading = service.download(
        peer: _peer(),
        share: _share(),
        itemKey: _key(),
        targetDir: tempDir.path,
        fileName: 'out.bin',
      );
      await server.waitFirstRequest();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final String id = service.taskIds.single;
      await service.cancel(id);
      await downloading;

      server.delayPerChunk = Duration.zero;
      final TransferRecord resumed = await service.resume(id);
      expect(resumed.status, TransferStatus.done);
      expect(await File('${tempDir.path}/out.bin').length(), size);
    });

    test('pause 已完成任务不改变其 done 状态', () async {
      final RangeTestServer server = await RangeTestServer.start(1024);
      final TransferServiceImpl service =
          TransferServiceImpl(resolver: StaticTargetResolver(server.urlFor('f.bin')));
      addTearDown(() async {
        await service.dispose();
        await server.stop();
      });

      await service.download(
        peer: _peer(),
        share: _share(),
        itemKey: _key(),
        targetDir: tempDir.path,
        fileName: 'out.bin',
      );
      final String id = service.taskIds.single;
      expect(service.recordOf(id)!.status, TransferStatus.done);
      await service.pause(id);
      expect(service.recordOf(id)!.status, TransferStatus.done);
    });

    test('未知 id 的 pause / cancel / resume 抛 notFound', () async {
      final TransferServiceImpl service =
          TransferServiceImpl(resolver: StaticTargetResolver(neverReachableUri));
      addTearDown(service.dispose);

      for (final Future<void> Function() action in <Future<void> Function()>[
        () => service.pause('nope'),
        () => service.cancel('nope'),
        () => service.resume('nope'),
      ]) {
        await expectLater(
          action(),
          throwsA(
            isA<LanFileException>().having(
              (LanFileException e) => e.code,
              'code',
              LanFileErrorCode.notFound,
            ),
          ),
        );
      }
    });
  });

  group('中断判定', () {
    test('30s 内静默续传，30s–5min 等待重连，>5min 失败', () {
      expect(
        decideInterruption(Duration.zero),
        InterruptionDecision.silentResume,
      );
      expect(
        decideInterruption(const Duration(seconds: 30)),
        InterruptionDecision.silentResume,
        reason: '边界含在 30s 内',
      );
      expect(
        decideInterruption(const Duration(seconds: 31)),
        InterruptionDecision.waitForReconnect,
      );
      expect(
        decideInterruption(const Duration(minutes: 5)),
        InterruptionDecision.waitForReconnect,
        reason: '边界含在 5min 内',
      );
      expect(
        decideInterruption(const Duration(minutes: 5, seconds: 1)),
        InterruptionDecision.fail,
      );
    });

    test('未知 id 的 tickWatchdog 抛 notFound', () async {
      final TransferServiceImpl service =
          TransferServiceImpl(resolver: StaticTargetResolver(neverReachableUri));
      addTearDown(service.dispose);
      expect(
        () async => service.tickWatchdog('missing'),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.notFound,
          ),
        ),
      );
    });

    test('注入时钟：静默越过失败窗口后，看门狗把任务标记 failed 并保留断点', () async {
      // 用一个「握手成功但数据永不到达」的端点造出真实静默。
      final RangeTestServer stalled = await RangeTestServer.start(1024 * 1024)
        ..delayPerChunk = const Duration(seconds: 30);
      addTearDown(stalled.stop);

      DateTime fake = DateTime(2026, 11, 4, 12);
      final TransferServiceImpl service = TransferServiceImpl(
        resolver: StaticTargetResolver(stalled.urlFor('f.bin')),
        clock: TransferClock(now: () => fake),
        chunkBytes: 256 * 1024,
      );
      addTearDown(service.dispose);

      // 这条 download 稍后会被 cancel 打断，必然抛 network 失败。
      // 立刻挂上兜底处理器，避免在取消之前就成为未处理异常。
      TransferRecord? settled;
      Object? settledError;
      final Future<void> pending = service
          .download(
            peer: _peer(),
            share: _share(),
            itemKey: _key(),
            targetDir: tempDir.path,
            fileName: 'out.bin',
          )
          .then<void>((TransferRecord r) {
            settled = r;
          }).catchError((Object e) {
            settledError = e;
          });

      final Stopwatch budget = Stopwatch()..start();
      while (service.taskIds.isEmpty && budget.elapsed < const Duration(seconds: 10)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(service.taskIds, hasLength(1));
      final String id = service.taskIds.single;

      // 静默 10s：仍在静默续传窗口内。
      fake = fake.add(const Duration(seconds: 10));
      expect(await service.tickWatchdog(id), InterruptionDecision.silentResume);
      expect(service.handleOf(id)!.phase, TransferPhase.flowing);

      // 静默 60s：进入等待重连。
      fake = fake.add(const Duration(seconds: 50));
      expect(await service.tickWatchdog(id), InterruptionDecision.waitForReconnect);
      expect(service.handleOf(id)!.phase, TransferPhase.waitingReconnect);
      expect(service.recordOf(id)!.status, isNot(TransferStatus.failed));

      // 静默 6min：越过失败窗口，标记 failed 并保留断点。
      fake = fake.add(const Duration(minutes: 6));
      expect(await service.tickWatchdog(id), InterruptionDecision.fail);
      final TransferRecord failed = service.recordOf(id)!;
      expect(failed.status, TransferStatus.failed);
      expect(service.handleOf(id)!.phase, TransferPhase.failed);
      expect(File('${tempDir.path}/out.bin.partmeta').existsSync(), isTrue,
          reason: '失败必须保留断点，供静默续传');

      // 收尾：取消并放掉挂起的 download（上面的 catchError 已接住预期失败）。
      await service.cancel(id);
      await pending.timeout(const Duration(seconds: 10), onTimeout: () {});
      expect(service.recordOf(id)!.status, TransferStatus.failed);
      expect(settledError, isNotNull, reason: '取消应让 download 以失败收尾');
      expect(settled, isNull);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}