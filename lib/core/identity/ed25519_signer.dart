// SPDX-License-Identifier: GPL-3.0-only

/// Ed25519 签名/验签与 peerId 派生。
///
/// 两条跨端一致性约定（Dart 端、网页端 WebCrypto 端必须逐字节一致）：
///
/// 1. **域分隔**：任何业务明文在被签名前，都必须先拼上固定前缀
///    `lsf/v2/`。这样「公告签名」与「凭证签名」不会互相冒用。
/// 2. **peerId 派生**：`peerId = "p_" + base32lower(sha256(publicKey))[0..13]`，
///    base32 采用 RFC 4648 小写字母表 `abcdefghijklmnopqrstuvwxyz234567`，
///    不补 `=`；取前 13 个字符。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import '../contracts/identity.dart';
import '../contracts/types.dart';

/// 所有签名前固定拼接的域分隔前缀。
const String kSignatureDomainPrefix = 'lsf/v2/';

/// peerId 中取自 base32 摘要的字符数（`p_` 之后的部分）。
const int kPeerIdDigestLength = 13;

/// Ed25519 公钥字节数。
const int kEd25519PublicKeyBytes = 32;

/// Ed25519 签名字节数。
const int kEd25519SignatureBytes = 64;

const String _base32Alphabet = 'abcdefghijklmnopqrstuvwxyz234567';

/// 把业务明文包装成实际被签名的字节：`lsf/v2/` + payload。
///
/// 调用方只传业务明文，前缀由本模块负责，避免各处自行拼前缀拼错。
Uint8List domainSeparatedPayload(Uint8List payload) {
  final List<int> header = utf8.encode(kSignatureDomainPrefix);
  final Uint8List out = Uint8List(header.length + payload.length);
  out.setAll(0, header);
  out.setAll(header.length, payload);
  return out;
}

/// 由公钥派生稳定 peerId。
///
/// 规则：`sha256(pubkey)` → base32（小写、无填充）→ 取前
/// [kPeerIdDigestLength] 个字符 → 加前缀 `p_`。
///
/// 同一公钥在任何节点、任何平台必须得到同一结果；公钥长度非法时抛
/// [ArgumentError]（这是编程错误，不是网络输入）。
PeerId derivePeerId(Uint8List publicKey) {
  if (publicKey.length != kEd25519PublicKeyBytes) {
    throw ArgumentError.value(
      publicKey.length,
      'publicKey',
      'Ed25519 公钥必须是 $kEd25519PublicKeyBytes 字节',
    );
  }
  final List<int> digest = crypto.sha256.convert(publicKey).bytes;
  final String encoded = _base32Lower(digest);
  return PeerId.parse('p_${encoded.substring(0, kPeerIdDigestLength)}');
}

/// 由 32 字节种子同步派生 32 字节公钥。
///
/// RFC 8032 §5.1.5 的标准流程：sha512(seed) → 取前 32 字节 → clamp →
/// 标量乘基点 → 压缩。
///
/// 之所以同步实现而不走 `package:cryptography`：`DeviceIdentityImpl.fromSeed`
/// 是同步 API，而 cryptography 的 `newKeyPairFromSeed` 只有异步版本，
/// 而 [PeerId] 与 `publicKey` 都是同步取值（见 contracts/identity.dart）。
Uint8List deriveEd25519PublicKeyFromSeed(Uint8List seed) {
  if (seed.length != 32) {
    throw ArgumentError.value(seed.length, 'seed', 'Ed25519 种子必须是 32 字节');
  }
  final List<int> hash = crypto.sha512.convert(seed).bytes;
  final Uint8List clamped = Uint8List.fromList(hash.sublist(0, 32));
  clamped[0] &= 0xf8;
  clamped[31] &= 0x7f;
  clamped[31] |= 0x40;
  return _encodePoint(_scalarMultiplyBase(clamped));
}

/// 用任意公钥验签的签名校验器。
///
/// 失败不是异常：签名长度不对、公钥长度不对、点非法，一律返回 `false`，
/// 由调用方翻译成 `LanFileException`。
final class Ed25519Signer implements SignatureVerifier {
  /// 构造；[algorithm] 仅用于测试替换。
  Ed25519Signer({Ed25519? algorithm}) : _algorithm = algorithm ?? Ed25519();

  final Ed25519 _algorithm;

