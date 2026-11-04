// SPDX-License-Identifier: GPL-3.0-only

/// 跨端一致性金标准（golden vector）。
///
/// 网页端（WebCrypto / 原生 JS）要能独立算出同样的 peerId 与同样的 token，
/// 因此这些输入输出必须被钉死。任何一条断言失败都意味着**线上格式变了**，
/// 会影响所有已经发出去的链接——改实现前先想清楚是否要升协议版本。
///
/// 生成方式（可用任意独立实现复算）：
///   peerId   = "p_" + base32lower(sha256(pubkey))[0..13]
///   token    = base64url(canonical_json) + "." + base64url(ed25519(lsf/v2/ + canonical_json))
///   canonical_json 的键序：issuer, sid, sub, perm, nbf, exp, jti
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/types.dart';
import 'package:lan_simple_file/core/identity/capability_codec_impl.dart';
import 'package:lan_simple_file/core/identity/device_identity_impl.dart';
import 'package:lan_simple_file/core/identity/ed25519_signer.dart';

import 'test_support.dart';

void main() {
  group('peerId 金标准', () {
    test('RFC 8032 TEST 1 公钥 → p_eh7ddx5bksrgc', () {
      final PeerId peerId = derivePeerId(rfc8032Test1PublicKey);
      expect(peerId.value, 'p_eh7ddx5bksrgc');
      expect(PeerId.parse(peerId.value), peerId);
      // 同时与独立复算（不调用被测 base32）交叉验证，防止金标准值本身被改坏。
      expect(peerId.value, 'p_${expectedPeerIdSuffix(rfc8032Test1PublicKey)}');
    });

    test('RFC 8032 TEST 2 公钥 → p_hh3rhufgiqst6', () {
      final PeerId peerId = derivePeerId(rfc8032Test2PublicKey);
      expect(peerId.value, 'p_hh3rhufgiqst6');
      expect(peerId.value, 'p_${expectedPeerIdSuffix(rfc8032Test2PublicKey)}');
    });

    test('peerId 在多次调用间完全稳定（跨进程一致的前提）', () {
      final String first = derivePeerId(fixedSeedAPublicKey()).value;
      for (var i = 0; i < 5; i++) {
        expect(derivePeerId(fixedSeedAPublicKey()).value, first);
      }
    });
  });

  group('token 金标准', () {
    test('固定 grant + 固定种子 → 固定 token 字符串（Ed25519 确定性）', () async {
      final CapabilityCodecImpl codec = codecAt(fixedNow);
      final String token = await codec.issue(grantAt(fixedNow));

      // 金标准：网页端用同一 payload + 同一私钥签出的 token 必须与下面
      // 这个字符串逐字节相同。改动任何编码细节（键序、padding、前缀）都会
      // 让这条断言失败——那是线上格式变更，不是可以顺手改的测试。
      expect(token, fixedTokenGolden);
      // 同一 token 第二次签发必须逐字节相同。
      expect(await codec.issue(grantAt(fixedNow)), token);

      // 结构可被独立复算：payload 段解码后应是规范化 JSON。
      final String payloadPart = token.split('.').first;
      final String padded = payloadPart +
          '=' * ((4 - payloadPart.length % 4) % 4);
      final String json = utf8.decode(base64Url.decode(padded));
      expect(
        json,
        '{"issuer":"${identityA().peerId.value}","sid":"share-0001",'
        '"sub":"*","perm":["read"],'
        '"nbf":${fixedNow.millisecondsSinceEpoch},'
        '"exp":${fixedNow.add(const Duration(hours: 1)).millisecondsSinceEpoch},'
        '"jti":"jti-0001"}',
      );
    });

    test('签名段确实是 lsf/v2/ 前缀下的签名，可被独立验证', () async {
      final DeviceIdentityImpl issuer = identityA();
      final String token = await codecAt(fixedNow).issue(grantAt(fixedNow));
      final List<String> parts = token.split('.');
      final Uint8List payload = decodeBase64UrlTest(parts[0]);
      final Uint8List signature = decodeBase64UrlTest(parts[1]);

      expect(signature.length, 64);
      // 直接对 payload 验签：应当通过（Ed25519Signer 内部会补域前缀）。
      expect(
        await Ed25519Signer().verify(payload, signature, issuer.publicKey),
        isTrue,
      );
      // 对「已经带前缀的 payload」再验一次必须失败，佐证前缀只加一次。
      expect(
        await Ed25519Signer().verify(
          domainSeparatedPayload(payload),
          signature,
          issuer.publicKey,
        ),
        isFalse,
      );
    });

    test('token 长度只由 payload 长度与固定 64 字节签名决定', () async {
      final CapabilityCodecImpl codec = codecAt(fixedNow);
      final String token = await codec.issue(grantAt(fixedNow));
      final List<String> parts = token.split('.');
      expect(parts[1].length, 86, reason: '64 字节的 base64url 无填充长度恒为 86');
      expect(
        parts[0].length,
        base64Url.encode(decodeBase64UrlTest(parts[0])).replaceAll('=', '').length,
      );
    });
  });
}

/// 独立复算 peerId 后缀（不调用被测的私有 base32）。
String expectedPeerIdSuffix(Uint8List publicKey) {
  final List<int> digest = sha256Of(publicKey);
  const String alphabet = 'abcdefghijklmnopqrstuvwxyz234567';
  final StringBuffer out = StringBuffer();
  var accumulator = 0;
  var bits = 0;
  for (final int byte in digest) {
    accumulator = (accumulator << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out.write(alphabet[(accumulator >> bits) & 0x1f]);
      if (out.length == kPeerIdDigestLength) {
        return out.toString();
      }
    }
    accumulator &= (1 << bits) - 1;
  }
  return out.toString();
}

/// 固定种子 A 的公钥。
Uint8List fixedSeedAPublicKey() {
  final Uint8List key = Uint8List.fromList(
    deriveEd25519PublicKeyFromSeed(fixedSeedA),
  );
  return key;
}

/// 测试内复用的宽松 base64url 解码。
Uint8List decodeBase64UrlTest(String text) {
  final String padded = text + '=' * ((4 - text.length % 4) % 4);
  return Uint8List.fromList(base64Url.decode(padded));
}

/// 金标准 token：fixedSeedA + fixedNow + grantAt(fixedNow) 的签发结果。
///
/// payload 段解码后应为
/// `{"issuer":"p_kzdvvj2umnduy","sid":"share-0001","sub":"*","perm":["read"],...}`；
/// 由 Ed25519 确定性签名保证，可在任何独立实现（网页端 WebCrypto）复算。
const String fixedTokenGolden =
    'eyJpc3N1ZXIiOiJwX2t6ZHZ2ajJ1bW5kdXkiLCJzaWQiOiJzaGFyZS0wMDAxIiwic3ViIjoiKiIsInBlcm0iOlsicmVhZCJdLCJuYmYiOjE3NjcyMjU2MDAwMDAsImV4cCI6MTc2NzIyOTIwMDAwMCwianRpIjoianRpLTAwMDEifQ.lvWEM2j9FZ63I_ZM7dqkPh2gf2svF8d5wA0iUg0LmQTEYm7xUXzqw-dEOTeYtP-7JV_qKxBUMRkQYzqtk-36CQ';
