// SPDX-License-Identifier: GPL-3.0-only

/// 身份与凭证契约：实现方不得改变签名语义。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'types.dart';

/// 设备身份密钥对的操作面。
///
/// 实现必须保证：同一份明文在任意节点上验签结果一致，
/// 且 [peerId] 恒等于由公钥派生出的稳定标识。
abstract interface class DeviceIdentity {
  /// 由公钥派生的稳定标识。
  PeerId get peerId;

  /// 裸公钥字节（Ed25519，32 字节）。
  Uint8List get publicKey;

  /// 对 payload 直接签名（实现内部负责域分隔，调用方无需自行拼前缀）。
  Future<Uint8List> sign(Uint8List payload);

  /// 用本机私钥解开 payload 的签名并自校验。
  Future<bool> verifyOwn(Uint8List payload, Uint8List signature);
}

/// 使用任意公钥验签的静态能力，供对端校验公告与凭证。
abstract interface class SignatureVerifier {
  /// 用 [publicKey] 校验 [payload] 上由 [signature] 表示的签名。
  Future<bool> verify(
    Uint8List payload,
    Uint8List signature,
    Uint8List publicKey,
  );
}

/// 能力凭证的编解码。
///
/// 凭证只承载「谁授权、能做什么、何时失效」，**不得**承载任何网络地址。
///
/// **issuer 必须写在 payload 内**：验证方手里只有 token，必须能从 token 自身
/// 解出「这是谁的凭证」，再去 peers 表取对应公钥验签。把 issuer 交给调用方
/// 从上下文注入会让同一 token 在不同调用点得到不同结论，且无法做「任何节点
/// 都能验证」的离线校验——那正是本设计要的确定性。
abstract interface class CapabilityCodec {
  /// 签发凭证，返回可直接放进链接的字符串。
  Future<String> issue(CapabilityGrant grant);

  /// 校验凭证是否仍然有效（验签、时间窗、吊销状态）。
  ///
  /// 实现必须自 token 内解出 issuer，并用该 issuer 的公钥验签。
  /// 公钥查找通过 [PublicKeyLookup] 完成，不得依赖调用方另传。
  Future<CapabilityClaims> verify(String token);

  /// 在线校验，额外比对 [CapabilityGrant.subject]。
  Future<CapabilityClaims> verifyForSubject(String token, String subject);
}

/// 由 peerId 查公钥的能力；凭证验证方必须持有它才能自证 issuer。
abstract interface class PublicKeyLookup {
  /// 查不到（例如对方从未在本机出现）返回 null。
  Future<Uint8List?> findPublicKey(PeerId peerId);
}

/// 消息签名的规范化：**签什么**由这里定死，实现方不得自造。
///
/// 与凭证签名共用域分隔前缀（`lsf/v2/`），但用途不同，故再叠加一层
/// 用途标签，防止把消息签名当作凭证签名重放。
abstract final class MessageSignature {
  /// 用途标签，与凭证的 payload 区分开。
  static const String purpose = 'msg';

  /// 参与签名的规范化字节。
  ///
  /// **只签不可变部分**：id、threadId、发送者、HLC、时间、kind、正文、附件。
  /// 撤回/删除/编辑是后续事件，绝不进签名——否则一撤回签名就失效，
  /// 历史消息会集体变成「签名无效」，那是设计错误。
  static Uint8List canonicalBytes({
    required String messageId,
    required String threadId,
    required String senderPeerId,
    required String hlc,
    required int tsMillis,
    required String kind,
    required String body,
    required String attachJson,
  }) {
    final String joined = <String>[
      purpose,
      messageId,
      threadId,
      senderPeerId,
      hlc,
      tsMillis.toString(),
      kind,
      body,
      attachJson,
    ].join(separator);

    // **必须是 utf8，不能用 codeUnits**。
    //
    // codeUnits 给出 UTF-16 码元（0..0xFFFF），塞进 Uint8List 时被静默截断成低 8 位：
    // 'A'(0x41) 与 'Ł'(0x141) 低字节相同 → 规范化字节完全一致 → 签名碰撞，
    // 攻击者可把 body='A' 换成 'Ł' 而验签照样通过；中文与 emoji 更会被压成单字节。
    // utf8 与 AnnouncePacket.signableBytes 及凭证 payload 口径一致，中文/emoji 正确。
    return Uint8List.fromList(utf8.encode(joined));
  }

  /// 字段分隔符：NUL。
  ///
  /// 选它是因为几乎不可能出现在正文或文件名里，比空格安全；
  /// 配合 utf8 时各字段的可变长编码不会跨字段产生歧义。
  static const String separator = '\u0000';
}

/// 签发时给定的授权事实。
final class CapabilityGrant {
  const CapabilityGrant({
    required this.shareId,
    required this.issuer,
    required this.subject,
    required this.permissions,
    required this.notBefore,
    required this.expiresAt,
    required this.tokenId,
  });

  final ShareId shareId;

  /// 签发者（分享所有者）的 peerId。
  final PeerId issuer;

  /// 授权对象；星号表示任何持有链接的人。
  final String subject;

  final Set<String> permissions;
  final DateTime notBefore;
  final DateTime expiresAt;
  final String tokenId;
}

/// 校验后得到的声明。
final class CapabilityClaims {
  const CapabilityClaims({
    required this.shareId,
    required this.issuer,
    required this.subject,
    required this.permissions,
    required this.notBefore,
    required this.expiresAt,
    required this.tokenId,
  });

  final ShareId shareId;
  final PeerId issuer;
  final String subject;
  final Set<String> permissions;
  final DateTime notBefore;
  final DateTime expiresAt;
  final String tokenId;
}
