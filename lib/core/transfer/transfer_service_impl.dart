// SPDX-License-Identifier: GPL-3.0-only

/// TransferService 实现：Range 下载池 + .part 续传 + 校验 + 限速。
///
/// 设计要点：
/// - 每个任务持有自己的 [HttpClient]，pause/cancel 用 [HttpClientRequest.abort]
///   真打断在飞连接，而不是等它自然读完；
/// - 区间状态在内存与 `.partmeta` 双写，进程重启后 resume 只补缺口；
/// - etag 变化视为「实体已换」，丢弃旧断点从头下，绝不拿旧字节拼新文件；
/// - 全程 int：区间端点是 int（Dart 64 位），不对齐 int32。
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lan_simple_file/core/contracts/contracts.dart';

import 'checksum.dart';
import 'chunk_scheduler.dart';
import 'partial_file.dart';
import 'speed_limiter.dart';

/// 传输过程中的阶段；用于中断判定。
enum TransferPhase {
  /// 没有在飞连接。
  idle,

  /// 数据正在流动。
  flowing,

  /// 30s 内无进展，正在静默续传。
  silentResuming,

  /// 30s–5min 无进展，等待重连。
  waitingReconnect,

  /// >5min 无进展，已标记失败但保留断点。
  failed,

  /// 用户暂停。
  paused,

  /// 用户取消。
  cancelled,

  /// 完成。
  done,
}

/// 一个下载任务的可变状态。
final class _Task {
  _Task({
    required this.id,
    required this.peerId,
    required this.shareId,
    required this.itemKey,
    required this.targetDir,
    required this.createdAt,
    required this.partial,
    required this.total,
    required this.etag,
    required this.algorithm,
    required this.expectedChecksum,
    this.url,
  });

  final String id;
  final PeerId peerId;
  final ShareId shareId;
  final ItemKey itemKey;
  final String targetDir;
  final DateTime createdAt;
  final PartialFile partial;

  int total;
  String etag;
  ChecksumAlgorithm algorithm;
  String? expectedChecksum;

  /// 直链；null 表示需由 [TransferTargetResolver] 解析。
  String? url;

  TransferPhase phase = TransferPhase.idle;
  TransferStatus status = TransferStatus.pending;
  String? error;
  DateTime? finishedAt;
  DateTime? lastProgressAt;
  int speedBps = 0;
  bool pauseRequested = false;
  bool cancelRequested = false;
  HttpClient? client;
  final Set<HttpClientRequest> inFlight = <HttpClientRequest>{};
  bool metadataFlushPending = false;
}

/// 一个下载任务的进度快照来源。
final class TransferHandle {
  TransferHandle._(this._service, this._task);

  final TransferServiceImpl _service;
  final _Task _task;

  String get id => _task.id;

  /// 当前状态快照。
  TransferRecord get record => _service._toRecord(_task);

  /// 已完成字节数。
  int get bytesDone => _task.partial.completedBytes;

  /// 总字节数。
  int get bytesTotal => _task.total;

  /// 当前阶段。
  TransferPhase get phase => _task.phase;
}

/// 解析「下载哪个地址」。真实实现按 share 查 store 拿到提供者地址；
/// 测试注入静态 resolver，避免把网络拓扑写死在传输层。
abstract interface class TransferTargetResolver {
  /// 返回可直接 GET 的文件 URL（应带 Range 支持）。
  Future<Uri> resolve({
    required PeerId peer,
    required ShareId share,
    required ItemKey itemKey,
  });
}

/// 固定 URL 的 resolver，供测试与「已知直链」场景使用。
final class StaticTargetResolver implements TransferTargetResolver {
  const StaticTargetResolver(this.uri);

  final Uri uri;

  @override
  Future<Uri> resolve({
    required PeerId peer,
    required ShareId share,
    required ItemKey itemKey,
  }) async =>
      uri;
}

/// 可注入的时间源，让 30s / 5min 的中断判定在测试里可控。
final class TransferClock {
  TransferClock({DateTime Function()? now, MonotonicClock? monotonic})
      : _now = now ?? DateTime.now,
        _monotonic = monotonic ?? defaultMonotonicClock;

