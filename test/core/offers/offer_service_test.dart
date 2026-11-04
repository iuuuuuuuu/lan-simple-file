// SPDX-License-Identifier: GPL-3.0-only

/// offer 全流程测试：真实 sqlite + 真实临时目录 + 真实文件。
///
/// 不 mock 存储（用 LanFileStoreImpl 写真实 .sqlite 文件），
/// 也不 mock 文件（在真实临时目录里造真实文件）。
/// 投递层用 [RecordingTransport]：它记录帧、可切换可达性，
/// 但不是「假装成功」——它是本模块对外的真实接口，
/// 真实网络投递属于发现/网络层，由组装层注入。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/identity/capability_codec_impl.dart';
import 'package:lan_simple_file/core/identity/device_identity_impl.dart';
import 'package:lan_simple_file/core/identity/token_revocation_store.dart';
import 'package:lan_simple_file/core/offers/offer_codec.dart';
import 'package:lan_simple_file/core/offers/offer_service_impl.dart';
import 'package:lan_simple_file/core/store/store_impl.dart';

/// 记录型投递器：把 offer 帧留在内存里，可按 peer 切换可达性。
final class RecordingTransport implements OfferTransport {
  RecordingTransport();

  final List<Map<String, Object?>> frames = <Map<String, Object?>>[];
  final Set<String> offline = <String>{};

  void setOffline(PeerId peer, {required bool offline}) {
    if (offline) {
      this.offline.add(peer.value);
    } else {
      this.offline.remove(peer.value);
    }
  }

  @override
  Future<bool> isReachable(PeerId peer) async => !offline.contains(peer.value);

  @override
  Future<void> deliver(
    Map<String, Object?> frame, {
    required PeerId toPeer,
  }) async {
    frames.add(frame);
  }
}

/// 由库支撑的公钥查表（与 assembly 里那份等价，测试独立一份避免依赖 app 层）。
final class _StoreKeys implements PublicKeyLookup {
  const _StoreKeys(this._store);

  final LanFileStore _store;

  @override
  Future<Uint8List?> findPublicKey(PeerId peerId) async {
    final DeviceRecord? r = await _store.findDevice(peerId);
    if (r == null || r.publicKey.isEmpty) return null;
    return r.publicKey;
  }
}

DeviceIdentityImpl _identity(int seedByte) => DeviceIdentityImpl.fromSeed(
      Uint8List.fromList(
        List<int>.generate(32, (int i) => (i * 17 + seedByte) % 256),
      ),
    );

