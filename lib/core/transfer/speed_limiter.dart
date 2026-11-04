// SPDX-License-Identifier: GPL-3.0-only

/// 令牌桶限速：按 share 与全局两级，时间源可注入。
///
/// 令牌按「字节」计。桶容量默认等于速率（约 1 秒的突发），
/// 因此稳态吞吐就是 rate，突发不会超过 1 秒的量。
library;

import 'dart:math' as math;

/// 单调时间源；测试注入假时钟以摆脱真实等待。
typedef MonotonicClock = Duration Function();

/// 线程安全的睡眠函数；测试可替换成可控实现。
typedef Sleeper = Future<void> Function(Duration duration);

/// 进程内默认单调时钟；注入假时钟可让限速测试不真等。
Duration defaultMonotonicClock() =>
    Duration(microseconds: DateTime.now().microsecondsSinceEpoch);

/// 默认睡眠实现。
Future<void> defaultSleeper(Duration duration) =>
    Future<void>.delayed(duration);

/// 一个令牌桶。
///
/// [rateBytesPerSecond] 为 null 或 <= 0 表示不限速。
final class TokenBucket {
  TokenBucket({
    required this.rateBytesPerSecond,
    int? capacityBytes,
    MonotonicClock? clock,
    Sleeper? sleeper,
  })  : _clock = clock ?? defaultMonotonicClock,
        _sleeper = sleeper ?? defaultSleeper,
        _capacity = capacityBytes ??
            (rateBytesPerSecond == null || rateBytesPerSecond <= 0
                ? 0
                : math.max(1, rateBytesPerSecond ~/ 8)) {
    // 桶初始为空：若一开始就塞满 1 秒的令牌，第一次 acquire 会白送一整秒，
    // 4MB@1MB/s 会变成 3s 而不是 4s。这里从 0 起，稳态才严格等于 rate。
    _tokens = 0;
    _lastRefill = _clock();
  }

  /// 每秒允许的字节数；null 表示不限速。
  final int? rateBytesPerSecond;

  final int _capacity;
  final MonotonicClock _clock;
  final Sleeper _sleeper;

  double _tokens = 0;
  Duration _lastRefill = Duration.zero;

  bool get isUnlimited => rateBytesPerSecond == null || rateBytesPerSecond! <= 0;

  /// 当前可用令牌（含惰性补充）；仅用于观测与测试。
  double get availableTokens {
    _refill();
    return _tokens;
  }

  void _refill() {
    if (isUnlimited) return;
    final Duration now = _clock();
    final int elapsedMicros = (now - _lastRefill).inMicroseconds;
    if (elapsedMicros <= 0) {
      _lastRefill = now;
      return;
    }
    final double added =
        elapsedMicros / Duration.microsecondsPerSecond * rateBytesPerSecond!;
    _tokens = (_tokens + added).clamp(0, _capacity.toDouble());
    _lastRefill = now;
  }

  /// 取得 [bytes] 个令牌，不够就按缺口睡眠等待。
  ///
  /// [isCancelled] 每轮睡眠前后各检查一次，便于 pause/cancel 及时退出。
  Future<void> acquire(
    int bytes, {
    bool Function()? isCancelled,
  }) async {
    if (bytes <= 0) return;
    if (isUnlimited) return;
    if (isCancelled != null && isCancelled()) return;

    int remaining = bytes;
    while (remaining > 0) {
      if (isCancelled != null && isCancelled()) return;
      _refill();

      // 先取走当前能取的令牌。
      if (_tokens >= 1) {
        final int take = _tokens >= remaining ? remaining : _tokens.floor();
        _tokens -= take;
        remaining -= take;
        if (remaining <= 0) return;
        continue;
      }

      // 一个令牌都没有：按缺口睡眠。睡眠时长按剩余需求算，
      // 但不超过「补满一个满桶」所需时间，避免一次睡太久无法响应取消。
      final double deficit = remaining.toDouble() - _tokens;
      final double seconds = deficit / rateBytesPerSecond!;
      final Duration wait = Duration(
        microseconds: (seconds * Duration.microsecondsPerSecond).ceil(),
      );
      if (wait <= Duration.zero) {
        // 防止 rate 极大时死循环。
        await _sleeper(const Duration(microseconds: 1));
        continue;
      }
      // 分段睡眠，每段最多 50ms，便于取消及时生效。
      const Duration slice = Duration(milliseconds: 50);
      Duration slept = Duration.zero;
      while (slept < wait) {
        if (isCancelled != null && isCancelled()) return;
        final Duration step = (wait - slept) < slice ? (wait - slept) : slice;
        await _sleeper(step);
        slept += step;
        _refill();
        if (_tokens >= 1) break;
      }
    }
  }
}

/// 两级限速器：全局桶 + 每个 share 各自的桶。
///
/// 一次读取必须先过 share 桶再过全局桶；两级都满足才放行，
/// 因此实际速率受较严的那一级约束。
final class SpeedLimiter {
  SpeedLimiter({
    int? globalBytesPerSecond,
    MonotonicClock? clock,
    Sleeper? sleeper,
  })  : _clock = clock ?? defaultMonotonicClock,
        _sleeper = sleeper ?? defaultSleeper,
        _globalBytesPerSecond = globalBytesPerSecond {
    _global = TokenBucket(
      rateBytesPerSecond: globalBytesPerSecond,
      clock: _clock,
      sleeper: _sleeper,
    );
  }

  final MonotonicClock _clock;
  final Sleeper _sleeper;
  int? _globalBytesPerSecond;
  late TokenBucket _global;
  final Map<String, TokenBucket> _perKey = <String, TokenBucket>{};

  /// 全局速率（字节/秒）；null 表示不限。
  int? get globalBytesPerSecond => _globalBytesPerSecond;

  /// 设置全局速率；传 null 关闭限速。
  void setGlobalBytesPerSecond(int? rate) {
    if (rate == _globalBytesPerSecond) return;
    _globalBytesPerSecond = rate;
    _global = TokenBucket(
      rateBytesPerSecond: rate,
      clock: _clock,
      sleeper: _sleeper,
    );
  }

  /// 设置某个 key（通常是 shareId）的速率；传 null 取消该 key 的限制。
  void setKeyBytesPerSecond(String key, int? rate) {
    if (rate == null || rate <= 0) {
      _perKey.remove(key);
      return;
    }
    _perKey[key] = TokenBucket(
      rateBytesPerSecond: rate,
      clock: _clock,
      sleeper: _sleeper,
    );
  }

  /// 某个 key 的当前速率；未设置返回 null。
  int? keyBytesPerSecond(String key) => _perKey[key]?.rateBytesPerSecond;

  /// 申请 [bytes] 字节的放行许可。
  Future<void> acquire(
    int bytes, {
    String? key,
    bool Function()? isCancelled,
  }) async {
    if (bytes <= 0) return;
    final TokenBucket? bucket = key == null ? null : _perKey[key];
    if (bucket != null) {
      await bucket.acquire(bytes, isCancelled: isCancelled);
    }
    await _global.acquire(bytes, isCancelled: isCancelled);
  }

  /// 该 key 当前是否受限。
  bool isKeyLimited(String key) => _perKey[key]?.isUnlimited == false;
}