  final DateTime Function() _now;
  final MonotonicClock _monotonic;

  DateTime now() => _now();

  Duration monotonic() => _monotonic();
}

/// 中断判定的结果。
enum InterruptionDecision {
  /// 仍在 30s 内，静默续传。
  silentResume,

  /// 30s–5min，进入等待重连。
  waitForReconnect,

  /// >5min，标记失败。
  fail,
}

/// 依据静默时长给出判定；纯函数，便于单测穷举边界。
InterruptionDecision decideInterruption(
  Duration silentFor, {
  Duration silentWindow = LanFileConstants.transferSilentResumeWindow,
  Duration failWindow = LanFileConstants.transferFailWindow,
}) {
  if (silentFor <= silentWindow) return InterruptionDecision.silentResume;
  if (silentFor <= failWindow) return InterruptionDecision.waitForReconnect;
  return InterruptionDecision.fail;
}

/// 下载实现。
final class TransferServiceImpl implements TransferService {
  TransferServiceImpl({
    required this.resolver,
    this.store,
    TransferClock? clock,
    SpeedLimiter? limiter,
    int concurrency = LanFileConstants.downloadConcurrency,
    int chunkBytes = LanFileConstants.rangeChunkBytes,
    ChecksumAlgorithm algorithm = ChecksumAlgorithm.xxh3,
    HttpClient Function()? clientFactory,
    this.retryBackoff = const Duration(milliseconds: 100),
  })  : clock = clock ?? TransferClock(),
        limiter = limiter ?? SpeedLimiter(),
        _concurrency = concurrency, // ignore: prefer_initializing_formals
        _chunkBytes = chunkBytes, // ignore: prefer_initializing_formals
        _algorithm = algorithm, // ignore: prefer_initializing_formals
        _clientFactory = clientFactory ?? HttpClient.new;

  /// 地址解析。
  final TransferTargetResolver resolver;

  /// 可选持久化；null 时只在内存里维护任务。
  final LanFileStore? store;

  /// 可注入时间源。
  final TransferClock clock;

  /// 两级限速器。
  final SpeedLimiter limiter;

  /// 重试前的退避。
  final Duration retryBackoff;

  final int _concurrency;
  final int _chunkBytes;
  final ChecksumAlgorithm _algorithm;
  final HttpClient Function() _clientFactory;

  final Map<String, _Task> _tasks = <String, _Task>{};
  final StreamController<TransferProgress> _progressController =
      StreamController<TransferProgress>.broadcast();
  int _idSeq = 0;

  /// 并发上限（契约 8）。
  int get concurrency => _concurrency;

  /// 分片大小（契约 4MB）。
  int get chunkBytes => _chunkBytes;

  /// 默认校验算法。
  ChecksumAlgorithm get algorithm => _algorithm;

  @override
  Stream<TransferProgress> watchAll() => _progressController.stream;

  /// 任务是否还在表中（测试用）。
  bool hasTask(String transferId) => _tasks.containsKey(transferId);

  /// 当前所有任务 id，按创建顺序。
  List<String> get taskIds => List<String>.unmodifiable(_tasks.keys);

  /// 取当前快照；未知 id 返回 null。
  TransferRecord? recordOf(String transferId) {
    final _Task? task = _tasks[transferId];
    return task == null ? null : _toRecord(task);
  }

  /// 取句柄；未知 id 返回 null。
  TransferHandle? handleOf(String transferId) {
    final _Task? task = _tasks[transferId];
    return task == null ? null : TransferHandle._(this, task);
  }

  TransferRecord _toRecord(_Task task) => TransferRecord(
        id: task.id,
        direction: TransferDirection.download,
        peerId: task.peerId,
        shareId: task.shareId,
        itemKey: task.itemKey,
        bytesTotal: task.total,
        bytesDone: task.partial.completedBytes,
        status: task.status,
        createdAt: task.createdAt,
        speedBps: task.speedBps,
        finishedAt: task.finishedAt,
        err: task.error,
      );

