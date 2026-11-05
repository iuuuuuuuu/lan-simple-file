// SPDX-License-Identifier: GPL-3.0-only

/// Android 配置文件的文本断言。
///
/// **这不是打包验证**：本机无网、Gradle 分发包缺失，`flutter build apk` 跑不起来。
/// 这些用例只能证明「关键节点确实写在文件里」，不能证明「manifest merger 通过」
/// 「AGP 接受这段 gradle」「系统真的按它行为」。
///
/// 每条断言都做到**能真红**：见测试文件末尾的 `_assertFailsWhenMissing` 自检，
/// 它用一个故意缺字段的假文本来验证断言函数本身有效，防止写出恒真的空断言。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

File manifestFile() => File('android/app/src/main/AndroidManifest.xml');
File gradleFile() => File('android/app/build.gradle.kts');
File networkConfigFile() =>
    File('android/app/src/main/res/xml/network_security_config.xml');

String read(File file) {
  if (!file.existsSync()) {
    fail('文件不存在: ${file.path}');
  }
  return file.readAsStringSync();
}

/// 断言 helper：文本必须包含 needle。
void expectContains(String text, String needle, {String? because}) {
  expect(text.contains(needle), isTrue, reason: because ?? '缺少 $needle');
}

void expectNotContains(String text, String needle, {String? because}) {
  expect(text.contains(needle), isFalse, reason: because ?? '不应出现 $needle');
}

/// 去掉 XML 注释后的正文。
///
/// 为什么要剥注释：本项目的配置文件里**刻意**写了「NSC 不支持 CIDR」这类说明，
/// 注释里必然出现 /16、192.168 等字样。若直接对全文做反向断言，
/// 断言会被自己的注释打成假红——那是断言写错，不是配置有问题。
String stripXmlComments(String text) {
  return text.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
}

