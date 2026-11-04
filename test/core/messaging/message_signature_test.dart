// SPDX-License-Identifier: GPL-3.0-only

/// 消息签名测试：真实 Ed25519 验签，不是「字段非空」这种伪证据。
///
/// 两条核心用例：
///  a) 落库消息的 sig 能被本机公钥验签通过（证明签名真起作用）；
///  b) 篡改 body 一个字节后验签失败（证明签名绑定了内容）。
///
/// 额外锁定一条已知风险：中文正文在当前契约 canonicalBytes 下会被截断，
/// 见文件末尾用例与报告中的缺陷说明。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/identity/device_identity_impl.dart';
import 'package:lan_simple_file/core/identity/ed25519_signer.dart';
import 'package:lan_simple_file/core/messaging/messaging_service_impl.dart';
import 'package:lan_simple_file/core/store/store_impl.dart';

DeviceIdentityImpl _identity(int seedByte) => DeviceIdentityImpl.fromSeed(
      Uint8List.fromList(
        List<int>.generate(32, (int i) => (i * 13 + seedByte) % 256),
      ),
    );

/// 从 base64url（无填充）还原签名字节。
Uint8List _decodeSig(String sig) {
  final int remainder = sig.length % 4;
  final String padded = remainder == 0 ? sig : sig + '=' * (4 - remainder);
  return Uint8List.fromList(base64Url.decode(padded));
}

/// 用契约的规范化规则重算签名载荷，供验签使用。
Uint8List _canonicalOf(MessageRecord record) => MessageSignature.canonicalBytes(
      messageId: record.id,
      threadId: record.threadId,
      senderPeerId: record.senderPeerId.value,
      hlc: record.hlc.encode(),
      tsMillis: record.ts.millisecondsSinceEpoch,
      kind: record.kind.name,
      body: record.body,
      attachJson: record.attachJson,
    );