  void _emit(_Task task) {
    if (_progressController.isClosed) return;
    _progressController.add(
      TransferProgress(
        transferId: task.id,
        bytesDone: task.partial.completedBytes,
        bytesTotal: task.total,
        status: task.status,
        speedBps: task.speedBps,
      ),
    );
  }

  Future<void> _persist(_Task task) async {
    final LanFileStore? sink = store;
    if (sink == null) return;
    await sink.putTransfer(_toRecord(task));
  }

  String _nextId() {
    _idSeq++;
    return 'tr-${clock.now().microsecondsSinceEpoch}-$_idSeq';
  }

  @override
  Future<TransferRecord> download({
    required PeerId peer,
    required ShareId share,
    required ItemKey itemKey,
    required String targetDir,
    String? fileName,
    String? url,
    String? expectedChecksum,
    ChecksumAlgorithm? checksumAlgorithm,
    int? maxBytesPerSecond,
  }) async {
    final Uri resolved =
        url == null ? await resolver.resolve(peer: peer, share: share, itemKey: itemKey) : Uri.parse(url);
    final String name = fileName ?? _fileNameOf(itemKey, resolved);

    final String targetPath = _joinPath(targetDir, name);
    final ChecksumAlgorithm algo = checksumAlgorithm ?? _algorithm;

    // 先探测实体长度与 etag，再决定是续传还是新建。
    final _Probe probe = await _probeEntity(resolved);
    if (probe.total > LanFileConstants.maxFileBytes) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '文件 $name 超过单文件上限 ${LanFileConstants.maxFileBytes} 字节',
      );
    }

    // etag 变了说明实体已换：旧断点的字节对新文件毫无意义，整份清掉重下。
    // 这里必须吞掉 EtagMismatch 并按「全新下载」处理，而不是把异常抛给用户。
    PartialFile partial;
    try {
      partial = await PartialFile.open(
        targetPath: targetPath,
        total: probe.total,
        etag: probe.etag,
      );
    } on EtagMismatchException {
      final PartialFile stale = PartialFile.fresh(
        targetPath: targetPath,
        total: probe.total,
        etag: probe.etag,
      );
      await stale.resetProgress();
      partial = stale;
    }
    if (maxBytesPerSecond != null) {
      limiter.setKeyBytesPerSecond(share.value, maxBytesPerSecond);
    }

    final String id = _nextId();
    final _Task task = _Task(
      id: id,
      peerId: peer,
      shareId: share,
      itemKey: itemKey,
      targetDir: targetDir,
      createdAt: clock.now(),
      partial: partial,
      total: probe.total,
      etag: probe.etag,
      algorithm: algo,
      expectedChecksum: expectedChecksum,
      url: resolved.toString(),
    );
    _tasks[id] = task;
    task.status = TransferStatus.active;
    await _persist(task);
    await _drive(task);
    return _toRecord(task);
  }

  @override
  Future<TransferRecord> resume(String transferId) async {
    final _Task? task = _tasks[transferId];
    if (task == null) {
      throw LanFileException(
        LanFileErrorCode.notFound,
        '没有这个传输任务: $transferId',
      );
    }
    task.cancelRequested = false;
    task.pauseRequested = false;
    task.error = null;
    task.status = TransferStatus.active;
    task.phase = TransferPhase.idle;

    // 重新探测：etag 变了就丢弃旧断点，从头开始。
    final Uri uri = Uri.parse(task.url!);
    final _Probe probe = await _probeEntity(uri);
    if (probe.etag.isNotEmpty &&
        task.etag.isNotEmpty &&
        probe.etag != task.etag) {
      await task.partial.resetProgress();
      task.etag = probe.etag;
      task.total = probe.total;
      task.partial.overrideTotal(probe.total);
      await task.partial.flushMeta(
        algorithm: task.algorithm.name,
        expectedChecksum: task.expectedChecksum,
      );
    } else if (probe.total != task.total) {
      await task.partial.resetProgress();
      task.total = probe.total;
      task.partial.overrideTotal(probe.total);
      task.etag = probe.etag;
    }

    await _persist(task);
    await _drive(task);
    return _toRecord(task);
  }

  @override
  Future<void> pause(String transferId) async {
    final _Task? task = _tasks[transferId];
    if (task == null) {
      throw LanFileException(
        LanFileErrorCode.notFound,
        '没有这个传输任务: $transferId',
      );
    }
    // 已完成的任务不能被 pause 打回 paused；失败任务保留 failed 状态。
    if (task.status == TransferStatus.done) return;
    task.pauseRequested = true;
    _abortInFlight(task);
    task.phase = TransferPhase.paused;
    task.status = TransferStatus.paused;
    task.speedBps = 0;
    await task.partial.flushMeta(
      algorithm: task.algorithm.name,
      expectedChecksum: task.expectedChecksum,
    );
    await _persist(task);
    _emit(task);
  }

  @override
  Future<void> cancel(String transferId) async {
    final _Task? task = _tasks[transferId];
    if (task == null) {
      throw LanFileException(
        LanFileErrorCode.notFound,
        '没有这个传输任务: $transferId',
      );
    }
    task.cancelRequested = true;
    _abortInFlight(task);
    task.phase = TransferPhase.cancelled;
    // 契约的 TransferStatus 没有 cancelled 值，取消用 failed + 明确 err 表示。
    task.status = TransferStatus.failed;
    task.error = 'cancelled';
    task.speedBps = 0;
    task.finishedAt = clock.now();
    // 绝不删除 .part / .partmeta：取消只停止传输，断点必须还在，
    // 否则之后 resume 只能从 0 重来。这里必须主动落一次 meta ——
    // _drive 的取消分支不会再写，否则已完成区间会丢在内存里。
    await task.partial.flushMeta(
      algorithm: task.algorithm.name,
      expectedChecksum: task.expectedChecksum,
    );
    await task.partial.closeHandle();
    await _persist(task);
    _emit(task);
  }

  /// 强制丢弃某个任务的断点（用户明确要求重下时用）。
  Future<void> discardPartial(String transferId) async {
    final _Task? task = _tasks[transferId];
    if (task == null) {
      throw LanFileException(
        LanFileErrorCode.notFound,
        '没有这个传输任务: @transferId',
      );
    }
    await task.partial.discard();
  }

  /// 关闭所有客户端；进程退出前调用。
  Future<void> dispose() async {
    for (final _Task task in _tasks.values) {
      _abortInFlight(task);
      await task.partial.closeHandle();
    }
    await _progressController.close();
  }

  /// 中断看门狗：按 [decideInterruption] 把「静默多久」翻译成阶段，
  /// 超过失败窗口就真 abort 在飞连接并标记 failed（断点保留）。
  ///
  /// 由 [_drive] 期间周期性调用；测试可直接手动 tick。
  ///
  /// 返回前会把断点落盘并释放句柄：失败任务若只在内存里标记 failed，
  /// 进程重启后既看不到断点也没有进度，等于静默丢掉了续传能力。
  Future<InterruptionDecision> tickWatchdog(String transferId) async {
    final _Task? maybe = _tasks[transferId];
    if (maybe == null) {
      throw LanFileException(
        LanFileErrorCode.notFound,
        '没有这个传输任务: @transferId',
      );
    }
    final _Task task = maybe;
    final DateTime? last = task.lastProgressAt;
    if (last == null) return InterruptionDecision.silentResume;
    final Duration silentFor = clock.now().difference(last);
    final InterruptionDecision decision = decideInterruption(silentFor);
    switch (decision) {
      case InterruptionDecision.silentResume:
        if (task.phase != TransferPhase.flowing) {
          task.phase = TransferPhase.flowing;
        }
      case InterruptionDecision.waitForReconnect:
        task.phase = TransferPhase.waitingReconnect;
      case InterruptionDecision.fail:
        task.phase = TransferPhase.failed;
        task.status = TransferStatus.failed;
        task.error = '静默超过失败窗口: ${silentFor.inSeconds}s';
        _abortInFlight(task);
        await task.partial.flushMeta(
          algorithm: task.algorithm.name,
          expectedChecksum: task.expectedChecksum,
        );
        await task.partial.closeHandle();
        await _persist(task);
        _emit(task);
    }
    return decision;
  }

  void _abortInFlight(_Task task) {
    for (final HttpClientRequest request in task.inFlight.toList()) {
      try {
        request.abort();
      } on Object {
        // abort 对已完成的请求会抛，忽略即可，不能因此中断取消流程。
      }
    }
    task.inFlight.clear();
    final HttpClient? client = task.client;
    task.client = null;
    client?.close(force: true);
  }

  /// 跑一轮：切片 → 并发下载 → 校验 → 落盘。
  Future<void> _drive(_Task task) async {
    if (task.partial.isComplete) {
      await _finish(task);
      return;
    }
    final HttpClient client = _clientFactory();
    task.client = client;
    task.phase = TransferPhase.flowing;
    task.lastProgressAt = clock.now();

    final List<ByteInterval> missing = task.partial.missing;
    final List<ChunkTask> plan = planChunks(
      missing: missing,
      chunkBytes: _chunkBytes,
    );
    final ConcurrencyProbe probe = ConcurrencyProbe();
    final ChunkScheduler scheduler = ChunkScheduler(
      concurrency: _concurrency,
      maxAttempts: 3,
    );

    Object? fatal;
    try {
      await scheduler.run(
        tasks: plan,
        isCancelled: () => task.cancelRequested || task.pauseRequested,
        worker: (ChunkTask chunk, int attempt) async {
          probe.enter();
          try {
            await _downloadChunk(task, client, chunk);
          } finally {
            probe.leave();
          }
        },
      );
    } on Object catch (error) {
      fatal = error;
    } finally {
      _abortInFlight(task);
    }

    if (task.cancelRequested) {
      task.status = TransferStatus.failed;
      task.phase = TransferPhase.cancelled;
      task.speedBps = 0;
      await _persist(task);
      _emit(task);
      return;
    }
    if (task.pauseRequested) {
      task.status = TransferStatus.paused;
      task.phase = TransferPhase.paused;
      task.speedBps = 0;
      await task.partial.flushMeta(
        algorithm: task.algorithm.name,
        expectedChecksum: task.expectedChecksum,
      );
      await _persist(task);
      _emit(task);
      return;
    }
    if (fatal != null) {
      task.status = TransferStatus.failed;
      task.phase = TransferPhase.failed;
      task.error = _describeError(fatal);
      task.finishedAt = clock.now();
      task.speedBps = 0;
      await task.partial.flushMeta(
        algorithm: task.algorithm.name,
        expectedChecksum: task.expectedChecksum,
      );
      // 必须先关句柄：失败后 .part 仍被持有的话，用户连删除/移动都做不了，
      // 后续 resume 也会撞上同一个占用。
      await task.partial.closeHandle();
      await _persist(task);
      _emit(task);
      if (fatal is LanFileException) throw fatal;
      throw LanFileException(
        LanFileErrorCode.network,
        '下载失败: ${task.error}',
        cause: fatal,
      );
    }

    await _finish(task);
  }

  Future<void> _finish(_Task task) async {
    // 完整性校验：缺片直接判失败，绝不把半截文件当成品。
    if (!task.partial.isComplete) {
      task.status = TransferStatus.failed;
      task.phase = TransferPhase.failed;
      task.error = '仍有未完成区间: ${task.partial.missing}';
      task.finishedAt = clock.now();
      await _persist(task);
      _emit(task);
      throw LanFileException(
        LanFileErrorCode.internal,
        task.error!,
      );
    }

    final String? expected = task.expectedChecksum;
    if (expected != null) {
      final String actual = await checksumOfFile(
        File(task.partial.partPath),
        task.algorithm,
      );
      if (!checksumEquals(expected, actual)) {
        task.status = TransferStatus.failed;
        task.phase = TransferPhase.failed;
        task.error = 'checksumMismatch';
        task.finishedAt = clock.now();
        await _persist(task);
        _emit(task);
        throw checksumMismatchError(
          expected: expected,
          actual: actual,
          algorithm: task.algorithm,
          subject: task.itemKey.value,
        );
      }
    }

    await task.partial.finalize();
    task.status = TransferStatus.done;
    task.phase = TransferPhase.done;
    task.finishedAt = clock.now();
    task.speedBps = 0;
    await _persist(task);
    _emit(task);
  }

  Future<void> _downloadChunk(
    _Task task,
    HttpClient client,
    ChunkTask chunk,
  ) async {
    if (task.cancelRequested || task.pauseRequested) return;

    // 限速：先过 share 桶再过全局桶。
    await limiter.acquire(
      chunk.length,
      key: task.shareId.value,
      isCancelled: () => task.cancelRequested || task.pauseRequested,
    );
    if (task.cancelRequested || task.pauseRequested) return;

    final HttpClientRequest request =
        await client.getUrl(Uri.parse(task.url!));
    request.headers.set(
      HttpHeaders.rangeHeader,
      'bytes=${chunk.start}-${chunk.endExclusive - 1}',
    );
    task.inFlight.add(request);
    HttpClientResponse response;
    try {
      response = await request.close();
    } on Object {
      task.inFlight.remove(request);
      rethrow;
    }

    try {
      if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
        // 服务端说这个区间不可满足：实体可能变短了。
        throw LanFileException(
          LanFileErrorCode.conflict,
          '服务端拒绝区间 ${chunk.interval}',
        );
      }
      if (response.statusCode != HttpStatus.partialContent &&
          response.statusCode != HttpStatus.ok) {
        throw LanFileException(
          LanFileErrorCode.network,
          '下载分片返回 ${response.statusCode}',
          httpStatus: response.statusCode,
        );
      }

      // 206 必须带 Content-Range，且起点要对得上，否则字节会对错位。
      if (response.statusCode == HttpStatus.partialContent) {
        final String? contentRange =
            response.headers.value(HttpHeaders.contentRangeHeader);
        final ByteInterval? got =
            contentRange == null ? null : parseContentRange(contentRange);
        if (got == null || got.start != chunk.start) {
          throw LanFileException(
            LanFileErrorCode.network,
            'Content-Range 与请求不符: 期望 ${chunk.interval}，实际 $contentRange',
          );
        }
      }

      final _BoundedSink sink = _BoundedSink();
      int received = 0;
      await for (final List<int> data in response) {
        if (task.cancelRequested || task.pauseRequested) return;
        // 只取本分片需要的字节：有些服务端会把末尾区间放大，
        // 只要起点对得上，多出来的部分丢弃即可，不该判为失败。
        final int room = chunk.length - received;
        if (room <= 0) break;
        final List<int> take =
            data.length <= room ? data : data.sublist(0, room);
        received += take.length;
        sink.add(take);
        task.lastProgressAt = clock.now();
      }

      // 必须先确认收满再落盘：若把不足长度的字节写进 .part 并记成「已完成」，
      // resume 会永远跳过这段损坏数据，最终得到一个看似完整实则损坏的文件。
      if (received != chunk.length) {
        throw LanFileException(
          LanFileErrorCode.network,
          '分片 ${chunk.interval} 只收到 $received / ${chunk.length} 字节',
        );
      }
      await _writeChunk(task, chunk, sink, finalChunk: true);
    } finally {
      task.inFlight.remove(request);
    }
  }

  Future<void> _writeChunk(
    _Task task,
    ChunkTask chunk,
    _BoundedSink sink, {
    bool finalChunk = false,
  }) async {
    if (sink.total == 0) return;
    final Uint8List bytes = sink.take();
    // 累积写入：偏移按已写字节推进。
    final int offset = chunk.start + sink.writtenOffset;
    await task.partial.writeAt(offset, bytes);
    sink.writtenOffset += bytes.length;
    if (finalChunk) {
      await task.partial.flushMeta(
        algorithm: task.algorithm.name,
        expectedChecksum: task.expectedChecksum,
      );
    }
    _emit(task);
  }

  /// 探测实体长度与 etag：发一个 `Range: bytes=0-0` 只取 1 字节。
  Future<_Probe> _probeEntity(Uri uri) async {
    final HttpClient client = _clientFactory();
    try {
      final HttpClientRequest request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      final HttpClientResponse response;
      try {
        response = await request.close();
      } on Object catch (error) {
        throw LanFileException(
          LanFileErrorCode.network,
          '探测实体失败: $error',
          cause: error,
        );
      }
      if (response.statusCode == HttpStatus.ok ||
          response.statusCode == HttpStatus.partialContent) {
        final String? contentRange =
            response.headers.value(HttpHeaders.contentRangeHeader);
        int total = response.contentLength;
        if (contentRange != null) {
          total = parseContentRangeTotal(contentRange) ?? total;
        }
        final String etag =
            response.headers.value(HttpHeaders.etagHeader) ?? '';
        try {
          await response.drain<void>();
        } on Object catch (error) {
          throw LanFileException(
            LanFileErrorCode.network,
            '探测实体时连接中断: $error',
            cause: error,
          );
        }
        return _Probe(total: total, etag: etag);
      }
      if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
        // 空文件：Content-Range: bytes */0
        final String? contentRange =
            response.headers.value(HttpHeaders.contentRangeHeader);
        await response.drain<void>();
        final int total =
            contentRange == null ? 0 : parseContentRangeTotal(contentRange) ?? 0;
        return _Probe(total: total, etag: '');
      }
      await response.drain<void>();
      throw LanFileException(
        LanFileErrorCode.network,
        '探测实体失败，HTTP ${response.statusCode}',
        httpStatus: response.statusCode,
      );
    } finally {
      client.close(force: true);
    }
  }

  String _describeError(Object error) {
    if (error is LanFileException) return '${error.code.name}: ${error.message}';
    return error.toString();
  }

  static String _fileNameOf(ItemKey itemKey, Uri uri) {
    final String fromKey = itemKey.value;
    final int slash = math.max(fromKey.lastIndexOf('/'), fromKey.lastIndexOf('\\'));
    final String name = slash >= 0 ? fromKey.substring(slash + 1) : fromKey;
    if (name.isNotEmpty) return name;
    final List<String> segments = uri.pathSegments;
    return segments.isEmpty ? 'download.bin' : segments.last;
  }

  static String _joinPath(String dir, String name) {
    final String separator = dir.contains('\\') ? '\\' : '/';
    final String trimmed =
        dir.endsWith('/') || dir.endsWith('\\') ? dir.substring(0, dir.length - 1) : dir;
    return '$trimmed$separator$name';
  }
}

