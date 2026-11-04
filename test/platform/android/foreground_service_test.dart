// SPDX-License-Identifier: GPL-3.0-only

/// 前台服务状态机与通道桥的测试。
///
/// **诚实边界**：这里全部是 mock MethodChannel + 纯函数，**没有一台安卓真机**。
/// 状态机部分是真逻辑（无 mock），通道部分用 TestDefaultBinaryMessenger 模拟，
/// 验证的是「参数怎么编、异常怎么映射」，不是「系统真的起了前台服务」。
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/platform/android/foreground_service.dart';

/// 记录调用并按脚本应答的假通道。
final class FakeChannel {
  final List<MethodCall> calls = <MethodCall>[];

  final Map<String, Object? Function(Map<String, Object?> args)> handlers =
      <String, Object? Function(Map<String, Object?>)>{};

  void on(String method, Object? Function(Map<String, Object?> args) fn) {
    handlers[method] = fn;
  }

  Future<Object?> dispatch(MethodCall call) async {
    calls.add(call);
    final Map<String, Object?> args =
        (call.arguments as Map<Object?, Object?>? ?? <Object?, Object?>{}).cast<
          String,
          Object?
        >();
    final Object? Function(Map<String, Object?>)? handler = handlers[call.method];
    if (handler == null) {
      throw MissingPluginException('未注册的假方法: ${call.method}');
    }
    return handler(args);
  }

  List<MethodCall> callsOf(String method) =>
      calls.where((MethodCall c) => c.method == method).toList();
}

