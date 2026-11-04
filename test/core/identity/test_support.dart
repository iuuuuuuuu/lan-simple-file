// SPDX-License-Identifier: GPL-3.0-only

/// 身份模块测试共用的确定性夹具与字节工具。
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:lan_simple_file/core/contracts/identity.dart';
import 'package:lan_simple_file/core/contracts/types.dart';
import 'package:lan_simple_file/core/identity/capability_codec_impl.dart';
import 'package:lan_simple_file/core/identity/device_identity_impl.dart';
import 'package:lan_simple_file/core/identity/token_revocation_store.dart';

/// RFC 8032 §7.1 TEST 1 的种子。
final Uint8List rfc8032Test1Seed = hexToBytes(
  '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60',
);

/// RFC 8032 §7.1 TEST 1 的公钥。
final Uint8List rfc8032Test1PublicKey = hexToBytes(
  'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
);

/// RFC 8032 §7.1 TEST 2 的种子。
final Uint8List rfc8032Test2Seed = hexToBytes(
  '4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb',
);

/// RFC 8032 §7.1 TEST 2 的公钥。
final Uint8List rfc8032Test2PublicKey = hexToBytes(
  '3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c',
);

/// RFC 8032 §7.1 TEST 2 的明文（单字节 0x72）。
final Uint8List rfc8032Test2Message = hexToBytes('72');

/// RFC 8032 §7.1 TEST 2 的签名（对**未加**域前缀的明文）。
final Uint8List rfc8032Test2Signature = hexToBytes(
  '92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da'
  '085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00',
);

/// 固定种子 A：保证每次跑测试用的身份完全一样。
final Uint8List fixedSeedA = hexToBytes(
  '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f',
);

/// 固定种子 B：第三方身份，用于「用错公钥验签」的负向用例。
final Uint8List fixedSeedB = hexToBytes(
  '202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f',
);

/// 固定测试时钟：2026-01-01T00:00:00Z。
final DateTime fixedNow = DateTime.utc(2026, 1, 1);

/// 固定身份 A（分享所有者，签发方）。
DeviceIdentityImpl identityA() => DeviceIdentityImpl.fromSeed(fixedSeedA);

/// 固定身份 B（验证方；也用于制造「错误公钥」）。
DeviceIdentityImpl identityB() => DeviceIdentityImpl.fromSeed(fixedSeedB);

/// 内存版 [PublicKeyLookup]：整条「A 签 B 验」链路靠它把公钥递给验证方。
///
/// 刻意做成可写的公开类而不是私有 mock —— 端到端验收需要把它注入
/// [CapabilityCodecImpl]。
final class FakePublicKeyLookup implements PublicKeyLookup {
  FakePublicKeyLookup();

  final Map<String, Uint8List> _keys = <String, Uint8List>{};

  /// 登记某人的公钥；重复登记覆盖。
  void register(PeerId peerId, Uint8List publicKey) {
    _keys[peerId.value] = Uint8List.fromList(publicKey);
  }

  /// 注销某人的公钥，模拟「本机从未见过这个人」。
  void forget(PeerId peerId) => _keys.remove(peerId.value);

  /// 当前登记了几个人。
  int get size => _keys.length;

  @override
  Future<Uint8List?> findPublicKey(PeerId peerId) async {
    final Uint8List? stored = _keys[peerId.value];
    return stored == null ? null : Uint8List.fromList(stored);
  }
}

/// 构造一张只认识给定几个身份的查找表（Dart 无变长参数，用 List）。
FakePublicKeyLookup lookupWith(List<DeviceIdentity> identities) {
  final FakePublicKeyLookup lookup = FakePublicKeyLookup();
  for (final DeviceIdentity identity in identities) {
    lookup.register(identity.peerId, identity.publicKey);
  }
  return lookup;
}

/// 只认识 A 的查找表（最常见场景：验自己人签的链接）。
FakePublicKeyLookup lookupWithA() => lookupWith(<DeviceIdentity>[identityA()]);

/// 用固定时钟构造的 codec（默认由 A 签发，查找表只含 A）。
CapabilityCodecImpl codecAt(
  DateTime now, {
  DeviceIdentity? identity,
  TokenRevocationStore? store,
  PublicKeyLookup? keys,
}) {
  final DeviceIdentity signer = identity ?? identityA();
  return CapabilityCodecImpl(
    issuer: signer,
    revoked: store ?? TokenRevocationStore(),
    keys: keys ?? lookupWith(<DeviceIdentity>[signer]),
    clock: () => now,
  );
}

/// 一份合规的授权事实，时间窗以 [anchor] 为基准。
CapabilityGrant grantAt(
  DateTime anchor, {
  String shareId = 'share-0001',
  String subject = '*',
  Set<String> permissions = const <String>{'read'},
  String tokenId = 'jti-0001',
  Duration ttl = const Duration(hours: 1),
  PeerId? issuer,
}) {
  return CapabilityGrant(
    shareId: ShareId.parse(shareId),
    issuer: issuer ?? identityA().peerId,
    subject: subject,
    permissions: permissions,
    notBefore: anchor,
    expiresAt: anchor.add(ttl),
    tokenId: tokenId,
  );
}

/// 十六进制字符串转字节。
Uint8List hexToBytes(String text) {
  final String clean = text.replaceAll(RegExp(r'\s'), '');
  final Uint8List out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// sha256 摘要（独立复算 peerId 用，不借道被测实现）。
List<int> sha256Of(List<int> bytes) => crypto.sha256.convert(bytes).bytes;

/// 字节转小写十六进制字符串。
String bytesToHex(List<int> bytes) {
  final StringBuffer buffer = StringBuffer();
  for (final int byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