final class _Probe {
  const _Probe({required this.total, required this.etag});

  final int total;
  final String etag;
}

/// 解析 `bytes START-END/TOTAL`。
ByteInterval? parseContentRange(String value) {
  final String v = value.trim();
  const String prefix = 'bytes ';
  if (!v.startsWith(prefix)) return null;
  final String rest = v.substring(prefix.length);
  final int slash = rest.indexOf('/');
  if (slash < 0) return null;
  final String span = rest.substring(0, slash);
  final int dash = span.indexOf('-');
  if (dash < 0) return null;
  final int? start = int.tryParse(span.substring(0, dash).trim());
  final int? end = int.tryParse(span.substring(dash + 1).trim());
  if (start == null || end == null || end < start) return null;
  return ByteInterval(start, end + 1);
}

/// 解析 `bytes START-END/TOTAL` 或 `bytes */TOTAL` 里的总长度。
int? parseContentRangeTotal(String value) {
  final int slash = value.lastIndexOf('/');
  if (slash < 0) return null;
  final String tail = value.substring(slash + 1).trim();
  if (tail == '*') return null;
  return int.tryParse(tail);
}

/// 累积到阈值就落盘的缓冲。
final class _BoundedSink {
  final List<int> _buffer = <int>[];

  int writtenOffset = 0;

  int get total => _buffer.length;

  void add(List<int> data) => _buffer.addAll(data);

  Uint8List take() {
    final Uint8List bytes = Uint8List.fromList(_buffer);
    _buffer.clear();
    return bytes;
  }
}