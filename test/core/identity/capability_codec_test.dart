// SPDX-License-Identifier: GPL-3.0-only

/// 能力凭证的签发、自解 issuer、校验、时间窗、吊销语义用例。
///
/// 核心链路：**A 签 → B 验**。B 手里只有 token 与一张公钥表，
/// issuer 由 token 自解，不靠调用方注入。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/errors.dart';
import 'package:lan_simple_file/core/contracts/identity.dart';
import 'package:lan_simple_file/core/identity/capability_codec_impl.dart';
import 'package:lan_simple_file/core/identity/token_revocation_store.dart';

import 'test_support.dart';

/// 取出 token 的 payload 段并解成 JSON，用于断言「线上形态」。
Map<String, Object?> decodePayload(String token) {
  final String payloadPart = token.substring(0, token.indexOf('.'));
  final Object? decoded =
      jsonDecode(utf8.decode(decodeBase64UrlLoose(payloadPart)));
  return decoded! as Map<String, Object?>;
}

/// 把 payload JSON 重新编码成 token 的 payload 段（用于构造被篡改的 token）。
String encodePayload(Map<String, Object?> payload) =>
    base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');

/// 宽松 base64url 解码。
Uint8List decodeBase64UrlLoose(String text) {
  final int remainder = text.length % 4;
  final String padded = remainder == 0 ? text : text + '=' * (4 - remainder);
  return Uint8List.fromList(base64Url.decode(padded));
}

/// 断言某个动作抛出指定错误码，并可选校验文案关键词。
Future<void> expectCode(
  Future<Object?> Function() action,
  LanFileErrorCode expected, {
  String? reason,
  String? messageContains,
}) async {
  await expectLater(
    action(),
    throwsA(
      isA<LanFileException>()
          .having((LanFileException e) => e.code, 'code', expected)
          .having(
            (LanFileException e) => e.message,
            'message',
            messageContains == null ? anything : contains(messageContains),
          ),
    ),
    reason: reason,
  );
}