  @override
  Future<bool> verify(
    Uint8List payload,
    Uint8List signature,
    Uint8List publicKey,
  ) async {
    if (publicKey.length != kEd25519PublicKeyBytes) {
      return false;
    }
    if (signature.length != kEd25519SignatureBytes) {
      return false;
    }
    final Uint8List message = domainSeparatedPayload(payload);
    return _algorithm.verify(
      message,
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 曲线运算：只用于「由种子同步算公钥」这一条路径，签名与验签都走
// package:cryptography。使用扩展扭曲爱德华兹坐标，避免中间求逆。
// ---------------------------------------------------------------------------

final BigInt _fieldP = (BigInt.one << 255) - BigInt.from(19);

/// 曲线常数 d = -121665 / 121666 mod p。
final BigInt _curveD =
    (BigInt.from(-121665) * BigInt.from(121666).modInverse(_fieldP)) % _fieldP;

final BigInt _twoD = (_curveD * BigInt.two) % _fieldP;

/// RFC 8032 基点 B 的仿射坐标。
final BigInt _baseX = BigInt.parse(
  '15112221349535400772501151409588531511454012693041857206046113283949847762202',
);
final BigInt _baseY = BigInt.parse(
  '46316835694926478169428394003475163141307993866256225615783033603165251855960',
);

/// 扩展坐标点 (X : Y : Z : T)，满足 x = X/Z、y = Y/Z、T = XY/Z。
final class _ExtPoint {
  const _ExtPoint(this.x, this.y, this.z, this.t);

  final BigInt x;
  final BigInt y;
  final BigInt z;
  final BigInt t;
}

final _ExtPoint _identity = _ExtPoint(
  BigInt.zero,
  BigInt.one,
  BigInt.one,
  BigInt.zero,
);

final _ExtPoint _basePoint = _ExtPoint(_baseX, _baseY, BigInt.one, (_baseX * _baseY) % _fieldP);

BigInt _mod(BigInt value) {
  final BigInt reduced = value % _fieldP;
  return reduced.isNegative ? reduced + _fieldP : reduced;
}

/// a = -1 的完整加法公式（ref10 同款）。
_ExtPoint _addPoints(_ExtPoint p1, _ExtPoint p2) {
  final BigInt a = _mod((p1.y - p1.x) * (p2.y - p2.x));
  final BigInt b = _mod((p1.y + p1.x) * (p2.y + p2.x));
  final BigInt c = _mod(p1.t * _twoD * p2.t);
  final BigInt d = _mod(p1.z * BigInt.two * p2.z);
  final BigInt e = _mod(b - a);
  final BigInt f = _mod(d - c);
  final BigInt g = _mod(d + c);
  final BigInt h = _mod(b + a);
  return _ExtPoint(_mod(e * f), _mod(g * h), _mod(f * g), _mod(e * h));
}

/// 标量乘基点；[scalar] 为 32 字节小端标量。
_ExtPoint _scalarMultiplyBase(Uint8List scalar) {
  _ExtPoint result = _identity;
  _ExtPoint addend = _basePoint;
  for (var i = 0; i < 256; i++) {
    if (((scalar[i >> 3] >> (i & 7)) & 0x01) == 1) {
      result = _addPoints(result, addend);
    }
    addend = _addPoints(addend, addend);
  }
  return result;
}

/// 压缩点：小端 32 字节 y，最高位放 x 的最低位。
Uint8List _encodePoint(_ExtPoint point) {
  final BigInt zInverse = point.z.modInverse(_fieldP);
  final BigInt x = _mod(point.x * zInverse);
  final BigInt y = _mod(point.y * zInverse);
  final Uint8List out = Uint8List(32);
  BigInt value = y;
  final BigInt mask = BigInt.from(0xff);
  for (var i = 0; i < 32; i++) {
    out[i] = (value & mask).toInt();
    value = value >> 8;
  }
  if (x.isOdd) {
    out[31] |= 0x80;
  }
  return out;
}

/// RFC 4648 base32，小写字母表，不补 `=`。
String _base32Lower(List<int> bytes) {
  final StringBuffer buffer = StringBuffer();
  var accumulator = 0;
  var bits = 0;
  for (final int byte in bytes) {
    accumulator = (accumulator << 8) | (byte & 0xff);
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      buffer.write(_base32Alphabet[(accumulator >> bits) & 0x1f]);
    }
    accumulator &= (1 << bits) - 1;
  }
  if (bits > 0) {
    buffer.write(_base32Alphabet[(accumulator << (5 - bits)) & 0x1f]);
  }
  return buffer.toString();
}