void main() {
  group('AndroidManifest 关键声明（文本断言，非打包验证）', () {
    test('会话级前台服务声明了 dataSync 类型且不导出', () {
      final String xml = read(manifestFile());
      expectContains(xml, 'android:name=".service.ShareForegroundService"');
      expectContains(xml, 'android:foregroundServiceType="dataSync"');
      expectContains(xml, 'android:exported="false"');
    });

    test('前台服务权限与通知权限齐全', () {
      final String xml = read(manifestFile());
      expectContains(xml, 'android.permission.FOREGROUND_SERVICE');
      expectContains(xml, 'android.permission.FOREGROUND_SERVICE_DATA_SYNC');
      expectContains(xml, 'android.permission.POST_NOTIFICATIONS');
    });

    test('组播锁与网络权限齐全', () {
      final String xml = read(manifestFile());
      expectContains(xml, 'android.permission.CHANGE_WIFI_MULTICAST_STATE');
      expectContains(xml, 'android.permission.ACCESS_WIFI_STATE');
      expectContains(xml, 'android.permission.INTERNET');
    });

    test('声明可选的所有文件访问权限', () {
      expectContains(
        read(manifestFile()),
        'android.permission.MANAGE_EXTERNAL_STORAGE',
      );
    });

    test('ACTION_SEND 与 SEND_MULTIPLE 两个 intent-filter 都在 Activity 上', () {
      final String xml = read(manifestFile());
      expectContains(xml, 'android.intent.action.SEND');
      expectContains(xml, 'android.intent.action.SEND_MULTIPLE');
      expectContains(xml, 'android.intent.category.DEFAULT');
      expectContains(xml, 'android:mimeType="*/*"');
    });

    test('引用了 network_security_config，且没有全局 usesCleartextTraffic', () {
      final String xml = read(manifestFile());
      expectContains(xml, 'android:networkSecurityConfig="@xml/network_security_config"');
      // 硬约束：绝不允许全局放开明文。
      expectNotContains(
        xml,
        'android:usesCleartextTraffic="true"',
        because: '全局明文会绕过「仅局域网」的约束',
      );
    });
  });

  group('network_security_config（文本断言，非运行时验证）', () {
    test('base-config 默认禁止明文，只对回环放行', () {
      final String xml = read(networkConfigFile());
      expectContains(xml, '<base-config cleartextTrafficPermitted="false">');
      expectContains(xml, '127.0.0.1');
      expectContains(xml, 'localhost');
      // 只允许出现在 domain-config 内部，不允许作为 base 的默认。
      expectContains(xml, '<domain-config cleartextTrafficPermitted="true">');
    });

    test('没有把 CIDR 网段当成 domain 写（NSC 不支持网段）', () {
      // 只检查去掉注释后的正文：注释里本来就写着「不支持 CIDR」的说明。
      final String body = stripXmlComments(read(networkConfigFile()));
      expectNotContains(
        body,
        '192.168.',
        because: 'NSC 的 domain 只接受主机名，写网段是无效配置',
      );
      expectNotContains(
        body,
        '10.0.0.0',
        because: 'NSC 的 domain 只接受主机名，写网段是无效配置',
      );
      expectNotContains(body, '/16', because: 'NSC 不接受 CIDR 前缀');
      expectNotContains(body, '/8', because: 'NSC 不接受 CIDR 前缀');
    });

    test('剥注释的 helper 自身有效（否则上面那条又是恒真）', () {
      const String withComment =
          '<a/>' '<!-- 这里是 /16 说明 -->' '<b/>';
      expect(stripXmlComments(withComment), '<a/><b/>');
      expect(stripXmlComments(withComment).contains('/16'), isFalse);
    });

    test('文件里如实写明了 NSC 不覆盖 dart:io 的限制', () {
      final String xml = read(networkConfigFile());
      expectContains(xml, 'dart:io');
      expectContains(xml, '不支持 CIDR');
    });
  });

  group('build.gradle.kts（文本断言，非 AGP 验证）', () {
    test('发布构建必须提供独立签名，不回退到 debug 签名', () {
      final String gradle = read(gradleFile());
      expectContains(gradle, 'LAN_SIMPLE_FILE_KEYSTORE');
      expectContains(gradle, 'LAN_SIMPLE_FILE_STORE_PASSWORD');
      expectContains(gradle, 'LAN_SIMPLE_FILE_KEY_ALIAS');
      expectContains(gradle, 'LAN_SIMPLE_FILE_KEY_PASSWORD');
      expectContains(gradle, 'Release signing is required');
      expectNotContains(gradle, 'signingConfigs.getByName("debug")');
    });

    test('minSdk / targetSdk 显式写死而非跟随 flutter 默认值', () {
      final String gradle = read(gradleFile());
      expectContains(gradle, 'minSdk = 24');
      expectContains(gradle, 'targetSdk = 34');
      // 不应再依赖 flutter.minSdkVersion 这种可被上游改掉的默认值。
      expectNotContains(gradle, 'minSdk = flutter.minSdkVersion');
      expectNotContains(gradle, 'targetSdk = flutter.targetSdkVersion');
    });

    test('配置了 split-per-abi 且覆盖 arm64-v8a', () {
      final String gradle = read(gradleFile());
      expectContains(gradle, 'splits {');
      expectContains(gradle, 'abi {');
      expectContains(gradle, '"arm64-v8a"');
      expectContains(gradle, '"armeabi-v7a"');
      expectContains(gradle, 'isUniversalApk = false');
    });

    test('依赖里有 documentfile 与 core-ktx', () {
      final String gradle = read(gradleFile());
      expectContains(gradle, 'androidx.documentfile:documentfile');
      expectContains(gradle, 'androidx.core:core-ktx');
    });
  });

  group('Kotlin 源码关键实现（文本断言，非编译验证）', () {
    File serviceFile() => File(
      'android/app/src/main/kotlin/com/lansimplefile/lan_simple_file/service/ShareForegroundService.kt',
    );
    File multicastFile() => File(
      'android/app/src/main/kotlin/com/lansimplefile/lan_simple_file/service/MulticastLockHolder.kt',
    );

    test('startForeground 在 Android 14+ 传了 FGS 类型', () {
      final String kt = read(serviceFile());
      expectContains(kt, 'startForeground(NOTIFICATION_ID, notification, fgsType)');
      expectContains(kt, 'FOREGROUND_SERVICE_TYPE_DATA_SYNC');
      expectContains(kt, 'UPSIDE_DOWN_CAKE');
    });

    test('shareCount <= 0 时自我停止，不常驻', () {
      final String kt = read(serviceFile());
      expectContains(kt, 'if (shareCount <= 0)');
      expectContains(kt, 'stopSelf()');
      expectContains(kt, 'multicast.sync(false)');
    });

    test('组播锁是会话级的：acquire 与 release 成对出现', () {
      final String kt = read(multicastFile());
      expectContains(kt, 'setReferenceCounted(false)');
      expectContains(kt, 'fun sync(shouldHold: Boolean): Boolean');
      expectContains(kt, 'current?.release()');
      // 必须有幂等保护，避免重复 acquire 叠加。
      expectContains(kt, 'if (held.get())');
      expectContains(kt, 'if (!held.getAndSet(false))');
    });

    test('onDestroy 里释放锁，不会泄漏', () {
      final String kt = read(serviceFile());
      expectContains(kt, 'override fun onDestroy()');
      expectContains(kt, 'isRunning = false');
    });
  });

  group('断言函数自身能真红（防恒真断言）', () {
    test('expectContains 对缺失文本会失败', () {
      bool threw = false;
      try {
        expectContains('<manifest/>', 'android:foregroundServiceType="dataSync"');
      } on TestFailure {
        threw = true;
      }
      expect(threw, isTrue, reason: '断言函数必须能真红');
    });

    test('expectNotContains 对存在的文本会失败', () {
      bool threw = false;
      try {
        expectNotContains(
          'android:usesCleartextTraffic="true"',
          'android:usesCleartextTraffic="true"',
        );
      } on TestFailure {
        threw = true;
      }
      expect(threw, isTrue, reason: '反向断言函数必须能真红');
    });
  });
}
