// SPDX-License-Identifier: GPL-3.0-only

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/platform/android/permission_flow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(kPermissionChannelName);
  const bridge = PermissionBridge(channel: channel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('真实状态名映射，缺失或意外结果不能当作授权', () async {
    for (final entry in {
      'granted': PermissionGrantState.granted,
      'denied': PermissionGrantState.denied,
      'notRequired': PermissionGrantState.notRequired,
      'unexpected': PermissionGrantState.unknown,
      null: PermissionGrantState.unknown,
    }.entries) {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => {'allFilesAccess': entry.key},
      );
      expect(await bridge.allFilesAccessState(), entry.value);
    }
  });

  test('没有通道时状态未知，请求明确报错', () async {
    expect(await bridge.allFilesAccessState(), PermissionGrantState.unknown);
    await expectLater(
      bridge.openAllFilesAccessSettings(),
      throwsA(
        isA<PermissionFlowFailure>().having(
          (error) => error.kind,
          'kind',
          PermissionFailureKind.notAndroid,
        ),
      ),
    );
  });

  test('打开设置只发送独立请求，不假装授权', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'queryStates') {
        return {'allFilesAccess': 'denied'};
      }
      return null;
    });
    await bridge.openAllFilesAccessSettings();
    expect(calls.single.method, 'openAllFilesAccessSettings');
    expect(calls.single.arguments, isNull);
    expect(await bridge.allFilesAccessState(), PermissionGrantState.denied);
    expect(PermissionStep.values, hasLength(3));
  });

  test('系统不支持或拒绝设置页时上报失败', () async {
    for (final code in [
      'unsupported',
      'settingsUnavailable',
      'settingsRejected',
    ]) {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: code),
      );
      await expectLater(
        bridge.openAllFilesAccessSettings(),
        throwsA(
          isA<PermissionFlowFailure>()
              .having(
                (error) => error.kind,
                'kind',
                PermissionFailureKind.requestFailed,
              )
              .having((error) => error.message, 'message', contains(code)),
        ),
      );
    }
  });
}