void installChannel(FakeChannel fake) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel(kForegroundChannelName),
        fake.dispatch,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('状态机：有共享才起、无共享即停', () {
    test('初始状态不运行，且不持组播锁', () {
      final ForegroundServiceMachine machine = ForegroundServiceMachine();
      expect(machine.state.running, isFalse);
      expect(machine.state.holdsMulticastLock, isFalse);
      expect(machine.state, ForegroundServiceState.stopped);
    });

    test('shareCount = 0 时不起服务，理由里说清「立即停止」', () {
      final ForegroundServiceMachine machine = ForegroundServiceMachine();
      final ForegroundDecision decision = machine.update(shareCount: 0);
      expect(decision.shouldRun, isFalse);
      expect(decision.nextState.running, isFalse);
      expect(decision.reason, contains('没有活跃共享'));
      expect(decision.reason, isNotEmpty);
    });

    test('shareCount > 0 即起服务，即使还没人连上', () {
      final ForegroundServiceMachine machine = ForegroundServiceMachine();
      final ForegroundDecision decision = machine.update(
        shareCount: 3,
        connectedPeers: 0,
      );
      expect(decision.shouldRun, isTrue);
      expect(decision.nextState.running, isTrue);
      expect(decision.nextState.shareCount, 3);
      expect(decision.nextState.connectedPeers, 0);
    });

    test('有共享时持组播锁；清零后立刻释放', () {
      final ForegroundServiceMachine machine = ForegroundServiceMachine();
      machine.update(shareCount: 2);
      expect(machine.state.holdsMulticastLock, isTrue);
      machine.clear();
      expect(machine.state.holdsMulticastLock, isFalse);
      expect(machine.state.running, isFalse);
    });

    test('负数计数按 0 处理，不抛异常（UI 抖动不该炸服务）', () {
      final ForegroundServiceMachine machine = ForegroundServiceMachine();
      final ForegroundDecision decision = machine.update(
        shareCount: -5,
        connectedPeers: -2,
      );
      expect(decision.shouldRun, isFalse);
      expect(machine.shareCount, 0);
      expect(machine.connectedPeers, 0);
    });

    test('通知栏文案符合「N 个文件 · 已连接 X 台」', () {
      const ForegroundServiceState state = ForegroundServiceState(
        running: true,
        shareCount: 12,
        connectedPeers: 3,
      );
      expect(state.notificationTitle, '共享中');
      expect(state.notificationBody, '12 个文件 · 已连接 3 台');
      expect(state.stopActionLabel, '停止共享');
    });

    test('通知栏计数上溢被钳制，不会出现天文数字', () {
      const ForegroundServiceState state = ForegroundServiceState(
        running: true,
        shareCount: 1 << 30,
        connectedPeers: -1,
      );
      expect(state.notificationBody, contains(kForegroundMaxCount.toString()));
      expect(state.notificationBody, contains('已连接 0 台'));
    });

    test('停止态的通知栏标题不冒充「共享中」', () {
      expect(ForegroundServiceState.stopped.notificationTitle, '已停止共享');
    });
  });

  group('通道载荷编解码', () {
    test('toChannelArguments 的键与 Kotlin 侧常量一一对应', () {
      const ForegroundServiceState state = ForegroundServiceState(
        running: true,
        shareCount: 4,
        connectedPeers: 2,
      );
      final Map<String, Object?> args = state.toChannelArguments();
      expect(args.keys.toSet(), <String>{
        'running',
        'shareCount',
        'connectedPeers',
      });
      expect(args['running'], isTrue);
      expect(args['shareCount'], 4);
      expect(args['connectedPeers'], 2);
    });
  });

  group('通道桥：异常映射（mock，非真机）', () {
    late FakeChannel fake;
    late ForegroundServiceBridge bridge;

    setUp(() {
      fake = FakeChannel();
      installChannel(fake);
      bridge = const ForegroundServiceBridge();
    });

    test('apply 把状态推成 Map，字段齐全', () async {
      fake.on('apply', (Map<String, Object?> args) => null);
      await bridge.apply(
        const ForegroundServiceState(
          running: true,
          shareCount: 7,
          connectedPeers: 1,
        ),
      );
      final MethodCall call = fake.callsOf('apply').single;
      final Map<Object?, Object?> sent = call.arguments as Map<Object?, Object?>;
      expect(sent['running'], isTrue);
      expect(sent['shareCount'], 7);
      expect(sent['connectedPeers'], 1);
    });

    test('notificationDenied 映射为可读的权限提示', () async {
      fake.on('apply', (Map<String, Object?> args) {
        throw PlatformException(code: 'notificationDenied', message: 'no perm');
      });
      await expectLater(
        bridge.apply(const ForegroundServiceState(running: true, shareCount: 1)),
        throwsA(
          isA<ForegroundServiceFailure>()
              .having(
                (ForegroundServiceFailure e) => e.kind,
                'kind',
                ForegroundFailureKind.notificationDenied,
              )
              .having(
                (ForegroundServiceFailure e) => e.userMessage,
                'userMessage',
                contains('通知权限'),
              ),
        ),
      );
    });

    test('startRejected 映射为后台限制提示', () async {
      fake.on('apply', (Map<String, Object?> args) {
        throw PlatformException(code: 'startRejected');
      });
      await expectLater(
        bridge.apply(const ForegroundServiceState(running: true, shareCount: 1)),
        throwsA(
          isA<ForegroundServiceFailure>().having(
            (ForegroundServiceFailure e) => e.kind,
            'kind',
            ForegroundFailureKind.startRejected,
          ),
        ),
      );
    });

    test('未知错误码落到 unknown，且消息里保留原始 code', () async {
      fake.on('apply', (Map<String, Object?> args) {
        throw PlatformException(code: 'weirdError', message: 'boom');
      });
      await expectLater(
        bridge.apply(const ForegroundServiceState(running: true, shareCount: 1)),
        throwsA(
          isA<ForegroundServiceFailure>()
              .having(
                (ForegroundServiceFailure e) => e.kind,
                'kind',
                ForegroundFailureKind.unknown,
              )
              .having(
                (ForegroundServiceFailure e) => e.message,
                'message',
                contains('weirdError'),
              ),
        ),
      );
    });

    test('通道缺失映射为 notAndroid，而不是静默成功', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(kForegroundChannelName),
            null,
          );
      await expectLater(
        bridge.apply(ForegroundServiceState.stopped),
        throwsA(
          isA<ForegroundServiceFailure>().having(
            (ForegroundServiceFailure e) => e.kind,
            'kind',
            ForegroundFailureKind.notAndroid,
          ),
        ),
      );
      installChannel(fake);
    });

    test('isRunning 返回非 bool 时报错，不瞎猜', () async {
      fake.on('isRunning', (Map<String, Object?> args) => 'yes');
      await expectLater(
        bridge.isRunning(),
        throwsA(isA<ForegroundServiceFailure>()),
      );
    });

    test('syncMulticastLock 透传 hold 并回显平台结论', () async {
      fake.on('syncMulticastLock', (Map<String, Object?> args) {
        return args['hold'] == true;
      });
      expect(await bridge.syncMulticastLock(shouldHold: true), isTrue);
      expect(await bridge.syncMulticastLock(shouldHold: false), isFalse);
      final List<MethodCall> calls = fake.callsOf('syncMulticastLock');
      expect(calls.length, 2);
      expect((calls[0].arguments as Map<Object?, Object?>)['hold'], isTrue);
      expect((calls[1].arguments as Map<Object?, Object?>)['hold'], isFalse);
    });
  });

  group('控制器：只在变化时推送', () {
    test('首次 sync 推一次，重复同状态不再打扰平台', () async {
      final FakeChannel fake = FakeChannel();
      installChannel(fake);
      fake.on('apply', (Map<String, Object?> args) => null);
      final ForegroundServiceController controller = ForegroundServiceController(
        bridge: const ForegroundServiceBridge(),
      );

      await controller.sync(shareCount: 5, connectedPeers: 1);
      expect(fake.callsOf('apply').length, 1);

      await controller.sync(shareCount: 5, connectedPeers: 1);
      expect(fake.callsOf('apply').length, 1, reason: '状态未变不应重推');

      await controller.sync(shareCount: 0);
      expect(fake.callsOf('apply').length, 2, reason: '清零必须推');
      final MethodCall stop = fake.callsOf('apply').last;
      expect((stop.arguments as Map<Object?, Object?>)['running'], isFalse);
    });

    test('clear 保证服务停下并释放锁', () async {
      final FakeChannel fake = FakeChannel();
      installChannel(fake);
      fake.on('apply', (Map<String, Object?> args) => null);
      final ForegroundServiceController controller = ForegroundServiceController(
        bridge: const ForegroundServiceBridge(),
      );
      await controller.sync(shareCount: 3);
      expect(controller.state.holdsMulticastLock, isTrue);

      final ForegroundDecision decision = await controller.clear();
      expect(decision.shouldRun, isFalse);
      expect(controller.state.holdsMulticastLock, isFalse);
    });

    test('平台说没在跑时 reconcile 把本地状态校正为 stopped', () async {
      final FakeChannel fake = FakeChannel();
      installChannel(fake);
      fake.on('isRunning', (Map<String, Object?> args) => false);
      final ForegroundServiceController controller = ForegroundServiceController(
        bridge: const ForegroundServiceBridge(),
      );
      final ForegroundServiceState state = await controller.reconcile();
      expect(state.running, isFalse);
    });

    test('非安卓（通道缺失）时 reconcile 不抛错，返回 stopped', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(kForegroundChannelName),
            null,
          );
      final ForegroundServiceController controller = ForegroundServiceController(
        bridge: const ForegroundServiceBridge(),
      );
      final ForegroundServiceState state = await controller.reconcile();
      expect(state.running, isFalse);
    });
  });
}