void main() {
  late Directory tempDir;
  late LanFileStoreImpl store;
  late DeviceIdentityImpl me;
  late MessagingServiceImpl service;
  late PeerId peer;
  late String threadId;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lsf_sig_test_');
    store = await LanFileStoreImpl.open(
      dbFile: File('${tempDir.path}${Platform.pathSeparator}sig.sqlite'),
    );
    me = _identity(3);
    peer = _identity(9).peerId;
    service = MessagingServiceImpl(
      store: store,
      identity: me,
      selfName: 'A',
      selfAvatarHash: '',
    );
    threadId = directThreadId(me.peerId, peer);
  });

  tearDown(() async {
    await service.dispose();
    await store.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('消息签名真的起作用', () {
    test('落库消息 sig 非空，且用本机公钥验签通过', () async {
      await service.sendText(threadId, '同意这个方案');

      final List<MessageRecord> list =
          await store.listMessages(threadId, limit: -1);
      expect(list.length, 1);
      final MessageRecord record = list.single;

      expect(record.sig, isNotEmpty, reason: '注入身份后必须真的签上');

      final Uint8List signature = _decodeSig(record.sig);
      expect(signature.length, kEd25519SignatureBytes);

      final bool ok = await Ed25519Signer().verify(
        _canonicalOf(record),
        signature,
        me.publicKey,
      );
      expect(ok, isTrue, reason: '规范化载荷 + 本机公钥必须验签通过');
    });

    test('篡改 body 一个字节后验签失败', () async {
      await service.sendText(threadId, '转账 100 元');
      final MessageRecord record =
          (await store.listMessages(threadId, limit: -1)).single;
      final Uint8List signature = _decodeSig(record.sig);

      // 先确认原样能验过，避免「本来就验不过」掩盖问题。
      expect(
        await Ed25519Signer().verify(
          _canonicalOf(record), signature, me.publicKey),
        isTrue,
      );

      // 改一个字符（'元' -> '圆'），规范化载荷变化，签名应失效。
      final MessageRecord tampered = MessageRecord(
        id: record.id,
        threadId: record.threadId,
        senderPeerId: record.senderPeerId,
        kind: record.kind,
        hlc: record.hlc,
        ts: record.ts,
        body: '转账 100 圆',
        attachJson: record.attachJson,
        sig: record.sig,
      );
      expect(
        await Ed25519Signer().verify(
          _canonicalOf(tampered), signature, me.publicKey),
        isFalse,
        reason: '正文被改，签名必须失效',
      );
    });

    test('篡改 hlc 也会导致验签失败（HLC 在签名范围内）', () async {
      await service.sendText(threadId, '顺序敏感');
      final MessageRecord record =
          (await store.listMessages(threadId, limit: -1)).single;
      final Uint8List signature = _decodeSig(record.sig);

      final MessageRecord tampered = MessageRecord(
        id: record.id,
        threadId: record.threadId,
        senderPeerId: record.senderPeerId,
        kind: record.kind,
        hlc: Hlc(
          millis: record.hlc.millis + 1,
          counter: record.hlc.counter,
          origin: record.hlc.origin,
        ),
        ts: record.ts,
        body: record.body,
        attachJson: record.attachJson,
        sig: record.sig,
      );
      expect(
        await Ed25519Signer().verify(
          _canonicalOf(tampered), signature, me.publicKey),
        isFalse,
      );
    });

    test('撤回不进签名：撤回后原签名仍然有效', () async {
      // 这是契约的设计意图：撤回/删除/编辑是后续事件，
      // 若纳入签名，一撤回历史消息就会集体变成「签名无效」。
      await service.sendText(threadId, '先发后撤');
      final MessageRecord before =
          (await store.listMessages(threadId, limit: -1)).single;
      final Uint8List signature = _decodeSig(before.sig);

      await service.revoke(before.id, reason: '撤回测试');
      final MessageRecord after =
          (await store.listMessages(threadId, limit: -1)).single;

      expect(after.isRevoked, isTrue);
      expect(after.sig, before.sig, reason: '撤回不得改动已签名的 sig 字段');
      expect(
        await Ed25519Signer().verify(
          _canonicalOf(after), signature, me.publicKey),
        isTrue,
        reason: '撤回后原签名必须仍然有效（撤回不在签名范围内）',
      );
    });

    test('sendFile 也带签名', () async {
      await service.sendFile(threadId, ShareId.parse('sh_sig01'));
      final MessageRecord record =
          (await store.listMessages(threadId, limit: -1)).single;
      expect(record.sig, isNotEmpty);
      expect(
        await Ed25519Signer().verify(
          _canonicalOf(record), _decodeSig(record.sig), me.publicKey),
        isTrue,
      );
    });

    test('不同身份签出的消息不能用别人公钥验过', () async {
      await service.sendText(threadId, '我是 A');
      final MessageRecord record =
          (await store.listMessages(threadId, limit: -1)).single;
      final Uint8List otherPublicKey = _identity(77).publicKey;
      expect(
        await Ed25519Signer().verify(
          _canonicalOf(record), _decodeSig(record.sig), otherPublicKey),
        isFalse,
      );
    });
  });

  group('已知风险：canonicalBytes 的 UTF-16 截断', () {
    test('中文正文参与签名时仍能往返验签（当前实现路径可用）', () async {
      // 能验过说明接线正确；但这不等于安全——见下一条与报告。
      await service.sendText(threadId, '你好，世界');
      final MessageRecord record =
          (await store.listMessages(threadId, limit: -1)).single;
      expect(record.sig, isNotEmpty);
      expect(
        await Ed25519Signer().verify(
          _canonicalOf(record), _decodeSig(record.sig), me.publicKey),
        isTrue,
      );
    });

    test('修复验证：不同正文必须产生不同规范化字节（原先会碰撞）', () {
      // 历史背景：契约层 MessageSignature.canonicalBytes 曾用 codeUnits，
      // UTF-16 码元被截断成低 8 位，'A' 与 'Ł' 产生完全相同的字节 → 签名可被绕过。
      // 已改为 utf8.encode。这条用例原先断言 a == b（锁定缺陷现状），
      // 契约修复后翻转成 a != b（锁定修复生效）。
      final Uint8List a = MessageSignature.canonicalBytes(
        messageId: 'm1',
        threadId: 't',
        senderPeerId: 'p_aaaaaaaaaaaaa',
        hlc: '1:0:x',
        tsMillis: 1,
        kind: 'text',
        body: 'A',
        attachJson: '',
      );
      final Uint8List b = MessageSignature.canonicalBytes(
        messageId: 'm1',
        threadId: 't',
        senderPeerId: 'p_aaaaaaaaaaaaa',
        hlc: '1:0:x',
        tsMillis: 1,
        kind: 'text',
        body: '\u0141', // 拉丁大写 L with stroke
        attachJson: '',
      );
      expect(a, isNot(equals(b)),
          reason: '修复后不得碰撞；若变红说明 canonicalBytes 又退回了 codeUnits');
    });
  });
}
