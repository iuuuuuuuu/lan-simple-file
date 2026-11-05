// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/platform/default_nickname.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(deviceNameChannel, null));

  test(
    'Android uses the configured device name, trimmed and length-limited',
    () async {
      messenger.setMockMethodCallHandler(deviceNameChannel, (call) async {
        expect(call.method, 'getDeviceName');
        return '  My Android  ';
      });
      expect(
        await loadDefaultNickname(operatingSystem: 'android'),
        'My Android',
      );
      messenger.setMockMethodCallHandler(
        deviceNameChannel,
        (_) async => 'a' * 80,
      );
      expect(
        (await loadDefaultNickname(operatingSystem: 'android')).length,
        64,
      );
    },
  );

  test(
    'blank, unavailable and denied Android names have a readable fallback',
    () async {
      for (final name in ['', '   ', null]) {
        messenger.setMockMethodCallHandler(
          deviceNameChannel,
          (_) async => name,
        );
        expect(
          await loadDefaultNickname(operatingSystem: 'android'),
          'Android',
        );
      }
      messenger.setMockMethodCallHandler(deviceNameChannel, (_) async {
        throw PlatformException(code: 'denied');
      });
      expect(await loadDefaultNickname(operatingSystem: 'android'), 'Android');
      messenger.setMockMethodCallHandler(deviceNameChannel, null);
      expect(await loadDefaultNickname(operatingSystem: 'android'), 'Android');
    },
  );

  test(
    'desktop keeps account naming without invoking the Android channel',
    () async {
      var invoked = false;
      messenger.setMockMethodCallHandler(deviceNameChannel, (_) async {
        invoked = true;
        return 'Android name';
      });
      for (final os in ['windows', 'macos', 'linux']) {
        expect(
          await loadDefaultNickname(operatingSystem: os),
          resolveDefaultNickname(),
        );
      }
      expect(invoked, isFalse);
      expect(
        resolveDefaultNickname(environment: {'USERNAME': ' Win user '}),
        'Win user',
      );
      expect(
        resolveDefaultNickname(environment: {'USER': 'Mac user'}),
        'Mac user',
      );
    },
  );
}
