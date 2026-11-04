// SPDX-License-Identifier: GPL-3.0-only

/// DeviceIdentityImpl 的落盘、重载与损坏检测。
///
/// 注意：**不**测 `loadOrCreateInAppData` —— 它依赖 `path_provider`
/// 的平台通道，在 `flutter test` 的宿主环境里没有实现。这里测的是
/// 纯 Dart 的 `loadOrCreate(dataDir:)`，也就是生产路径的核心逻辑。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/errors.dart';
import 'package:lan_simple_file/core/contracts/types.dart';
import 'package:lan_simple_file/core/identity/device_identity_impl.dart';
import 'package:lan_simple_file/core/identity/ed25519_signer.dart';

import 'test_support.dart';

late Directory testDir;
late File identityFile;

void main() {
  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('lsf_identity_');
    identityFile = File(
      '${testDir.path}${Platform.pathSeparator}$kIdentityFileName',
    );
  });

  tearDown(() async {
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }
  });

  group('loadOrCreate', () {
    test('首次调用生成 identity.key，含 v/alg/seed/pub 四个字段', () async {
      expect(await identityFile.exists(), isFalse);
      final DeviceIdentityImpl identity =
          await DeviceIdentityImpl.loadOrCreate(dataDir: testDir);
      expect(await identityFile.exists(), isTrue);

      final Map<String, Object?> stored =
          jsonDecode(await identityFile.readAsString())! as Map<String, Object?>;
      expect(stored['v'], kIdentityFileVersion);
      expect(stored['alg'], 'ed25519');
      expect((stored['seed']! as String).contains('='), isFalse);
      expect((stored['pub']! as String).contains('='), isFalse);
      expect(identity.publicKey.length, 32);
      expect(identity.peerId, equals(derivePeerId(identity.publicKey)));
    });

    test('同一目录二次调用返回同一身份（peerId 稳定，不重新生成）', () async {
      final DeviceIdentityImpl first =
          await DeviceIdentityImpl.loadOrCreate(dataDir: testDir);
      final DeviceIdentityImpl second =
          await DeviceIdentityImpl.loadOrCreate(dataDir: testDir);
      expect(second.peerId, equals(first.peerId));
      expect(bytesToHex(second.publicKey), bytesToHex(first.publicKey));
    });

    test('重启后仍能把已有身份签出的签名验过', () async {
      final DeviceIdentityImpl first =
          await DeviceIdentityImpl.loadOrCreate(dataDir: testDir);
      final Uint8List payload = Uint8List.fromList('persist'.codeUnits);
      final Uint8List signature = await first.sign(payload);

      final DeviceIdentityImpl reloaded =
          await DeviceIdentityImpl.loadOrCreate(dataDir: testDir);
      expect(await reloaded.verifyOwn(payload, signature), isTrue);
      expect(
        await Ed25519Signer().verify(payload, signature, reloaded.publicKey),
        isTrue,
      );
    });

    test('目录不存在时自动创建', () async {
      final Directory nested = Directory(
        '${testDir.path}${Platform.pathSeparator}x'
        '${Platform.pathSeparator}y',
      );
      expect(await nested.exists(), isFalse);
      await DeviceIdentityImpl.loadOrCreate(dataDir: nested);
      expect(
        await File('${nested.path}${Platform.pathSeparator}$kIdentityFileName')
            .exists(),
        isTrue,
      );
    });

    test('并发首次创建只会留下一个身份（rename 抢占）', () async {
      final List<DeviceIdentityImpl> results = await Future.wait(
        <Future<DeviceIdentityImpl>>[
          DeviceIdentityImpl.loadOrCreate(dataDir: testDir),
          DeviceIdentityImpl.loadOrCreate(dataDir: testDir),
          DeviceIdentityImpl.loadOrCreate(dataDir: testDir),
        ],
      );
      for (final DeviceIdentityImpl identity in results) {
        expect(identity.peerId, equals(results.first.peerId));
      }
      expect(
        await File('${identityFile.path}.tmp').exists(),
        isFalse,
        reason: '失败方的临时文件必须被清理',
      );
    });
  });

  group('损坏检测（必须显式报错，不许静默重建身份）', () {
    Future<void> expectIoError(Future<DeviceIdentityImpl> future) async {
      await expectLater(
        future,
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.io,
          ),
        ),
      );
    }

    test('非 JSON', () async {
      await identityFile.writeAsString('nope');
      await expectIoError(DeviceIdentityImpl.loadOrCreate(dataDir: testDir));
    });

    test('顶层不是对象', () async {
      await identityFile.writeAsString('[1,2,3]');
      await expectIoError(DeviceIdentityImpl.loadOrCreate(dataDir: testDir));
    });

    test('版本或算法不受支持', () async {
      await identityFile.writeAsString(
        jsonEncode(<String, Object?>{'v': 99, 'alg': 'ed25519', 'seed': 'AA', 'pub': 'AA'}),
      );
      await expectIoError(DeviceIdentityImpl.loadOrCreate(dataDir: testDir));

      await identityFile.writeAsString(
        jsonEncode(<String, Object?>{'v': 1, 'alg': 'secp256k1', 'seed': 'AA', 'pub': 'AA'}),
      );
      await expectIoError(DeviceIdentityImpl.loadOrCreate(dataDir: testDir));
    });

    test('密钥不是合法 base64url', () async {
      await identityFile.writeAsString(
        jsonEncode(<String, Object?>{'v': 1, 'alg': 'ed25519', 'seed': '!!', 'pub': 'AA'}),
      );
      await expectIoError(DeviceIdentityImpl.loadOrCreate(dataDir: testDir));
    });

    test('种子长度不对', () async {
      await identityFile.writeAsString(
        jsonEncode(<String, Object?>{
          'v': 1,
          'alg': 'ed25519',
          'seed': base64Url.encode(Uint8List(16)).replaceAll('=', ''),
          'pub': base64Url.encode(Uint8List(32)).replaceAll('=', ''),
        }),
      );
      await expectIoError(DeviceIdentityImpl.loadOrCreate(dataDir: testDir));
    });

    test('公钥与种子不匹配（有人手改文件想换身份）', () async {
      final Uint8List seed = fixedSeedA;
      final Uint8List wrongPublic = deriveEd25519PublicKeyFromSeed(fixedSeedB);
      await identityFile.writeAsString(
        jsonEncode(<String, Object?>{
          'v': 1,
          'alg': 'ed25519',
          'seed': base64Url.encode(seed).replaceAll('=', ''),
          'pub': base64Url.encode(wrongPublic).replaceAll('=', ''),
        }),
      );
      await expectIoError(DeviceIdentityImpl.loadOrCreate(dataDir: testDir));
    });
  });

  group('exportSeed', () {
    test('导出的种子能重建出同一身份', () {
      final DeviceIdentityImpl origin = DeviceIdentityImpl.fromSeed(fixedSeedA);
      final DeviceIdentityImpl rebuilt =
          DeviceIdentityImpl.fromSeed(origin.exportSeed());
      expect(rebuilt.peerId, equals(origin.peerId));
      expect(bytesToHex(rebuilt.publicKey), bytesToHex(origin.publicKey));
    });

    test('exportSeed 返回副本，外部改动不影响身份', () {
      final DeviceIdentityImpl identity = DeviceIdentityImpl.fromSeed(fixedSeedA);
      final PeerId before = identity.peerId;
      identity.exportSeed()[0] ^= 0xff;
      expect(identity.peerId, before);
    });
  });

  group('锁失败必须显式报错，不许无锁写盘', () {
    test('锁被长期占用且身份不存在时抛 io，且不写出 identity.key', () async {
      final File lock = File(
        '${testDir.path}${Platform.pathSeparator}$kIdentityLockFileName',
      );
      await lock.create(exclusive: true);
      await expectLater(
        DeviceIdentityImpl.loadOrCreate(dataDir: testDir),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.io,
          ),
        ),
      );
      expect(await identityFile.exists(), isFalse);
      await lock.delete();
    });
  });
}
