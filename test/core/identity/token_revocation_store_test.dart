// SPDX-License-Identifier: GPL-3.0-only

/// TokenRevocationStore 的内存 + 落盘双层语义。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/errors.dart';
import 'package:lan_simple_file/core/identity/token_revocation_store.dart';

/// 每个用例一个独立临时目录，互不干扰，结束即删。
late Directory testDir;
late File storeFile;

void main() {
  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('lsf_revoke_');
    storeFile = File('${testDir.path}${Platform.pathSeparator}revoked.json');
  });

  tearDown(() async {
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }
  });

  group('内存表', () {
    test('revoke 后 isRevoked 为 true，未吊销的为 false', () async {
      final TokenRevocationStore store = TokenRevocationStore();
      expect(await store.isRevoked('jti-a'), isFalse);
      await store.revoke('jti-a');
      expect(await store.isRevoked('jti-a'), isTrue);
      expect(await store.isRevoked('jti-b'), isFalse);
    });

    test('重复 revoke 幂等', () async {
      final TokenRevocationStore store = TokenRevocationStore();
      await store.revoke('jti-a');
      await store.revoke('jti-a');
      expect(store.memoryRevokedCount, 1);
      expect(await store.isRevoked('jti-a'), isTrue);
    });

    test('空 jti 不静默接受：revoke 抛 invalidArgument，isRevoked 返回 false', () async {
      final TokenRevocationStore store = TokenRevocationStore();
      await expectLater(
        store.revoke(''),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.invalidArgument,
          ),
        ),
      );
      expect(await store.isRevoked(''), isFalse);
    });

    test('revokeAll 之后任何 jti 都判为已吊销', () async {
      final TokenRevocationStore store = TokenRevocationStore();
      await store.revokeAll();
      for (final String jti in <String>['jti-a', 'jti-b', 'jti-never-used']) {
        expect(await store.isRevoked(jti), isTrue, reason: jti);
      }
    });

    test('revokeAll 之后新 revoke 不破坏全量失效语义', () async {
      final TokenRevocationStore store = TokenRevocationStore();
      await store.revokeAll();
      await store.revoke('jti-a');
      expect(await store.isRevoked('jti-other'), isTrue);
    });
  });

  group('落盘表', () {
    test('落盘后新实例（模拟重启）仍记得吊销', () async {
      final TokenRevocationStore first =
          TokenRevocationStore.persistent(storeFile);
      await first.revoke('jti-persist');
      expect(first.isPersistent, isTrue);

      final TokenRevocationStore second =
          TokenRevocationStore.persistent(storeFile);
      expect(await second.isRevoked('jti-persist'), isTrue);
      expect(await second.isRevoked('jti-other'), isFalse);
    });

    test('落盘文件是稳定 JSON：按 jti 排序，重复写不产生顺序抖动', () async {
      final TokenRevocationStore store = TokenRevocationStore.persistent(storeFile);
      await store.revoke('jti-c');
      await store.revoke('jti-a');
      await store.revoke('jti-b');

      final Object? decoded = jsonDecode(await storeFile.readAsString());
      final Map<String, Object?> map = decoded! as Map<String, Object?>;
      expect(map['v'], 1);
      expect(map['jti'], <String>['jti-a', 'jti-b', 'jti-c']);

      final String before = await storeFile.readAsString();
      await store.revoke('jti-a');
      expect(await storeFile.readAsString(), before);
    });

    test('父目录不存在时自动创建', () async {
      final File nested = File(
        '${testDir.path}${Platform.pathSeparator}a'
        '${Platform.pathSeparator}b'
        '${Platform.pathSeparator}revoked.json',
      );
      final TokenRevocationStore store = TokenRevocationStore.persistent(nested);
      await store.revoke('jti-nested');
      expect(await nested.exists(), isTrue);
      expect(await TokenRevocationStore.persistent(nested).isRevoked('jti-nested'), isTrue);
    });

    test('empty 文件视为空表，不抛异常', () async {
      await storeFile.writeAsString('');
      final TokenRevocationStore store = TokenRevocationStore.persistent(storeFile);
      expect(await store.isRevoked('jti-a'), isFalse);
      await store.revoke('jti-a');
      expect(await store.isRevoked('jti-a'), isTrue);
    });

    test('文件内容损坏时抛 io 而不是静默当成空表', () async {
      await storeFile.writeAsString('{not json');
      final TokenRevocationStore store = TokenRevocationStore.persistent(storeFile);
      await expectLater(
        store.isRevoked('jti-a'),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.io,
          ),
        ),
      );
      // 结构合法但缺 jti 数组同样必须报错，不能当空表放过。
      await storeFile.writeAsString('{"v":1}');
      await expectLater(
        store.isRevoked('jti-a'),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.io,
          ),
        ),
      );
    });

    test('revokeAll 落盘后同样对所有 jti 生效且重启后仍生效', () async {
      final TokenRevocationStore store = TokenRevocationStore.persistent(storeFile);
      await store.revoke('jti-a');
      await store.revokeAll();

      final TokenRevocationStore restarted =
          TokenRevocationStore.persistent(storeFile);
      expect(await restarted.isRevoked('jti-a'), isTrue);
      expect(await restarted.isRevoked('any-later-jti'), isTrue);

      final Object? decoded = jsonDecode(await storeFile.readAsString());
      expect(
        (decoded! as Map<String, Object?>)['jti'],
        <String>[TokenRevocationStore.allTokensSentinel],
      );
    });

    test('内存命中时不读盘：文件损坏但已 revoked 的 jti 仍立即为 true', () async {
      final TokenRevocationStore store = TokenRevocationStore.persistent(storeFile);
      await store.revoke('jti-a');
      await storeFile.writeAsString('{broken');
      expect(await store.isRevoked('jti-a'), isTrue);
    });
  });
}
