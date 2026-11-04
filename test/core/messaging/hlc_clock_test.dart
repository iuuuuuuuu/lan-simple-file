// SPDX-License-Identifier: GPL-3.0-only

/// HLC 时钟测试：单调性、跨节点收敛、排序一致性、回退韧性。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/messaging/hlc_clock.dart';

void main() {
  group('本地单调性', () {
    test('连续 next 严格递增', () {
      final HlcClock clock = HlcClock(origin: 'p_a');
      Hlc previous = clock.next();
      for (int i = 0; i < 100; i++) {
        final Hlc current = clock.next();
        expect(current.compareTo(previous), greaterThan(0));
        previous = current;
      }
    });

    test('墙钟回退时 counter 递增，毫秒不倒退', () {
      // 注入一个可以任意摆布的时钟：先给 1000ms，再回退到 500ms。
      int wall = 1000;
      final HlcClock clock = HlcClock(origin: 'p_a', now: () {
        return DateTime.fromMillisecondsSinceEpoch(wall, isUtc: true);
      });

      final Hlc first = clock.next();
      expect(first.millis, 1000);
      expect(first.counter, 0);

      // 时间倒退 500ms。
      wall = 500;
      final Hlc second = clock.next();
      expect(second.millis, 1000, reason: '毫秒不得倒退');
      expect(second.counter, 1, reason: '回退靠 counter 保住顺序');
      expect(second.compareTo(first), greaterThan(0));

      // 再退一次，counter 继续涨。
      wall = 100;
      final Hlc third = clock.next();
      expect(third.millis, 1000);
      expect(third.counter, 2);
      expect(third.compareTo(second), greaterThan(0));
    });

    test('墙钟停在同一毫秒，counter 持续递增（同一毫秒多条消息）', () {
      final HlcClock clock = HlcClock(
        origin: 'p_a',
        now: () => DateTime.fromMillisecondsSinceEpoch(42, isUtc: true),
      );
      final List<Hlc> stamps = List<Hlc>.generate(5, (_) => clock.next());
      expect(stamps.map((Hlc h) => h.millis).toSet(), <int>{42});
      expect(stamps.map((Hlc h) => h.counter).toList(),
          <int>[0, 1, 2, 3, 4]);
      for (int i = 1; i < stamps.length; i++) {
        expect(stamps[i].compareTo(stamps[i - 1]), greaterThan(0));
      }
    });
  });

  group('observe 合并远端', () {
    test('观察远端后本机时间戳严格大于远端', () {
      int wall = 1000;
      final HlcClock clock = HlcClock(origin: 'p_a', now: () {
        return DateTime.fromMillisecondsSinceEpoch(wall, isUtc: true);
      });
      clock.next();

      // 远端时钟跑到很前面。
      final Hlc remote = Hlc(millis: 9000, counter: 3, origin: 'p_b');
      final Hlc merged = clock.observe(remote);

      expect(merged.compareTo(remote), greaterThan(0));
      expect(merged.millis, 9000, reason: '物理部分取最大');
      expect(merged.counter, 4, reason: '逻辑部分在远端基础上 +1');
      expect(merged.origin, 'p_a', reason: 'origin 始终是本机');
    });

    test('远落后于本机时，本机仍严格递增', () {
      int wall = 5000;
      final HlcClock clock = HlcClock(origin: 'p_a', now: () {
        return DateTime.fromMillisecondsSinceEpoch(wall, isUtc: true);
      });
      final Hlc local1 = clock.next();
      final Hlc remoteStale = Hlc(millis: 1, counter: 99, origin: 'p_b');
      final Hlc merged = clock.observe(remoteStale);
      expect(merged.compareTo(local1), greaterThan(0));
      expect(merged.millis, local1.millis);
    });
  });

  group('跨节点排序一致', () {
    test('两节点对同一事件集合排序结果完全一致', () {
      // 两台节点各自经历一段交错的事件，再交换日志；
      // 双方用 Hlc.compareTo 排序后必须得到同一顺序。
      final HlcClock a = HlcClock(
        origin: 'p_aaaaaaaaaaaaa',
        now: () => DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
      );
      final HlcClock b = HlcClock(
        origin: 'p_bbbbbbbbbbbbb',
        now: () => DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
      );

      final List<Hlc> events = <Hlc>[];
      // 交错产生事件，并互相 observe（模拟收到对方消息）。
      for (int i = 0; i < 10; i++) {
        final Hlc fromA = a.next();
        events.add(fromA);
        b.observe(fromA);
        final Hlc fromB = b.next();
        events.add(fromB);
        a.observe(fromB);
      }

      final List<Hlc> sortedOnA = List<Hlc>.of(events)
        ..sort((Hlc x, Hlc y) => x.compareTo(y));
      final List<Hlc> sortedOnB = List<Hlc>.of(events.reversed.toList())
        ..sort((Hlc x, Hlc y) => x.compareTo(y));

      expect(
        sortedOnA.map((Hlc h) => h.encode()).toList(),
        sortedOnB.map((Hlc h) => h.encode()).toList(),
        reason: '同一集合在不同起始顺序下必须排出同一结果',
      );
      // 且严格无重复（单调性保证）。
      expect(sortedOnA.map((Hlc h) => h.encode()).toSet().length,
          sortedOnA.length);
    });

    test('同一毫秒同一 counter 时按 origin 决胜，顺序确定', () {
      final Hlc a = Hlc(millis: 5, counter: 0, origin: 'p_aaaaaaaaaaaaa');
      final Hlc b = Hlc(millis: 5, counter: 0, origin: 'p_bbbbbbbbbbbbb');
      expect(a.compareTo(b), lessThan(0));
      expect(b.compareTo(a), greaterThan(0));
      // 与传入顺序无关。
      final List<Hlc> list = <Hlc>[b, a];
      list.sort((Hlc x, Hlc y) => x.compareTo(y));
      expect(list.first, a);
      expect(list.last, b);
    });
  });

  group('restore', () {
    test('向前恢复被接受，向后恢复抛错', () {
      final HlcClock clock = HlcClock(origin: 'p_a');
      clock.next();
      final Hlc ahead = Hlc(millis: 9_999_999_999_999, counter: 7, origin: 'p_a');
      clock.restore(ahead);
      expect(clock.last.millis, ahead.millis);
      expect(clock.last.counter, ahead.counter);

      expect(
        () => clock.restore(Hlc(millis: 1, counter: 0, origin: 'p_a')),
        throwsArgumentError,
        reason: '回退恢复会破坏单调性',
      );
    });
  });
}
