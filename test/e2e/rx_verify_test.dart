// SPDX-License-Identifier: GPL-3.0-only

/// 收侧验签的真实证据：篡改的消息必须被拒收，正常消息必须收下。
///
/// 只证明「发侧签了名」不够——那只是「能签」。
/// 这条证明「收侧会验」，即签名真的挡住了篡改。
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

final class _Lookup implements PublicKeyLookup {
  _Lookup(this.entries);

  final Map<String, Uint8List> entries;

  @override
  Future<Uint8List?> findPublicKey(PeerId peerId) async =>
      entries[peerId.value];
}

void main() {
  late Directory tmp;
  late LanFileStoreImpl storeB;
  late DeviceIdentityImpl alice;
  late DeviceIdentityImpl bob;
  late String peerB;
  late String selfA;
  late String hlcText;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('lsf_rxverify_');
    storeB = await LanFileStoreImpl.open(
      dbFile: File('${tmp.path}${Platform.pathSeparator}b.sqlite'),
    );
    alice = DeviceIdentityImpl.fromSeed(
      Uint8List.fromList(List<int>.generate(32, (int i) => i + 7)),
    );
    selfA = alice.peerId.value;
    bob = DeviceIdentityImpl.fromSeed(
      Uint8List.fromList(List<int>.generate(32, (i) => i + 70)),
    );
    peerB = bob.peerId.value;
    hlcText = '1767225600000:0:$selfA';
  });

  tearDown(() async {
    await storeB.close();
    for (int i = 0; i < 6; i++) {
      try {
        if (tmp.existsSync()) {
          tmp.deleteSync(recursive: true);
        }
        return;
      } on FileSystemException {
        sleep(const Duration(milliseconds: 120));
      }
    }
  });

  String directThread() {
    final List<String> pair = <String>[selfA, peerB]..sort();
    final String low = pair[0];
    final String high = pair[1];
    return 'd_$low--$high';
  }

  Uint8List canonicalFor(String body) => MessageSignature.canonicalBytes(
    messageId: '$selfA:1',
    threadId: directThread(),
    senderPeerId: selfA,
    hlc: hlcText,
    tsMillis: 1767225600000,
    kind: 'text',
    body: body,
    attachJson: '{}',
  );

  Map<String, Object?> payloadFor({required String body, required String sig}) {
    return <String, Object?>{
      'id': '$selfA:1',
      'thread': directThread(),
      'from': selfA,
      'kind': 'text',
      'hlc': hlcText,
      'ts': 1767225600000,
      'body': body,
      'attach': '{}',
      'sig': sig,
    };
  }

  MessagingServiceImpl makeB({_Lookup? lookup, SignatureVerifier? verifier}) =>
      MessagingServiceImpl(
        store: storeB,
        identity: bob,
        selfName: 'B',
        selfAvatarHash: '',
        keys: lookup,
        verifier: verifier,
      );

  test('正常签名消息：收侧验签通过并落库', () async {
    final Uint8List sig = await alice.sign(canonicalFor('正常内容'));
    final MessagingServiceImpl b = makeB(
      lookup: _Lookup(<String, Uint8List>{alice.peerId.value: alice.publicKey}),
      verifier: Ed25519Signer(),
    );
    await b.handleFrame(
      alice.peerId,
      WsFrame(
        WsFrame.msg,
        payloadFor(
          body: '正常内容',
          sig: base64Url.encode(sig).replaceAll('=', ''),
        ),
      ),
    );
    final List<MessageRecord> stored = await storeB.listMessages(
      directThread(),
      limit: -1,
    );
    expect(stored.length, 1);
    expect(stored.single.body, '正常内容');
    expect(b.unverifiedInbound, 0);
    await b.dispose();
  });

  test('篡改正文：收侧必须拒收，且库里不留脏消息', () async {
    final Uint8List sig = await alice.sign(canonicalFor('正常内容'));
    final MessagingServiceImpl b = makeB(
      lookup: _Lookup(<String, Uint8List>{alice.peerId.value: alice.publicKey}),
      verifier: Ed25519Signer(),
    );
    await expectLater(
      b.handleFrame(
        alice.peerId,
        WsFrame(
          WsFrame.msg,
          payloadFor(
            body: '被改了',
            sig: base64Url.encode(sig).replaceAll('=', ''),
          ),
        ),
      ),
      throwsA(isA<LanFileException>()),
    );
    final List<MessageRecord> stored = await storeB.listMessages(
      directThread(),
      limit: -1,
    );
    expect(stored, isEmpty, reason: '拒收的消息绝不允许落库');
    await b.dispose();
  });

  test('未知发送者：查不到公钥必须拒收，不静默接受', () async {
    final MessagingServiceImpl b = makeB(
      lookup: _Lookup(<String, Uint8List>{}),
      verifier: Ed25519Signer(),
    );
    await expectLater(
      b.handleFrame(
        alice.peerId,
        WsFrame(WsFrame.msg, payloadFor(body: '正常内容', sig: 'AAAA')),
      ),
      throwsA(isA<LanFileException>()),
    );
    await b.dispose();
  });

  test('未注入 keys/verifier 时降级：计入 unverifiedInbound，不静默', () async {
    final MessagingServiceImpl b = makeB();
    await b.handleFrame(
      alice.peerId,
      WsFrame(WsFrame.msg, payloadFor(body: '未验签也收下', sig: '')),
    );
    expect(b.unverifiedInbound, 1, reason: '降级必须留计数，不能隐形');
    final List<MessageRecord> stored = await storeB.listMessages(
      directThread(),
      limit: -1,
    );
    expect(stored.length, 1);
    await b.dispose();
  });
}
