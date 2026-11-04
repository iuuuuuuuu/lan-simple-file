// SPDX-License-Identifier: GPL-3.0-only

/// 能力凭证（capability token）的签发与校验。
///
/// 形态（见 `.agents/notes/implemented/architecture/
/// 2026-11-04-host-independent-capability-addressing.md`）：
///
/// ```
/// token   = base64url(payload) + "." + base64url(sig)
/// payload = {"issuer","sid","sub","perm","nbf","exp","jti"}   // 键序固定，无填充
/// ```
///
/// - `issuer` 签发者 peerId；**写在 payload 内**，验证方从 token 自解，
///   不接受调用方从上下文注入（否则同一 token 在不同调用点会得出不同结论）
/// - `sid`  分享标识（[ShareId]）
/// - `sub`  授权对象；`*` 表示任何持链接者
/// - `perm` 权限集合，**排序后**写入，保证同一集合只有一种编码
/// - `nbf`  生效时刻（Unix 毫秒）
/// - `exp`  失效时刻（Unix 毫秒）
/// - `jti`  凭证唯一 id，吊销表的键
///
/// 凭证里**不出现任何网络地址**：链接与 IP 解耦。
library;

import 'dart:convert';
import 'dart:typed_data';

import '../contracts/errors.dart';
import '../contracts/identity.dart';
import '../contracts/types.dart';
import 'ed25519_signer.dart';
import 'token_revocation_store.dart';

/// 「任何主体都通过」的 sub 取值。
const String kSubjectWildcard = '*';

/// 规范化 JSON 的键名，顺序固定；跨端（Dart / WebCrypto）必须一致。
const List<String> kCapabilityPayloadKeys = <String>[
  'issuer',
  'sid',
  'sub',
  'perm',
  'nbf',
  'exp',
  'jti',
];

/// 把 [CapabilityGrant] 规范化成被签名的 JSON 字节。
///
/// 键序即 [kCapabilityPayloadKeys]；issuer 排在最前，保证「先知道是谁签的，
/// 再去取公钥」这条验证路径在编码层就是自然顺序。
Uint8List encodeCapabilityPayload(CapabilityGrant grant) {
  final List<String> permissions = grant.permissions.toList()..sort();
  final Map<String, Object?> payload = <String, Object?>{
    'issuer': grant.issuer.value,
    'sid': grant.shareId.value,
    'sub': grant.subject,
    'perm': permissions,
    'nbf': grant.notBefore.toUtc().millisecondsSinceEpoch,
    'exp': grant.expiresAt.toUtc().millisecondsSinceEpoch,
    'jti': grant.tokenId,
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(payload)));
}

/// 能力凭证编解码实现。
///
/// 一个实例同时具备签发与校验能力：[DeviceIdentity] 只用来签名本机签发的
/// 凭证；校验任何凭证时一律走 [PublicKeyLookup] 按 payload 里的 issuer
/// 取公钥，因此同一个实例既能签自己的、也能验别人的。
final class CapabilityCodecImpl implements CapabilityCodec {
  CapabilityCodecImpl({
    required DeviceIdentity issuer,
    required TokenRevocationStore revoked,
    required PublicKeyLookup keys,
    DateTime Function()? clock,
  })  : _signer = issuer,
        _revocationStore = revoked,
        _publicKeyLookup = keys,
        _clock = clock ?? DateTime.now,
        _verifier = Ed25519Signer();

  final DeviceIdentity _signer;
  final TokenRevocationStore _revocationStore;
  final PublicKeyLookup _publicKeyLookup;
  final DateTime Function() _clock;
  final Ed25519Signer _verifier;

  /// 本机签发身份。
  DeviceIdentity get issuer => _signer;

  /// 公钥查找表。公开只读访问器，端到端验收要能拿到注入点。
  PublicKeyLookup get keys => _publicKeyLookup;