void main() {
  group('issue：payload 含 issuer', () {
    test('token = base64url(payload) + "." + base64url(sig)，无填充字符', () async {
      final CapabilityCodecImpl codec = codecAt(fixedNow);
      final String token = await codec.issue(grantAt(fixedNow));

      expect(token.contains('='), isFalse, reason: 'base64url 不得带填充');
      expect('.'.allMatches(token).length, 1);
      final List<String> parts = token.split('.');
      expect(parts.length, 2);
      // 64 字节签名的 base64url 无填充长度恒为 86。
      expect(parts[1].length, 86);
      expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(parts[0]), isTrue);
      expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(parts[1]), isTrue);
    });

    test('payload 键序固定为 issuer,sid,sub,perm,nbf,exp,jti', () async {
      final CapabilityCodecImpl codec = codecAt(fixedNow);
      final Map<String, Object?> payload =
          decodePayload(await codec.issue(grantAt(fixedNow)));

      expect(payload.keys.toList(), kCapabilityPayloadKeys);
      expect(kCapabilityPayloadKeys.first, 'issuer');
      expect(payload['issuer'], identityA().peerId.value);
      expect(payload['sid'], 'share-0001');
      expect(payload['sub'], '*');
      expect(payload['jti'], 'jti-0001');
      expect(payload['nbf'], fixedNow.millisecondsSinceEpoch);
    });

    test('issuer 字段就是签发者 peerId，不是别的值', () async {
      final CapabilityCodecImpl codecA = codecAt(fixedNow);
      final CapabilityCodecImpl codecB =
          codecAt(fixedNow, identity: identityB());
      expect(
        decodePayload(await codecA.issue(grantAt(fixedNow)))['issuer'],
        identityA().peerId.value,
      );
      expect(
        decodePayload(
          await codecB.issue(grantAt(fixedNow, issuer: identityB().peerId)),
        )['issuer'],
        identityB().peerId.value,
      );
    });

    test('perm 排序后写入，同一集合只有一种编码', () async {
      final CapabilityCodecImpl codec = codecAt(fixedNow);
      final String tokenA = await codec.issue(
        grantAt(fixedNow, permissions: <String>{'write', 'read', 'list'}),
      );
      final String tokenB = await codec.issue(
        grantAt(fixedNow, permissions: <String>{'list', 'read', 'write'}),
      );
      expect(decodePayload(tokenA)['perm'], <String>['list', 'read', 'write']);
      expect(tokenA, tokenB);
    });

    test('token 里不出现任何网络地址', () async {
      final CapabilityCodecImpl codec = codecAt(fixedNow);
      final String flat =
          decodePayload(await codec.issue(grantAt(fixedNow))).toString();
      expect(RegExp(r'[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+').hasMatch(flat), isFalse);
      expect(flat.contains('://'), isFalse);
      expect(flat.contains('host'), isFalse);
      expect(flat.contains('port'), isFalse);
    });

    test('tokenId 为空、时间窗倒挂、issuer 不符都抛 invalidArgument', () async {
      final CapabilityCodecImpl codec = codecAt(fixedNow);
      await expectCode(
        () => codec.issue(grantAt(fixedNow, tokenId: '')),
        LanFileErrorCode.invalidArgument,
      );
      await expectCode(
        () => codec.issue(grantAt(fixedNow, ttl: Duration.zero)),
        LanFileErrorCode.invalidArgument,
      );
      // A 的 codec 不能代签 issuer=B 的凭证。
      await expectCode(
        () => codec.issue(grantAt(fixedNow, issuer: identityB().peerId)),
        LanFileErrorCode.invalidArgument,
        messageContains: '不一致',
      );
    });
  });

  group('verify：自解 issuer + 公钥查找', () {
    test('A 签、B 验（B 的公钥表里有 A）', () async {
      final String token = await codecAt(fixedNow).issue(grantAt(fixedNow));
      final CapabilityCodecImpl verifier = CapabilityCodecImpl(
        issuer: identityB(),
        revoked: TokenRevocationStore(),
        keys: lookupWithA(),
        clock: () => fixedNow,
      );
      final CapabilityClaims claims = await verifier.verify(token);
      expect(claims.issuer, identityA().peerId);
      expect(claims.tokenId, 'jti-0001');
      expect(claims.shareId.value, 'share-0001');
      expect(claims.subject, '*');
      expect(claims.permissions, <String>{'read'});
      expect(claims.notBefore, fixedNow);
      expect(claims.expiresAt, fixedNow.add(const Duration(hours: 1)));
    });

    test('未知 issuer → accessDenied，文案能区分「未知签发者」', () async {
      // 用 B 的身份签，但验证方的表里只有 A。
      final String token = await codecAt(fixedNow, identity: identityB())
          .issue(grantAt(fixedNow, issuer: identityB().peerId));
      final CapabilityCodecImpl verifier = CapabilityCodecImpl(
        issuer: identityA(),
        revoked: TokenRevocationStore(),
        keys: lookupWithA(),
        clock: () => fixedNow,
      );
      await expectCode(
        () => verifier.verify(token),
        LanFileErrorCode.accessDenied,
        messageContains: '未知签发者',
      );
    });

    test('查找表为空时同样报未知签发者，而不是签名无效', () async {
      final String token = await codecAt(fixedNow).issue(grantAt(fixedNow));
      final CapabilityCodecImpl verifier = CapabilityCodecImpl(
        issuer: identityB(),
        revoked: TokenRevocationStore(),
        keys: FakePublicKeyLookup(),
        clock: () => fixedNow,
      );
      await expectCode(
        () => verifier.verify(token),
        LanFileErrorCode.accessDenied,
        messageContains: '未知签发者',
      );
    });

    test('用 B 的公钥去验 A 签的 token 必须失败（实现不得忽略 payload 里的 issuer）', () async {
      final String token = await codecAt(fixedNow).issue(grantAt(fixedNow));
      // 关键构造：payload 里写着 issuer=A，但查找表故意把 A 的公钥映射成 B 的。
      final FakePublicKeyLookup lyingLookup = FakePublicKeyLookup();
      lyingLookup.register(identityA().peerId, identityB().publicKey);

      final CapabilityCodecImpl verifier = CapabilityCodecImpl(
        issuer: identityB(),
        revoked: TokenRevocationStore(),
        keys: lyingLookup,
        clock: () => fixedNow,
      );
      await expectCode(
        () => verifier.verify(token),
        LanFileErrorCode.accessDenied,
        messageContains: '签名无效',
      );
    });

    test('篡改 payload 里的 issuer 字段后验签必须失败', () async {
      final String token = await codecAt(fixedNow).issue(grantAt(fixedNow));
      final List<String> parts = token.split('.');
      final Map<String, Object?> payload = decodePayload(token);

      // 把 issuer 改成 B：A 的签名覆盖的是原 issuer，改后必然验签失败。
      payload['issuer'] = identityB().peerId.value;
      final String tampered = '${encodePayload(payload)}.${parts[1]}';

      final CapabilityCodecImpl verifier = CapabilityCodecImpl(
        issuer: identityB(),
        revoked: TokenRevocationStore(),
        // 表里两个人都认得，确保失败原因只能是「签名对不上」。
        keys: lookupWith(<DeviceIdentity>[identityA(), identityB()]),
        clock: () => fixedNow,
      );
      await expectCode(
        () => verifier.verify(tampered),
        LanFileErrorCode.accessDenied,
        messageContains: '签名无效',
      );
    });

    test('篡改 payload 任意一个字段后验签必须失败', () async {
      final String token = await codecAt(fixedNow).issue(grantAt(fixedNow));
      final List<String> parts = token.split('.');
      final Map<String, Object?> payload = decodePayload(token);
      payload['jti'] = 'jti-hijacked';
      final String tampered = '${encodePayload(payload)}.${parts[1]}';

      final CapabilityCodecImpl verifier = CapabilityCodecImpl(
        issuer: identityA(),
        revoked: TokenRevocationStore(),
        keys: lookupWithA(),
        clock: () => fixedNow,
      );
      await expectCode(
        () => verifier.verify(tampered),
        LanFileErrorCode.accessDenied,
      );
    });

    test('issuer 不是合法 peerId 时拒绝', () async {
      final String token = await codecAt(fixedNow).issue(grantAt(fixedNow));
      final List<String> parts = token.split('.');
      final Map<String, Object?> payload = decodePayload(token);
      payload['issuer'] = 'not-a-peer-id';
      final String tampered = '${encodePayload(payload)}.${parts[1]}';

      final CapabilityCodecImpl verifier = CapabilityCodecImpl(
        issuer: identityA(),
        revoked: TokenRevocationStore(),
        keys: lookupWithA(),
        clock: () => fixedNow,
      );
      await expectCode(
        () => verifier.verify(tampered),
        LanFileErrorCode.accessDenied,
        messageContains: '不是合法 peerId',
      );
    });

    test('payload 缺少 issuer 字段时拒绝', () async {
      final String token = await codecAt(fixedNow).issue(grantAt(fixedNow));
      final List<String> parts = token.split('.');
      final Map<String, Object?> payload = decodePayload(token);
      payload.remove('issuer');
      final String tampered = '${encodePayload(payload)}.${parts[1]}';

      final CapabilityCodecImpl verifier = CapabilityCodecImpl(
        issuer: identityA(),
        revoked: TokenRevocationStore(),
        keys: lookupWithA(),
        clock: () => fixedNow,
      );
      await expectCode(
        () => verifier.verify(tampered),
        LanFileErrorCode.accessDenied,
        messageContains: '缺少 issuer',
      );
    });

    test('过期 token 必须抛 expired', () async {
      final String token = await codecAt(fixedNow).issue(
        grantAt(fixedNow, ttl: const Duration(minutes: 10)),
      );
      final CapabilityCodecImpl later = codecAt(
        fixedNow.add(const Duration(minutes: 11)),
      );
      await expectCode(() => later.verify(token), LanFileErrorCode.expired);
    });

    test('尚未生效（nbf 在未来）必须抛 accessDenied', () async {
      final String token = await codecAt(fixedNow).issue(grantAt(fixedNow));
      final CapabilityCodecImpl earlier = codecAt(
        fixedNow.subtract(const Duration(seconds: 1)),
      );
      await expectCode(
        () => earlier.verify(token),
        LanFileErrorCode.accessDenied,
        messageContains: '尚未生效',
      );
    });

    test('吊销后必须抛 revoked', () async {
      final TokenRevocationStore store = TokenRevocationStore();
      final CapabilityCodecImpl codec = codecAt(fixedNow, store: store);
      final String token = await codec.issue(grantAt(fixedNow));
      expect((await codec.verify(token)).tokenId, 'jti-0001');

      await store.revoke('jti-0001');
      await expectCode(() => codec.verify(token), LanFileErrorCode.revoked);
    });

    test('revokeAll 之后任何 token 都抛 revoked', () async {
      final TokenRevocationStore store = TokenRevocationStore();
      final CapabilityCodecImpl codec = codecAt(fixedNow, store: store);
      final String tokenA = await codec.issue(grantAt(fixedNow));
      final String tokenB =
          await codec.issue(grantAt(fixedNow, tokenId: 'jti-9999'));
      expect((await codec.verify(tokenA)).tokenId, 'jti-0001');

      await store.revokeAll();
      for (final String token in <String>[tokenA, tokenB]) {
        await expectCode(() => codec.verify(token), LanFileErrorCode.revoked);
      }
    });

    test('结构非法（多段、空段、非 base64url、签名长度错）一律 accessDenied', () async {
      final CapabilityCodecImpl codec = codecAt(fixedNow);
      final String good = await codec.issue(grantAt(fixedNow));
      final String payloadPart = good.split('.').first;
      final String signaturePart = good.split('.').last;
      final List<String> bad = <String>[
        '',
        'nodot',
        'a.b.c',
        '.$signaturePart',
        '$payloadPart.',
        '%%%%.$signaturePart',
        '$payloadPart.AAAA',
      ];
      for (final String token in bad) {
        await expectCode(
          () => codec.verify(token),
          LanFileErrorCode.accessDenied,
          reason: '非法 token 应当被拒绝: $token',
        );
      }
    });
  });

  group('verifyForSubject', () {
    test('sub 为 * 时任何主体都通过', () async {
      final CapabilityCodecImpl codec = codecAt(fixedNow);
      final String token = await codec.issue(grantAt(fixedNow, subject: '*'));
      final CapabilityClaims claims =
          await codec.verifyForSubject(token, 'p_aaaaaaaaaaaaa');
      expect(claims.subject, '*');
    });

    test('sub 精确匹配才通过，不匹配抛 accessDenied', () async {
      final CapabilityCodecImpl codec = codecAt(fixedNow);
      final String token =
          await codec.issue(grantAt(fixedNow, subject: 'p_aaaaaaaaaaaaa'));
      expect(
        (await codec.verifyForSubject(token, 'p_aaaaaaaaaaaaa')).subject,
        'p_aaaaaaaaaaaaa',
      );
      await expectCode(
        () => codec.verifyForSubject(token, 'p_bbbbbbbbbbbbb'),
        LanFileErrorCode.accessDenied,
        messageContains: '不适用于该主体',
      );
    });

    test('verifyForSubject 继承吊销判定', () async {
      final TokenRevocationStore store = TokenRevocationStore();
      final CapabilityCodecImpl codec = codecAt(fixedNow, store: store);
      final String token =
          await codec.issue(grantAt(fixedNow, subject: 'p_aaaaaaaaaaaaa'));
      await store.revoke('jti-0001');
      await expectCode(
        () => codec.verifyForSubject(token, 'p_aaaaaaaaaaaaa'),
        LanFileErrorCode.revoked,
      );
    });

    test('verifyForSubject 继承「未知签发者」判定', () async {
      final String token = await codecAt(fixedNow, identity: identityB())
          .issue(grantAt(fixedNow, issuer: identityB().peerId));
      final CapabilityCodecImpl verifier = CapabilityCodecImpl(
        issuer: identityA(),
        revoked: TokenRevocationStore(),
        keys: lookupWithA(),
        clock: () => fixedNow,
      );
      await expectCode(
        () => verifier.verifyForSubject(token, 'p_aaaaaaaaaaaaa'),
        LanFileErrorCode.accessDenied,
        messageContains: '未知签发者',
      );
    });
  });

  group('跨节点语义', () {
    test('同一 token 在任意节点得到同一结论（同一组公钥表）', () async {
      final String token = await codecAt(fixedNow).issue(
        grantAt(fixedNow, subject: 'p_aaaaaaaaaaaaa'),
      );
      final List<CapabilityCodecImpl> nodes = <CapabilityCodecImpl>[
        codecAt(fixedNow),
        CapabilityCodecImpl(
          issuer: identityB(),
          revoked: TokenRevocationStore(),
          keys: lookupWith(<DeviceIdentity>[identityA(), identityB()]),
          clock: () => fixedNow,
        ),
      ];
      for (final CapabilityCodecImpl node in nodes) {
        final CapabilityClaims claims =
            await node.verifyForSubject(token, 'p_aaaaaaaaaaaaa');
        expect(claims.issuer, identityA().peerId);
        expect(claims.tokenId, 'jti-0001');
      }
    });

    test('各节点吊销表独立：一个节点吊销不影响另一个节点（离线吊销的诚实边界）', () async {
      final String token = await codecAt(fixedNow).issue(grantAt(fixedNow));

      final TokenRevocationStore storeX = TokenRevocationStore();
      final CapabilityCodecImpl nodeX = CapabilityCodecImpl(
        issuer: identityA(),
        revoked: storeX,
        keys: lookupWithA(),
        clock: () => fixedNow,
      );
      final CapabilityCodecImpl nodeY = CapabilityCodecImpl(
        issuer: identityA(),
        revoked: TokenRevocationStore(),
        keys: lookupWithA(),
        clock: () => fixedNow,
      );

      expect((await nodeX.verify(token)).tokenId, 'jti-0001');
      await storeX.revoke('jti-0001');
      await expectCode(() => nodeX.verify(token), LanFileErrorCode.revoked);
      // Y 没收到吊销通告，仍认这个 token —— 这是无中心下的真实边界。
      expect((await nodeY.verify(token)).tokenId, 'jti-0001');
    });

    test('公钥查找表对外可读写，端到端注入点可用', () async {
      final CapabilityCodecImpl codec = codecAt(fixedNow);
      expect(codec.keys, isA<FakePublicKeyLookup>());
      expect(codec.issuer.peerId, identityA().peerId);
      final FakePublicKeyLookup lookup = codec.keys as FakePublicKeyLookup;
      expect(lookup.size, 1);
      lookup.register(identityB().peerId, identityB().publicKey);
      expect(lookup.size, 2);
      expect(await lookup.findPublicKey(identityB().peerId), isNotNull);
      lookup.forget(identityB().peerId);
      expect(await lookup.findPublicKey(identityB().peerId), isNull);
    });
  });
}