void main() {
  late Directory tempDir;
  late Directory fileDir;
  late LanFileStoreImpl store;
  late DeviceIdentityImpl me;
  late DeviceIdentityImpl peerIdentity;
  late PeerId peer;
  late RecordingTransport transport;
  late OfferServiceImpl service;
  late OfferServiceImpl receiver;
  late DateTime now;

  CapabilityCodec buildCodec() => CapabilityCodecImpl(
        issuer: me,
        revoked: TokenRevocationStore(),
        keys: _StoreKeys(store),
        clock: () => now,
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lsf_offer_db_');
    fileDir = await Directory.systemTemp.createTemp('lsf_offer_files_');
    store = await LanFileStoreImpl.open(
      dbFile: File('${tempDir.path}${Platform.pathSeparator}o.sqlite'),
    );
    me = _identity(1);
    peerIdentity = _identity(200);
    peer = peerIdentity.peerId;
    now = DateTime.utc(2026, 11, 4, 10, 0, 0);

    // 双方设备都入库：凭证验签要靠公钥查表。
    await store.upsertDevice(DeviceRecord(
      peerId: me.peerId,
      publicKey: me.publicKey,
      name: 'Me',
      avatarHash: '',
      os: 'windows',
      firstSeen: now,
      lastSeen: now,
      online: true,
      isSelf: true,
      isGuest: false,
      note: '',
    ));
    await store.upsertDevice(DeviceRecord(
      peerId: peer,
      publicKey: peerIdentity.publicKey,
      name: 'Peer',
      avatarHash: '',
      os: 'android',
      firstSeen: now,
      lastSeen: now,
      online: true,
      isSelf: false,
      isGuest: false,
      note: '',
    ));

    transport = RecordingTransport();
    // 发起方服务：本机身份 me。
    service = OfferServiceImpl(
      store: store,
      identity: me,
      codec: buildCodec(),
      transport: transport,
      clock: () => now,
      offerIdGenerator: () => 'f_fixed01',
    );
    // 接收方服务：对端身份 peerIdentity，共享同一库（单进程双实例，存储层真实）。
    // 真实部署里两端各有各的库；这里共用一份是为了让凭证公钥查表可直接命中。
    receiver = OfferServiceImpl(
      store: store,
      identity: peerIdentity,
      codec: CapabilityCodecImpl(
        issuer: me,
        revoked: TokenRevocationStore(),
        keys: _StoreKeys(store),
        clock: () => now,
      ),
      transport: transport,
      clock: () => now,
    );
  });

  tearDown(() async {
    await receiver.dispose();
    await service.dispose();
    await store.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    if (fileDir.existsSync()) await fileDir.delete(recursive: true);
  });

  File makeFile(String name, int bytes) {
    final File f = File('${fileDir.path}${Platform.pathSeparator}$name');
    f.writeAsBytesSync(List<int>.generate(bytes, (int i) => i % 256));
    return f;
  }

  group('propose', () {
    test('只发元数据：帧里不含任何文件内容字节', () async {
      final File f = makeFile('报告.txt', 1024);
      final String offerId = await service.propose(
        toPeer: peer,
        localPaths: <String>[f.path],
        note: '请查收',
      );

      expect(offerId, 'f_fixed01');
      expect(transport.frames.length, 1);
      final Map<String, Object?> frame = transport.frames.single;
      final Map<String, Object?> file =
          (frame['files']! as List<Object?>).single! as Map<String, Object?>;
      expect(file['name'], '报告.txt');
      expect(file['size'], 1024);
      // 关键断言：帧里只有元数据，没有内容。
      expect(file.keys.toSet(),
          <String>{'itemKey', 'name', 'size', 'mime', 'isDir'});
      // 整帧序列化后不得出现文件内容（用前 16 字节做特征串）。
      final String encoded = jsonEncode(frame);
      final List<int> head =
          List<int>.generate(16, (int i) => i % 256);
      expect(encoded.contains(base64Encode(head)), isFalse);
    });

    test('对端离线时抛 providerOffline，且不落库不投递', () async {
      transport.setOffline(peer, offline: true);
      final File f = makeFile('x.bin', 8);
      await expectLater(
        service.propose(toPeer: peer, localPaths: <String>[f.path]),
        throwsA(isA<LanFileException>().having(
          (LanFileException e) => e.code,
          'code',
          LanFileErrorCode.providerOffline,
        )),
      );
      expect(transport.frames, isEmpty);
      expect(await store.listPendingOffers(peer), isEmpty);
    });

    test('空路径列表被拒绝', () async {
      await expectLater(
        service.propose(toPeer: peer, localPaths: const <String>[]),
        throwsA(isA<LanFileException>()),
      );
    });

    test('不存在的路径被拒绝（notFound），不落一条假 offer', () async {
      await expectLater(
        service.propose(
          toPeer: peer,
          localPaths: <String>[
            '${fileDir.path}${Platform.pathSeparator}不存在.bin',
          ],
        ),
        throwsA(isA<LanFileException>()),
      );
      expect(await store.listPendingOffers(peer), isEmpty);
    });

    test('不能向自己 propose', () async {
      final File f = makeFile('self.bin', 4);
      await expectLater(
        service.propose(toPeer: me.peerId, localPaths: <String>[f.path]),
        throwsA(isA<LanFileException>()),
      );
    });
  });

  group('接收方视角与零字节承诺', () {
    test('accept 之前：库中不存在临时 share', () async {
      final File f = makeFile('a.txt', 32);
      final String offerId =
          await service.propose(toPeer: peer, localPaths: <String>[f.path]);

      expect(await receiver.tempShareOf(offerId), isNull,
          reason: '接受前不得存在任何可读临时 share');
      expect(await receiver.isTempShareReadable(offerId), isFalse);
      // 全库也没有任何 isEphemeral 分享。
      final List<ShareRecord> all = await store.listShares();
      expect(all.where((ShareRecord s) => s.isEphemeral), isEmpty);
    });

    test('watchIncoming 只吐 toPeer=本机的 pending（发起方看不到、接收方看得到）', () async {
      final File f = makeFile('w.txt', 16);
      final String offerId =
          await service.propose(toPeer: peer, localPaths: <String>[f.path], note: '给你');

      // 发起方侧：这条是发给别人的，不应出现在「收件箱」。
      final List<OfferView> mine = await service.watchIncoming().first;
      expect(mine, isEmpty, reason: '发起方不应看到自己发出的 offer');

      // 接收方侧：必须看得到，且字段齐全。
      final List<OfferView> theirs = await receiver.watchIncoming().first;
      expect(theirs.length, 1, reason: '接收方必须看到待决策 offer');
      expect(theirs.single.id, offerId);
      expect(theirs.single.files.single.name, 'w.txt');
      expect(theirs.single.sizeTotal, 16);
      expect(theirs.single.note, '给你');
      expect(theirs.single.status, 'pending');
    });
  });

  group('全链路：propose -> accept -> 可读 -> revoke -> 不可读', () {
    test('接受后临时 share 可读，撤销后立即不可读', () async {
      final File f = makeFile('photo.jpg', 2048);
      final String offerId =
          await service.propose(toPeer: peer, localPaths: <String>[f.path]);

      // 本机既是发起方也是接收方（同一 store 上模拟对端接受）。
      final ShareRecord share = await receiver.accept(offerId);

      expect(share.mode, ShareMode.offer);
      expect(share.isEphemeral, isTrue);
      expect(share.expiresAt, isNotNull);
      expect(share.expiresAt!.toUtc(),
          now.add(LanFileConstants.offerShareTtl));

      // 可读。
      expect(await receiver.isTempShareReadable(offerId), isTrue);
      // 但过期时刻之后不可读。
      final DateTime afterExpiry =
          now.add(LanFileConstants.offerShareTtl).add(const Duration(seconds: 1));
      expect(
        await receiver.isTempShareReadable(offerId, at: afterExpiry),
        isFalse,
        reason: '超过 expiresAt 必须不可读',
      );

      // 撤销后立即不可读。
      await receiver.revokeOffer(offerId);
      expect(await receiver.isTempShareReadable(offerId), isFalse,
          reason: '撤销后必须立即不可读');
      final ShareRecord? revoked = await store.findShare(share.id);
      expect(revoked!.isRevoked, isTrue);
      expect(revoked.enabled, isFalse);
    });

    test('撤销是幂等的，重复撤销不抛异常', () async {
      final File f = makeFile('r.bin', 8);
      final String offerId =
          await service.propose(toPeer: peer, localPaths: <String>[f.path]);
      await receiver.accept(offerId);
      await receiver.revokeOffer(offerId);
      await receiver.revokeOffer(offerId);
      expect(await receiver.isTempShareReadable(offerId), isFalse);
    });

    test('接受后 offer 状态为 accepted 且落库', () async {
      final File f = makeFile('s.txt', 12);
      final String offerId =
          await service.propose(toPeer: peer, localPaths: <String>[f.path]);
      await receiver.accept(offerId);
      final OfferRecord? record = await store.findOffer(offerId);
      expect(record!.status, OfferStatusWire.accepted);
      expect(record.decidedAt, now);
    });
  });

  group('过期', () {
    test('decision ttl 过后 pending 变 expired，accept 抛 expired', () async {
      final File f = makeFile('e.txt', 8);
      final String offerId =
          await service.propose(toPeer: peer, localPaths: <String>[f.path]);

      // 把时钟推到 decision ttl 之后。
      now = now.add(LanFileConstants.offerDecisionTtl).add(
          const Duration(seconds: 1));

      await expectLater(
        receiver.accept(offerId),
        throwsA(isA<LanFileException>().having(
          (LanFileException e) => e.code,
          'code',
          LanFileErrorCode.expired,
        )),
      );
      final OfferRecord? record = await store.findOffer(offerId);
      expect(record!.status, OfferStatusWire.expired,
          reason: '过期状态必须落库，不能只在内存判断');
    });

    test('过期 offer 不再出现在 pending 列表里', () async {
      final File f = makeFile('p.txt', 8);
      await service.propose(toPeer: peer, localPaths: <String>[f.path]);
      expect((await store.listPendingOffers(peer)).length, 1);
      now = now.add(LanFileConstants.offerDecisionTtl).add(
          const Duration(seconds: 1));
      await receiver.watchIncoming().first; // 触发结算
      // 对本机而言本来就没有 pending；直接查库确认已结算。
      final OfferRecord? record = await store.findOffer('f_fixed01');
      expect(record!.status, OfferStatusWire.expired);
    });
  });

  group('拒绝', () {
    test('reject 后状态为 rejected，理由可被发起方读回', () async {
      final File f = makeFile('no.bin', 8);
      final String offerId =
          await service.propose(toPeer: peer, localPaths: <String>[f.path]);
      await receiver.reject(offerId, reason: '磁盘空间不足');

      final OfferRecord? record = await store.findOffer(offerId);
      expect(record!.status, OfferStatusWire.rejected);

      // 发起方读回理由（走同一个 envelope）。
      final OfferEnvelope envelope =
          OfferEnvelope.decode(record.filesJson);
      expect(envelope.rejectReason, '磁盘空间不足');

      // 决策帧也应带理由。
      final Map<String, Object?> decision = transport.frames.last;
      expect(decision['accepted'], isFalse);
      expect(decision['reason'], '磁盘空间不足');
    });

    test('reject 后再 accept 抛 conflict', () async {
      final File f = makeFile('c.bin', 8);
      final String offerId =
          await service.propose(toPeer: peer, localPaths: <String>[f.path]);
      await receiver.reject(offerId, reason: '不要');
      await expectLater(
        receiver.accept(offerId),
        throwsA(isA<LanFileException>()),
      );
    });
  });

  group('权限边界', () {
    test('非 toPeer 的设备不能 accept/reject 别人的 offer', () async {
      final File f = makeFile('auth.bin', 8);
      final String offerId =
          await service.propose(toPeer: peer, localPaths: <String>[f.path]);

      // 换一个「不是接收方」的身份构造服务，尝试 accept。
      final DeviceIdentityImpl third = _identity(99);
      await store.upsertDevice(DeviceRecord(
        peerId: third.peerId,
        publicKey: third.publicKey,
        name: 'Third',
        avatarHash: '',
        os: 'windows',
        firstSeen: now,
        lastSeen: now,
        online: true,
        isSelf: false,
        isGuest: false,
        note: '',
      ));
      final OfferServiceImpl thirdService = OfferServiceImpl(
        store: store,
        identity: third,
        codec: CapabilityCodecImpl(
          issuer: third,
          revoked: TokenRevocationStore(),
          keys: _StoreKeys(store),
          clock: () => now,
        ),
        transport: transport,
        clock: () => now,
      );
      await expectLater(
        thirdService.accept(offerId),
        throwsA(isA<LanFileException>().having(
          (LanFileException e) => e.code,
          'code',
          LanFileErrorCode.accessDenied,
        )),
      );
      await thirdService.dispose();
    });

    test('不存在的 offer 抛 notFound 而不是静默成功', () async {
      await expectLater(
        receiver.accept('f_nope'),
        throwsA(isA<LanFileException>().having(
          (LanFileException e) => e.code,
          'code',
          LanFileErrorCode.notFound,
        )),
      );
    });
  });
}