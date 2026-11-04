// SPDX-License-Identifier: GPL-3.0-only

/// 身份派生、Ed25519 签名与域分隔的一致性用例。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/errors.dart';
import 'package:lan_simple_file/core/contracts/types.dart';
import 'package:lan_simple_file/core/identity/device_identity_impl.dart';
import 'package:lan_simple_file/core/identity/ed25519_signer.dart';

import 'test_support.dart';

void main() {
  group('deriveEd25519PublicKeyFromSeed', () {
    test('RFC 8032 TEST 1 公钥逐字节一致', () {
      expect(
        bytesToHex(deriveEd25519PublicKeyFromSeed(rfc8032Test1Seed)),
        bytesToHex(rfc8032Test1PublicKey),
      );
    });

    test('RFC 8032 TEST 2 公钥逐字节一致', () {
      expect(
        bytesToHex(deriveEd25519PublicKeyFromSeed(rfc8032Test2Seed)),
        bytesToHex(rfc8032Test2PublicKey),
      );
    });

    test('种子长度非法抛 ArgumentError，不静默截断', () {
      expect(
        () => deriveEd25519PublicKeyFromSeed(Uint8List(31)),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('derivePeerId', () {
    test('同一公钥派生稳定，且结果被 PeerId.parse 接受', () {
      final PeerId first = derivePeerId(rfc8032Test2PublicKey);
      final PeerId second =
          derivePeerId(Uint8List.fromList(rfc8032Test2PublicKey));
      expect(first, equals(second));
      expect(PeerId.parse(first.value), equals(first));
      expect(first.value.length, 15);
      expect(RegExp(r'^p_[a-z0-9]{13}$').hasMatch(first.value), isTrue);
    });

    test('peerId 只取 sha256(pubkey) 的 base32 前 13 位', () {
      // 独立复算：sha256 走 package:crypto，base32 手写展开，
      // 不调用被测的私有函数，避免「用实现验证实现」。
      final List<int> digest = sha256Of(rfc8032Test2PublicKey);
      const String alphabet = 'abcdefghijklmnopqrstuvwxyz234567';
      final StringBuffer expected = StringBuffer('p_');
      var accumulator = 0;
      var bits = 0;
      for (final int byte in digest) {
        accumulator = (accumulator << 8) | byte;
        bits += 8;
        while (bits >= 5 && expected.length < 15) {
          bits -= 5;
          expected.write(alphabet[(accumulator >> bits) & 0x1f]);
        }
        accumulator &= (1 << bits) - 1;
      }
      expect(derivePeerId(rfc8032Test2PublicKey).value, expected.toString());
    });

    test('不同公钥派生不同 peerId', () {
      expect(
        derivePeerId(rfc8032Test1PublicKey),
        isNot(equals(derivePeerId(rfc8032Test2PublicKey))),
      );
    });

    test('公钥长度非法抛 ArgumentError', () {
      expect(() => derivePeerId(Uint8List(31)), throwsA(isA<ArgumentError>()));
    });
  });

  group('DeviceIdentityImpl', () {
    test('fromSeed 的 peerId 恒等于 derivePeerId(publicKey)', () {
      final DeviceIdentityImpl identity = identityA();
      expect(identity.publicKey.length, 32);
      expect(identity.peerId, equals(derivePeerId(identity.publicKey)));
    });

    test('publicKey 返回副本，外部改动不影响身份', () {
      final DeviceIdentityImpl identity = identityA();
      final Uint8List copy = identity.publicKey;
      final int originalFirst = identity.publicKey[0];
      copy[0] ^= 0xff;
      expect(identity.publicKey[0], originalFirst);
      expect(identity.peerId, equals(derivePeerId(identity.publicKey)));
    });

    test('fromSeed 相同种子得到相同签名（确定性）', () async {
      final Uint8List payload = Uint8List.fromList(utf8.encode('same seed'));
      final Uint8List first = await identityA().sign(payload);
      final Uint8List second = await identityA().sign(payload);
      expect(bytesToHex(first), bytesToHex(second));
    });
  });

  group('Ed25519Signer', () {
    test('同一 payload 两次签名互相可验证', () async {
      final DeviceIdentityImpl identity = identityA();
      final Uint8List payload = Uint8List.fromList(utf8.encode('hello'));
      final Uint8List signature1 = await identity.sign(payload);
      final Uint8List signature2 = await identity.sign(payload);
      final Ed25519Signer verifier = Ed25519Signer();

      expect(signature1.length, 64);
      expect(signature2.length, 64);
      expect(
        await verifier.verify(payload, signature1, identity.publicKey),
        isTrue,
      );
      expect(
        await verifier.verify(payload, signature2, identity.publicKey),
        isTrue,
      );
      // 交叉验证：签名 1 能用签名 2 的「同一 payload」验过，
      // 因为 Ed25519 是确定性签名，两者本就应当逐字节相同。
      expect(bytesToHex(signature1), bytesToHex(signature2));
      expect(await identity.verifyOwn(payload, signature1), isTrue);
    });

    test('篡改 payload 一个字节必须验签失败', () async {
      final DeviceIdentityImpl identity = identityA();
      final Uint8List payload = Uint8List.fromList(utf8.encode('hello'));
      final Uint8List signature = await identity.sign(payload);

      final Uint8List tampered = Uint8List.fromList(payload);
      tampered[0] ^= 0x01;
      expect(
        await Ed25519Signer().verify(tampered, signature, identity.publicKey),
        isFalse,
      );
      expect(await identity.verifyOwn(tampered, signature), isFalse);
    });

    test('用错误公钥验签必须失败', () async {
      final DeviceIdentityImpl alice = identityA();
      final DeviceIdentityImpl mallory = identityB();
      final Uint8List payload = Uint8List.fromList(utf8.encode('who am i'));
      final Uint8List signature = await alice.sign(payload);

      expect(await alice.verifyOwn(payload, signature), isTrue);
      expect(
        await Ed25519Signer().verify(payload, signature, mallory.publicKey),
        isFalse,
      );
    });

    test('签名或公钥长度不对时返回 false，不抛异常', () async {
      final DeviceIdentityImpl identity = identityA();
      final Uint8List payload = Uint8List.fromList(<int>[1, 2, 3]);
      final Uint8List signature = await identity.sign(payload);
      final Ed25519Signer verifier = Ed25519Signer();

      expect(
        await verifier.verify(
          payload,
          signature.sublist(0, 63),
          identity.publicKey,
        ),
        isFalse,
      );
      expect(
        await verifier.verify(
          payload,
          signature,
          identity.publicKey.sublist(0, 31),
        ),
        isFalse,
      );
    });

    test('域分隔生效：信封式前缀参与签名，调用方重复拼接必然失配', () async {
      final DeviceIdentityImpl identity = identityA();
      final Uint8List payload = Uint8List.fromList(utf8.encode('domain'));
      final Uint8List signature = await identity.sign(payload);

      expect(
        bytesToHex(domainSeparatedPayload(payload).sublist(0, 7)),
        bytesToHex(utf8.encode(kSignatureDomainPrefix)),
      );
      expect(kSignatureDomainPrefix, 'lsf/v2/');
      // 调用方若自己再拼一次前缀，验签就是「前缀+前缀+payload」，必须失败。
      expect(
        await Ed25519Signer().verify(
          domainSeparatedPayload(payload),
          signature,
          identity.publicKey,
        ),
        isFalse,
      );
    });

    test('RFC 8032 TEST 2 签名在「raw 明文」下不通过（正是域分隔存在的意义）', () async {
      // TEST 2 的签名是对单字节 0x72 直接签的。本工程的 verify 会先加
      // lsf/v2/ 前缀，所以它必须验不过——这是一条防止「有人去掉域分隔」的
      // 回归用例。
      expect(
        await Ed25519Signer().verify(
          rfc8032Test2Message,
          rfc8032Test2Signature,
          rfc8032Test2PublicKey,
        ),
        isFalse,
      );
    });
  });

  group('LanFileException 载体', () {
    test('身份层错误使用可判定错误码，不抛裸 Exception', () {
      const LanFileException error = LanFileException(
        LanFileErrorCode.io,
        '身份文件损坏',
      );
      expect(error.code, LanFileErrorCode.io);
      expect(error.resolvedHttpStatus, 500);
      expect(error, isA<Exception>());
    });
  });
}
