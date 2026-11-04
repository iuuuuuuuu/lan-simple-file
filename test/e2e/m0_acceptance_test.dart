// SPDX-License-Identifier: GPL-3.0-only

/// M0 端到端验收：跨模块串联，验证契约在真实路径上成立。
///
/// 这不是模块单测，是 Lead 侧的把关：只有真正把 A 模块的产物喂给 B 模块，
/// 才能发现「各自单测全绿但接不起来」这一类问题。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/files/local_ref.dart';
import 'package:lan_simple_file/core/files/relative_path_codec.dart';
import 'package:lan_simple_file/core/identity/capability_codec_impl.dart';
import 'package:lan_simple_file/core/identity/device_identity_impl.dart';
import 'package:lan_simple_file/core/identity/ed25519_signer.dart';
import 'package:lan_simple_file/core/identity/token_revocation_store.dart';

/// 内存版公钥查表，模拟「本机的 peers 表」。
final class _MemoryLookup implements PublicKeyLookup {
  final Map<String, Uint8List> _keys = <String, Uint8List>{};

  void add(PeerId id, Uint8List key) => _keys[id.value] = key;

  @override
  Future<Uint8List?> findPublicKey(PeerId peerId) async => _keys[peerId.value];
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lsf_e2e_');
  });
  tearDown(() {
    if (tmp.existsSync()) {
      tmp.deleteSync(recursive: true);
    }
  });

  Uint8List seedOf(int base) =>
      Uint8List.fromList(List<int>.generate(32, (int i) => (base + i) & 0xff));

  CapabilityGrant grantFor(PeerId issuer, String jti) => CapabilityGrant(
        shareId: ShareId.parse('7Qm2xK'),
        issuer: issuer,
        subject: '*',
        permissions: const <String>{'read'},
        notBefore: DateTime.utc(2026, 1, 1),
        expiresAt: DateTime.utc(2030, 1, 1),
        tokenId: jti,
      );

  group('身份与凭证跨模块串联', () {
    test('同一 seed 两次派生同一 peerId，且格式被契约接受', () {
      final Uint8List seed = seedOf(1);
      final DeviceIdentityImpl a = DeviceIdentityImpl.fromSeed(seed);
      final DeviceIdentityImpl b = DeviceIdentityImpl.fromSeed(seed);
      expect(a.peerId.value, b.peerId.value);
      expect(PeerId.parse(a.peerId.value).value, a.peerId.value);
      expect(a.peerId.value.length, 15);
      expect(derivePeerId(a.publicKey).value, a.peerId.value);
    });

    test('A 签 token，B 用 A 的公钥离线验签通过', () async {
      final DeviceIdentityImpl a = DeviceIdentityImpl.fromSeed(seedOf(1));
      final _MemoryLookup lookup = _MemoryLookup()..add(a.peerId, a.publicKey);
      final TokenRevocationStore revoked = TokenRevocationStore();
      final CapabilityCodecImpl codec = CapabilityCodecImpl(
        issuer: a,
        revoked: revoked,
        keys: lookup,
      );
      final String token = await codec.issue(grantFor(a.peerId, 'jti-e2e-1'));
      final CapabilityClaims claims = await codec.verify(token);
      expect(claims.issuer.value, a.peerId.value);
      expect(claims.shareId.value, '7Qm2xK');
      expect(claims.subject, '*');
    });

    test('篡改 payload 里的 issuer 后验签必须失败', () async {
      final DeviceIdentityImpl a = DeviceIdentityImpl.fromSeed(seedOf(1));
      final DeviceIdentityImpl impostor = DeviceIdentityImpl.fromSeed(seedOf(9));
      final _MemoryLookup lookup = _MemoryLookup()
        ..add(a.peerId, a.publicKey)
        ..add(impostor.peerId, impostor.publicKey);
      final CapabilityCodecImpl codec = CapabilityCodecImpl(
        issuer: a,
        revoked: TokenRevocationStore(),
        keys: lookup,
      );
      final String token = await codec.issue(grantFor(a.peerId, 'jti-e2e-x'));

      final List<String> segs = token.split('.');
      final Map<String, Object?> payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(segs.first))),
      ) as Map<String, Object?>;
      payload['issuer'] = impostor.peerId.value;
      final String forgedPayload =
          base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
      final String forged = '$forgedPayload.${segs.last}';

      await expectLater(codec.verify(forged), throwsA(isA<LanFileException>()));
    });

    test('未知 issuer 必须被拒，不得静默通过', () async {
      final DeviceIdentityImpl a = DeviceIdentityImpl.fromSeed(seedOf(1));
      final _MemoryLookup empty = _MemoryLookup();
      final CapabilityCodecImpl signer = CapabilityCodecImpl(
        issuer: a,
        revoked: TokenRevocationStore(),
        keys: _MemoryLookup()..add(a.peerId, a.publicKey),
      );
      final String token = await signer.issue(grantFor(a.peerId, 'jti-e2e-3'));
      final CapabilityCodecImpl stranger = CapabilityCodecImpl(
        issuer: a,
        revoked: TokenRevocationStore(),
        keys: empty,
      );
      await expectLater(stranger.verify(token), throwsA(isA<LanFileException>()));
    });

    test('token 内不得含任何网络地址', () async {
      final DeviceIdentityImpl a = DeviceIdentityImpl.fromSeed(seedOf(1));
      final CapabilityCodecImpl codec = CapabilityCodecImpl(
        issuer: a,
        revoked: TokenRevocationStore(),
        keys: _MemoryLookup()..add(a.peerId, a.publicKey),
      );
      final String token = await codec.issue(grantFor(a.peerId, 'jti-e2e-2'));
      final String payload =
          utf8.decode(base64Url.decode(base64Url.normalize(token.split('.').first)));
      expect(payload.contains('192.168.'), isFalse);
      expect(payload.contains('127.0.0.1'), isFalse);
      expect(payload.contains('http://'), isFalse);
      expect(payload.contains('47778'), isFalse);
    });
  });

  group('FileRef 与路径编解码串联', () {
    test('真实目录树：列举 -> 取 itemKey -> 反向解析 -> 读内容一致', () async {
      final Directory root = Directory('${tmp.path}${Platform.pathSeparator}root')
        ..createSync();
      final Directory ab = Directory(
        '${root.path}${Platform.pathSeparator}a${Platform.pathSeparator}b',
      )..createSync(recursive: true);
      final File target = File('${ab.path}${Platform.pathSeparator}note.txt')
        ..writeAsStringSync('端到端内容');

      final LocalRef rootRef = LocalRef.root(root.path);
      final FileEntryPage top = await rootRef.list(limit: 10);
      expect(top.entries.map((FileEntry e) => e.name), contains('a'));

      final String key = toItemKey(root.path, target.path);
      expect(key, 'a/b/note.txt');
      expect(toAbsolutePath(root.path, ItemKey.parse(key)), target.path);

      final LocalRef leaf = LocalRef(rootPath: root.path, relativePath: key);
      expect(await leaf.exists(), isTrue);
      expect(utf8.decode(await _drain(leaf.openRead())), '端到端内容');

      final FileRef viaChild = await rootRef.child(ItemKey.parse(key));
      expect(await viaChild.length(), utf8.encode('端到端内容').length);
    });

    test('路径穿越在编解码层被拒', () {
      final String rootPath = '${tmp.path}${Platform.pathSeparator}root2';
      Directory(rootPath).createSync();
      final List<String> evils = <String>[
        '../outside.txt',
        '..\\outside.txt',
        'a/../../outside.txt',
        '${tmp.path}${Platform.pathSeparator}outside.txt',
      ];
      for (final String evil in evils) {
        expect(
          () => toAbsolutePath(rootPath, ItemKey.parse(evil)),
          throwsA(isA<LanFileException>()),
          reason: '必须拒绝: $evil',
        );
      }
    });
  });

  group('大文件分片读取与校验', () {
    test('32MB 真实文件分片读，拼接后 sha256 与原文件一致', () async {
      final String bigPath = '${tmp.path}${Platform.pathSeparator}big.bin';
      final File big = File(bigPath);
      final Random rnd = Random(20261104);
      final IOSink sink = big.openWrite();
      final List<int> expected = <int>[];
      const int total = 32 * 1024 * 1024;
      while (expected.length < total) {
        final List<int> block =
            List<int>.generate(256 * 1024, (_) => rnd.nextInt(256));
        sink.add(block);
        expected.addAll(block);
      }
      await sink.flush();
      await sink.close();

      final LocalRef rootRef = LocalRef.root(tmp.path);
      final FileRef fileRef = await rootRef.child(ItemKey.parse('big.bin'));
      const int chunk = 1024 * 1024 + 7;
      final int size = await fileRef.length();
      expect(size, total);

      final List<int> streamed = <int>[];
      int offset = 0;
      while (offset < size) {
        final int end = offset + chunk > size ? size : offset + chunk;
        await for (final List<int> part
            in fileRef.openRead(start: offset, endExclusive: end)) {
          streamed.addAll(part);
        }
        offset = end;
      }
      expect(streamed.length, total);
      expect(
        crypto.sha256.convert(streamed).toString(),
        crypto.sha256.convert(expected).toString(),
      );
    });
  });
}

Future<List<int>> _drain(Stream<List<int>> stream) async {
  final List<int> out = <int>[];
  await for (final List<int> part in stream) {
    out.addAll(part);
  }
  return out;
}