  @override
  Future<String> issue(CapabilityGrant grant) async {
    if (grant.tokenId.isEmpty) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        'tokenId 不能为空',
      );
    }
    if (!grant.expiresAt.isAfter(grant.notBefore)) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        'expiresAt 必须晚于 notBefore',
      );
    }
    if (grant.issuer != _signer.peerId) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        'grant.issuer 与本机身份不一致，不能代签',
      );
    }

    final Uint8List payload = encodeCapabilityPayload(grant);
    final Uint8List signature = await _signer.sign(payload);
    return '${_encodeBase64Url(payload)}.${_encodeBase64Url(signature)}';
  }

  @override
  Future<CapabilityClaims> verify(String token) async {
    final _DecodedToken decoded = _decodeToken(token);

    // 1) 先自 token 解出 issuer —— 这是「任何节点都能离线验证」的入口。
    final String issuerText = _extractIssuer(decoded.payload);
    final PeerId? issuer = PeerId.tryParse(issuerText);
    if (issuer == null) {
      throw const LanFileException(
        LanFileErrorCode.accessDenied,
        '凭证中的 issuer 不是合法 peerId',
      );
    }

    // 2) 按 issuer 取公钥；查不到就是「未知签发者」，与签名无效区分开。
    final Uint8List? publicKey = await _publicKeyLookup.findPublicKey(issuer);
    if (publicKey == null) {
      throw LanFileException(
        LanFileErrorCode.accessDenied,
        '未知签发者：本机没有 ${issuer.value} 的公钥',
      );
    }

    // 3) 用该公钥验签。
    final bool signatureValid = await _verifier.verify(
      decoded.payload,
      decoded.signature,
      publicKey,
    );
    if (!signatureValid) {
      throw const LanFileException(
        LanFileErrorCode.accessDenied,
        '凭证签名无效',
      );
    }

    // 4) 解完整声明（issuer 必须与第 1 步解出的一致）。
    final CapabilityClaims claims = _parseClaims(decoded.payload, issuer);

    // 5) 时间窗。
    _checkTimeWindow(claims);

    // 6) 吊销表。
    if (await _revocationStore.isRevoked(claims.tokenId)) {
      throw const LanFileException(
        LanFileErrorCode.revoked,
        '凭证已被吊销',
      );
    }
    return claims;
  }

  @override
  Future<CapabilityClaims> verifyForSubject(
    String token,
    String subject,
  ) async {
    final CapabilityClaims claims = await verify(token);
    if (claims.subject == kSubjectWildcard) {
      return claims;
    }
    if (claims.subject != subject) {
      throw const LanFileException(
        LanFileErrorCode.accessDenied,
        '凭证不适用于该主体',
      );
    }
    return claims;
  }

  /// 只解 issuer 一个字段；此时其余字段尚未被信任。
  String _extractIssuer(Uint8List payload) {
    final Object? decoded = _decodePayloadJson(payload);
    if (decoded is! Map<String, Object?>) {
      throw const LanFileException(
        LanFileErrorCode.accessDenied,
        '凭证负载结构非法',
      );
    }
    final Object? issuer = decoded['issuer'];
    if (issuer is! String || issuer.isEmpty) {
      throw const LanFileException(
        LanFileErrorCode.accessDenied,
        '凭证负载缺少 issuer 字段',
      );
    }
    return issuer;
  }

  Object? _decodePayloadJson(Uint8List payload) {
    try {
      return jsonDecode(utf8.decode(payload));
    } on FormatException catch (error) {
      throw LanFileException(
        LanFileErrorCode.accessDenied,
        '凭证负载不是合法 JSON',
        cause: error,
      );
    }
  }

  void _checkTimeWindow(CapabilityClaims claims) {
    final DateTime now = _clock().toUtc();
    if (now.isBefore(claims.notBefore)) {
      throw const LanFileException(
        LanFileErrorCode.accessDenied,
        '凭证尚未生效',
      );
    }
    if (!now.isBefore(claims.expiresAt)) {
      throw const LanFileException(
        LanFileErrorCode.expired,
        '凭证已过期',
      );
    }
  }

  CapabilityClaims _parseClaims(Uint8List payload, PeerId issuer) {
    final Object? decoded = _decodePayloadJson(payload);
    if (decoded is! Map<String, Object?>) {
      throw const LanFileException(
        LanFileErrorCode.accessDenied,
        '凭证负载结构非法',
      );
    }
    final Object? issuerText = decoded['issuer'];
    final Object? sid = decoded['sid'];
    final Object? sub = decoded['sub'];
    final Object? perm = decoded['perm'];
    final Object? nbf = decoded['nbf'];
    final Object? exp = decoded['exp'];
    final Object? jti = decoded['jti'];
    if (issuerText is! String ||
        sid is! String ||
        sub is! String ||
        perm is! List<Object?> ||
        nbf is! int ||
        exp is! int ||
        jti is! String) {
      throw const LanFileException(
        LanFileErrorCode.accessDenied,
        '凭证负载字段缺失或类型不符',
      );
    }
    if (issuerText != issuer.value) {
      throw const LanFileException(
        LanFileErrorCode.accessDenied,
        '凭证负载中的 issuer 前后不一致',
      );
    }
    final ShareId? shareId = ShareId.tryParse(sid);
    if (shareId == null) {
      throw const LanFileException(
        LanFileErrorCode.accessDenied,
        '凭证中的 shareId 非法',
      );
    }
    final Set<String> permissions = <String>{};
    for (final Object? entry in perm) {
      if (entry is! String) {
        throw const LanFileException(
          LanFileErrorCode.accessDenied,
          '凭证中的权限项不是字符串',
        );
      }
      permissions.add(entry);
    }
    return CapabilityClaims(
      shareId: shareId,
      issuer: issuer,
      subject: sub,
      permissions: permissions,
      notBefore: DateTime.fromMillisecondsSinceEpoch(nbf, isUtc: true),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(exp, isUtc: true),
      tokenId: jti,
    );
  }

  _DecodedToken _decodeToken(String token) {
    final int dot = token.indexOf('.');
    if (dot <= 0 || dot != token.lastIndexOf('.')) {
      throw const LanFileException(
        LanFileErrorCode.accessDenied,
        '凭证格式非法：必须恰好是 payload.signature 两段',
      );
    }
    final String payloadPart = token.substring(0, dot);
    final String signaturePart = token.substring(dot + 1);
    if (payloadPart.isEmpty || signaturePart.isEmpty) {
      throw const LanFileException(
        LanFileErrorCode.accessDenied,
        '凭证格式非法：段为空',
      );
    }
    final Uint8List payload;
    final Uint8List signature;
    try {
      payload = _decodeBase64Url(payloadPart);
      signature = _decodeBase64Url(signaturePart);
    } on FormatException catch (error) {
      throw LanFileException(
        LanFileErrorCode.accessDenied,
        '凭证不是合法 base64url',
        cause: error,
      );
    }
    if (signature.length != kEd25519SignatureBytes) {
      throw const LanFileException(
        LanFileErrorCode.accessDenied,
        '凭证签名长度非法',
      );
    }
    return _DecodedToken(payload, signature);
  }
}

final class _DecodedToken {
  const _DecodedToken(this.payload, this.signature);

  final Uint8List payload;
  final Uint8List signature;
}

/// base64url，**不带** `=` 填充。
String _encodeBase64Url(Uint8List bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// 宽松解码：接受带或不带填充的 base64url。
Uint8List _decodeBase64Url(String text) {
  final int remainder = text.length % 4;
  final String padded = remainder == 0 ? text : text + '=' * (4 - remainder);
  return Uint8List.fromList(base64Url.decode(padded));
}
