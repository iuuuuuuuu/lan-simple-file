// SPDX-License-Identifier: GPL-3.0-only

/// 混合逻辑时钟（HLC）：物理毫秒 + 逻辑计数 + 发起者，跨节点可复现排序。
///
/// 无中心架构里没有「总有一台在线」的服务器，本地时钟又不可信（手机可能慢 3 分钟，
/// 也有人手动改系统时间）。纯物理时间戳会让消息顺序错乱且不可复现；
/// 纯逻辑时钟（Lamport）顺序一致但丢失时间语义，UI 就没法显示「昨天 14:03」。
///
/// HLC 两者兼得：
/// - **物理部分**取 max(本地墙钟, 上次, 对端)，保证不落后于任何已见事件；
/// - **逻辑部分**在墙钟回退或与本机/对端相同时递增，保证严格单调。
///
/// 不变量（本实现的正确性基础，均有测试锁定）：
/// 1. 连续调用 [next] 得到的 HLC 严格递增，**即使注入倒退的墙钟**；
/// 2. [observe] 之后，本机时钟必然**严格大于**被观察到的远端 HLC；
/// 3. 任意两台节点对同一个事件集合按 Hlc.compareTo 排序，得到**相同顺序**
///    （关键字是 (millis, counter, origin)，origin 是 peerId，天然做最终决胜）。
library;

import 'dart:math' as math;

import '../contracts/types.dart';

/// 墙钟来源；测试注入假时钟以复现回退场景。
typedef WallClock = DateTime Function();

/// 一台节点的混合逻辑时钟。
///
/// 本类不是线程安全的，但 Dart 是单 isolate 事件循环，调用点天然串行；
/// 跨 isolate 使用时每个 isolate 必须各持一个实例。
final class HlcClock {
  /// [now] 缺省取系统 UTC 时间；[initial] 可从持久化状态恢复。
  HlcClock({
    required this.origin,
    WallClock? now,
    Hlc? initial,
  })  : _now = now ?? DateTime.now,
        _last = initial ?? Hlc(millis: 0, counter: 0, origin: origin);

  /// 本机 peerId 文本，作为 HLC 的最终决胜位。
  final String origin;

  final WallClock _now;

  Hlc _last;

  /// 最近一次发出或观察到的时间戳。
  ///
  /// 直接返回值对象（Hlc 不可变），调用方无法改坏内部状态。
  Hlc get last => _last;

  /// 产生一个本地事件时间戳（发消息、写本地日志等）。
  ///
  /// 墙钟前进时开新的毫秒并把计数归零；墙钟停住或**回退**时保留毫秒、
  /// 计数加一。因此无论系统时间怎么跳，输出始终严格递增。
  Hlc next() {
    final int wall = _now().millisecondsSinceEpoch;
    if (wall > _last.millis) {
      _last = Hlc(millis: wall, counter: 0, origin: origin);
    } else {
      _last = Hlc(
        millis: _last.millis,
        counter: _last.counter + 1,
        origin: origin,
      );
    }
    return _last;
  }

  /// 观察到远端时间戳后合并，返回合并后的本机时间戳。
  ///
  /// 物理部分取三者最大；逻辑部分保证结果严格大于 [remote] 与旧值。
  /// 这里的「+1」加在**逻辑计数**上，而不是物理毫秒上：
  /// 把远端毫秒直接 +1 会在对端时钟超前很多时把本机时间推到未来，
  /// 之后所有本地事件的物理时间都会失真；加计数则既保住顺序又保住时间语义。
  Hlc observe(Hlc remote) {
    final int wall = _now().millisecondsSinceEpoch;
    final int maxMillis = math.max(wall, math.max(_last.millis, remote.millis));

    final int counter;
    final bool lastIsMax = maxMillis == _last.millis;
    final bool remoteIsMax = maxMillis == remote.millis;
    if (lastIsMax && remoteIsMax) {
      counter = math.max(_last.counter, remote.counter) + 1;
    } else if (lastIsMax) {
      counter = _last.counter + 1;
    } else if (remoteIsMax) {
      counter = remote.counter + 1;
    } else {
      // 墙钟最大：这是一个全新的物理时刻，计数从零开始。
      counter = 0;
    }

    _last = Hlc(millis: maxMillis, counter: counter, origin: origin);
    return _last;
  }

  /// 从持久化状态恢复（例如重启后接上上次的时间戳）。
  ///
  /// 只允许向前恢复：传入的时间戳必须不小于当前值，否则抛 [ArgumentError]。
  /// 允许回退会让单调性失效，那正是 HLC 存在的意义。
  void restore(Hlc persisted) {
    if (persisted.compareTo(_last) < 0) {
      throw ArgumentError.value(
        persisted,
        'persisted',
        '恢复的时间戳早于当前值，会破坏单调性: ${persisted.encode()} < ${_last.encode()}',
      );
    }
    _last = Hlc(
      millis: persisted.millis,
      counter: persisted.counter,
      origin: origin,
    );
  }
}
