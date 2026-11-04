// SPDX-License-Identifier: GPL-3.0-only

/// 权限引导与退出前置校验的测试。
///
/// **诚实边界**：全部是 mock 通道 + 纯函数。**没有真机**。
/// 验证的是「缺项判定顺序、文案、请求路由」，不是「系统真的弹了授权对话框」。
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/platform/android/permission_flow.dart';

final class FakePermissionChannel {
  final List<MethodCall> calls = <MethodCall>[];
  final Map<String, Object? Function(Map<String, Object?> args)> handlers = {};

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

  List<MethodCall> called(String method) =>
      calls.where((MethodCall c) => c.method == method).toList();
}

void installPermissionChannel(FakePermissionChannel fake) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel(kPermissionChannelName),
        fake.dispatch,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('步骤顺序与文案', () {
    test('三步顺序固定：通知 -> 电池优化 -> SAF', () {
      expect(PermissionStep.values, <PermissionStep>[
        PermissionStep.notifications,
        PermissionStep.batteryOptimization,
        PermissionStep.safGrant,
      ]);
      expect(
        PermissionStep.notifications.next,
        PermissionStep.batteryOptimization,
      );
      expect(
        PermissionStep.batteryOptimization.next,
        PermissionStep.safGrant,
      );
      expect(PermissionStep.safGrant.next, isNull);
    });

    test('每一步都有非空的标题与解释', () {
      for (final PermissionStep step in PermissionStep.values) {
        expect(step.title, isNotEmpty);
        expect(step.explanation, isNotEmpty);
        expect(step.explanation.length, greaterThan(10));
      }
    });
  });

  group('缺项判定（纯函数）', () {
    PermissionCheck check(PermissionStep step, PermissionGrantState s) =>
        PermissionCheck(step: step, state: s);

    test('全部满足时 firstBlocking 为 null', () {
      final PermissionReport report = PermissionReport(
        androidSdk: 34,
        checks: <PermissionCheck>[
          check(PermissionStep.notifications, PermissionGrantState.granted),
          check(
            PermissionStep.batteryOptimization,
            PermissionGrantState.granted,
          ),
          check(PermissionStep.safGrant, PermissionGrantState.granted),
        ],
      );
      expect(report.allSatisfied, isTrue);
      expect(report.firstBlocking, isNull);
      expect(report.blockingSteps, isEmpty);
    });

    test('notRequired 也算满足（Android 12 及以下没有通知运行时权限）', () {
      final PermissionReport report = PermissionReport(
        androidSdk: 31,
        checks: <PermissionCheck>[
          check(PermissionStep.notifications, PermissionGrantState.notRequired),
          check(
            PermissionStep.batteryOptimization,
            PermissionGrantState.granted,
          ),
          check(PermissionStep.safGrant, PermissionGrantState.granted),
        ],
      );
      expect(report.allSatisfied, isTrue);
    });

    test('unknown 不等于已授权（判不出来必须当没授权）', () {
      final PermissionReport report = PermissionReport(
        androidSdk: 34,
        checks: <PermissionCheck>[
          check(PermissionStep.notifications, PermissionGrantState.unknown),
          check(
            PermissionStep.batteryOptimization,
            PermissionGrantState.granted,
          ),
          check(PermissionStep.safGrant, PermissionGrantState.granted),
        ],
      );
      expect(report.allSatisfied, isFalse);
      expect(report.firstBlocking, PermissionStep.notifications);
    });

    test('firstBlocking 取最靠前的那一项，blockingSteps 按顺序全列出', () {
      final PermissionReport report = PermissionReport(
        androidSdk: 34,
        checks: <PermissionCheck>[
          check(PermissionStep.notifications, PermissionGrantState.granted),
          check(PermissionStep.batteryOptimization, PermissionGrantState.denied),
          check(PermissionStep.safGrant, PermissionGrantState.denied),
        ],
      );
      expect(report.firstBlocking, PermissionStep.batteryOptimization);
      expect(report.blockingSteps, <PermissionStep>[
        PermissionStep.batteryOptimization,
        PermissionStep.safGrant,
      ]);
    });

    test('缺项文案说清「为什么」与「怎么办」', () {
      final PermissionCheck denied = check(
        PermissionStep.batteryOptimization,
        PermissionGrantState.denied,
      );
      expect(denied.userMessage, contains('电池优化'));
      expect(denied.userMessage, contains('未授权'));
      expect(denied.userMessage, contains('息屏'));

      final PermissionCheck unknown = check(
        PermissionStep.safGrant,
        PermissionGrantState.unknown,
        );
      expect(unknown.userMessage, contains('无法确认'));

      final PermissionCheck ok = check(
        PermissionStep.safGrant,
        PermissionGrantState.granted,
      );
      expect(ok.userMessage, contains('已就绪'));
    });
  });

  group('引导流：查状态并按需请求（mock）', () {
    late FakePermissionChannel fake;
    late PermissionFlow flow;

    setUp(() {
      fake = FakePermissionChannel();
      installPermissionChannel(fake);
      flow = PermissionFlow(bridge: const PermissionBridge());
    });

    test('Android 13 以下把通知标为 notRequired，其余缺项照常阻塞', () async {
      fake.on('androidSdk', (Map<String, Object?> args) => 31);
      fake.on(
        'queryStates',
        (Map<String, Object?> args) => <String, String>{
          'notifications': 'denied',
          'batteryOptimization': 'granted',
          'safGrant': 'granted',
        },
      );
      final PermissionReport report = await flow.inspect();
      expect(
        report.checkFor(PermissionStep.notifications)!.state,
        PermissionGrantState.notRequired,
      );
      expect(report.allSatisfied, isTrue);
    });

    test('Android 13+ 通知被拒时成为第一个阻塞项', () async {
      fake.on('androidSdk', (Map<String, Object?> args) => 34);
      fake.on(
        'queryStates',
        (Map<String, Object?> args) => <String, String>{
          'notifications': 'denied',
          'batteryOptimization': 'granted',
          'safGrant': 'granted',
        },
      );
      final PermissionReport report = await flow.inspect();
      expect(report.firstBlocking, PermissionStep.notifications);
      expect(
        report.checkFor(PermissionStep.notifications)!.state,
        PermissionGrantState.denied,
      );
    });

    test('interactive 只推进一步（不同时弹多个系统页）', () async {
      fake.on('androidSdk', (Map<String, Object?> args) => 34);
      fake.on(
        'queryStates',
        (Map<String, Object?> args) => <String, String>{
          'notifications': 'granted',
          'batteryOptimization': 'denied',
          'safGrant': 'denied',
        },
      );
      fake.on('request', (Map<String, Object?> args) => true);
      await flow.run(interactive: true);
      final List<MethodCall> requests = fake.called('request');
      expect(requests.length, 1, reason: '一次只推进一个步骤');
      expect(
        (requests.single.arguments as Map<Object?, Object?>)['step'],
        PermissionStep.batteryOptimization.name,
      );
    });

    test('非交互模式不请求任何权限', () async {
      fake.on('androidSdk', (Map<String, Object?> args) => 34);
      fake.on(
        'queryStates',
        (Map<String, Object?> args) => <String, String>{
          'notifications': 'denied',
        },
      );
      await flow.inspect();
      expect(fake.called('request'), isEmpty);
    });

    test('通道缺失时状态全为 unknown，最终判为未就绪', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(kPermissionChannelName),
            null,
          );
      final PermissionFlow offDevice = PermissionFlow(
        bridge: const PermissionBridge(),
      );
      final PermissionReport report = await offDevice.inspect();
      expect(report.allSatisfied, isFalse);
      expect(
        report.checkFor(PermissionStep.safGrant)!.state,
        PermissionGrantState.unknown,
      );
      installPermissionChannel(fake);
    });

    test('请求失败时上抛可判定类型，不静默返回 false', () async {
      fake.on('androidSdk', (Map<String, Object?> args) => 34);
      fake.on(
        'queryStates',
        (Map<String, Object?> args) => <String, String>{
          'notifications': 'denied',
        },
      );
      fake.on('request', (Map<String, Object?> args) {
        throw PlatformException(code: 'boom', message: 'nope');
      });
      await expectLater(
        flow.run(interactive: true),
        throwsA(
          isA<PermissionFlowFailure>().having(
            (PermissionFlowFailure e) => e.kind,
            'kind',
            PermissionFailureKind.requestFailed,
          ),
        ),
      );
    });

    test('用户拒绝后状态记为 denied，不会假装已授权', () async {
      fake.on('androidSdk', (Map<String, Object?> args) => 34);
      fake.on(
        'queryStates',
        (Map<String, Object?> args) => <String, String>{
          'notifications': 'denied',
          'batteryOptimization': 'granted',
          'safGrant': 'granted',
        },
      );
      fake.on('request', (Map<String, Object?> args) => false);
      final PermissionReport report = await flow.run(interactive: true);
      expect(
        report.checkFor(PermissionStep.notifications)!.state,
        PermissionGrantState.denied,
      );
      expect(report.allSatisfied, isFalse);
    });
  });

  group('退出前置校验', () {
    test('没有任何进行中的事情时不需要确认', () {
      final ExitGuardDecision decision = evaluateExitGuard(
        unfinishedTransfers: 0,
        activeDownloads: 0,
      );
      expect(decision.needsConfirmation, isFalse);
      expect(decision.confirmationMessage, isEmpty);
    });

    test('有未完成传输时需要确认，文案说明数量', () {
      final ExitGuardDecision decision = evaluateExitGuard(
        unfinishedTransfers: 3,
        activeDownloads: 0,
      );
      expect(decision.needsConfirmation, isTrue);
      expect(decision.confirmationMessage, contains('3 个传输进行中'));
      expect(decision.confirmationMessage, contains('确定要退出吗'));
    });

    test('被他人下载时也需要确认', () {
      final ExitGuardDecision decision = evaluateExitGuard(
        unfinishedTransfers: 0,
        activeDownloads: 2,
      );
      expect(decision.needsConfirmation, isTrue);
      expect(decision.confirmationMessage, contains('2 台设备正在下载'));
    });

    test('两者都有时文案列出两条', () {
      final ExitGuardDecision decision = evaluateExitGuard(
        unfinishedTransfers: 1,
        activeDownloads: 4,
      );
      expect(decision.confirmationMessage, contains('1 个传输进行中'));
      expect(decision.confirmationMessage, contains('4 台设备正在下载'));
      expect(decision.confirmationMessage, contains('，'));
    });

    test('负数计数按 0 处理', () {
      final ExitGuardDecision decision = evaluateExitGuard(
        unfinishedTransfers: -1,
        activeDownloads: -3,
      );
      expect(decision.needsConfirmation, isFalse);
      expect(decision.unfinishedTransfers, 0);
      expect(decision.activeDownloads, 0);
    });
  });
}
