// SPDX-License-Identifier: GPL-3.0-only

/// 会话失效与回收：心跳超时、显式撤销、页面关闭、宽限期删除、配额。
///
/// 全部用注入时钟推进时间，测试里没有任何 sleep。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/webshare/guest_session_registry.dart';
import 'package:lan_simple_file/core/files/local_ref.dart';
import 'package:lan_simple_file/core/webshare/session_sweeper.dart';
import 'package:lan_simple_file/core/webshare/staging_area.dart';
import 'package:lan_simple_file/core/webshare/web_share_service_impl.dart';

import 'support/web_share_fixture.dart';

const String kClientPubkey = 'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEtest';

void main() {
  group('心跳超时判定', () {
    test('停 1 拍不失效，停 2 拍判失效', () async {
      final WebShareFixture f = await WebShareFixture.create();
      addTearDown(f.dispose);

      final String sessionId = await f.service.openSession(
        clientPubkey: kClientPubkey,
      );

      // 恰好 1 拍（15s）：仍在容忍范围内。
      f.clock.advance(const Duration(seconds: 15));
      expect(f.registry.reapExpired(), isEmpty);
      expect(f.registry.isUsable(sessionId), isTrue);

      // 累计 2 拍（30s）：判定失效。
      f.clock.advance(const Duration(seconds: 15));
      final List<GuestSession> ended = f.registry.reapExpired();
      expect(ended, hasLength(1));
      expect(ended.single.sessionId, sessionId);
      expect(ended.single.endReason, SessionEndReason.heartbeatTimeout);
      expect(f.registry.isUsable(sessionId), isFalse);
    });

    test('心跳可续命：14s 一次心跳永远不会失效', () async {
      final WebShareFixture f = await WebShareFixture.create();
      addTearDown(f.dispose);
      final String sessionId = await f.service.openSession(
        clientPubkey: kClientPubkey,
      );
      for (int i = 0; i < 10; i++) {
        f.clock.advance(const Duration(seconds: 14));
        expect(await f.service.heartbeat(sessionId), isTrue);
        expect(f.registry.reapExpired(), isEmpty);
      }
      expect(f.registry.isUsable(sessionId), isTrue);
    });

    test('sweep 把超时会话的 share 置 revoked（链接 410）', () async {
      final WebShareFixture f = await WebShareFixture.create();
      addTearDown(f.dispose);
      final String sessionId = await f.service.openSession(
        clientPubkey: kClientPubkey,
      );
      final UploadGrant grant = f.service.acknowledgeAcceptedOffer(
        sessionId: sessionId,
        offerId: 'o1',
        fileName: 'a.bin',
        declaredSize: 8,
      );
      final UploadTicket ticket = await f.service.beginAuthorizedUpload(
        sessionId: sessionId,
        offerId: 'o1',
        fileName: 'a.bin',
        declaredSize: 8,
        token: grant.token,
        uploadId: 'up0001',
      );
      await f.service.writeChunk(
        sessionId: sessionId,
        uploadId: 'up0001',
        offset: 0,
        data: List<int>.filled(8, 1),
      );
      final ShareRecord record = await f.service.completeUpload(
        sessionId: sessionId,
        uploadId: 'up0001',
        displayName: 'a.bin',
      );
      expect(ticket.upload.fileName, 'a.bin');

      // 失效前：链接可读。
      expect(await f.service.isLinkReadable(record.id), isTrue);

      // 推过 2 拍，sweep 触发回收。
      f.clock.advance(const Duration(seconds: 31));
      final SweepResult result = await f.service.sweep();
      expect(result.expiredSessions, contains(sessionId));
      expect(result.revokedShares, contains(record.id.value));

      // 链接立即 410（可读性为 false）。
      expect(await f.service.isLinkReadable(record.id), isFalse);
      final ShareRecord? after = await f.store.findShare(record.id);
      expect(after!.revokedAt, isNotNull);
    });
  });

  group('显式撤销与页面关闭', () {
    test('revokeSession 立即让链接失效（不等 sweep）', () async {
      final WebShareFixture f = await WebShareFixture.create();
      addTearDown(f.dispose);
      final String sessionId = await f.service.openSession(
        clientPubkey: kClientPubkey,
      );
      final ShareRecord record = await f.service.acceptUpload(
        sessionId,
        _offer(),
        _fakeRef(f, sessionId),
      );
      expect(await f.service.isLinkReadable(record.id), isTrue);

      await f.service.revokeSession(sessionId);

      // 没有 sweep，也应立即失效。
      expect(await f.service.isLinkReadable(record.id), isFalse);
      final GuestSession? session = f.registry.find(sessionId);
      expect(session!.endReason, SessionEndReason.explicitRevoke);
    });

    test('closeSession（beforeunload）同样立即失效', () async {
      final WebShareFixture f = await WebShareFixture.create();
      addTearDown(f.dispose);
      final String sessionId = await f.service.openSession(
        clientPubkey: kClientPubkey,
      );
      final ShareRecord record = await f.service.acceptUpload(
        sessionId,
        _offer(),
        _fakeRef(f, sessionId),
      );
      await f.service.closeSession(sessionId);
      expect(await f.service.isLinkReadable(record.id), isFalse);
      expect(
        f.registry.find(sessionId)!.endReason,
        SessionEndReason.pageClosed,
      );
    });

    test('会话结束后不能再签发上传凭证', () async {
      final WebShareFixture f = await WebShareFixture.create();
      addTearDown(f.dispose);
      final String sessionId = await f.service.openSession(
        clientPubkey: kClientPubkey,
      );
      await f.service.revokeSession(sessionId);
      expect(
        () => f.service.acknowledgeAcceptedOffer(
          sessionId: sessionId,
          offerId: 'o',
          fileName: 'a.bin',
          declaredSize: 4,
        ),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.revoked,
          ),
        ),
      );
    });

    test('会话结束后拒绝写入分片', () async {
      final WebShareFixture f = await WebShareFixture.create();
      addTearDown(f.dispose);
      final String sessionId = await f.service.openSession(
        clientPubkey: kClientPubkey,
      );
      final UploadGrant grant = f.service.acknowledgeAcceptedOffer(
        sessionId: sessionId,
        offerId: 'o2',
        fileName: 'b.bin',
        declaredSize: 4,
      );
      await f.service.beginAuthorizedUpload(
        sessionId: sessionId,
        offerId: 'o2',
        fileName: 'b.bin',
        declaredSize: 4,
        token: grant.token,
        uploadId: 'up0002',
      );
      await f.service.revokeSession(sessionId);
      await expectLater(
        f.service.writeChunk(
          sessionId: sessionId,
          uploadId: 'up0002',
          offset: 0,
          data: List<int>.filled(4, 9),
        ),
        throwsA(isA<LanFileException>()),
      );
    });
  });

  group('宽限期回收', () {
    test('撤销后文件仍在；推过 10 分钟才真正从磁盘消失', () async {
      final WebShareFixture f = await WebShareFixture.create();
      addTearDown(f.dispose);
      final String sessionId = await f.service.openSession(
        clientPubkey: kClientPubkey,
      );
      final UploadGrant grant = f.service.acknowledgeAcceptedOffer(
        sessionId: sessionId,
        offerId: 'o3',
        fileName: 'c.bin',
        declaredSize: 16,
      );
      await f.service.beginAuthorizedUpload(
        sessionId: sessionId,
        offerId: 'o3',
        fileName: 'c.bin',
        declaredSize: 16,
        token: grant.token,
        uploadId: 'up0003',
      );
      await f.service.writeChunk(
        sessionId: sessionId,
        uploadId: 'up0003',
        offset: 0,
        data: List<int>.filled(16, 5),
      );

      // 撤销：链接失效，但文件还在。
      await f.service.revokeSession(sessionId);
      expect(await f.service.hasStagingResidue(sessionId), isTrue);
      expect(await f.stagingFileCount(sessionId), 1);

      // 宽限期内（9 分钟）：sweep 不应删。
      f.clock.advance(const Duration(minutes: 9));
      final SweepResult before = await f.service.sweep();
      expect(before.releasedSessions, isEmpty);
      expect(await f.stagingFileCount(sessionId), 1);

      // 过宽限期（再推 2 分钟，共 11 分钟）：文件必须真的消失。
      f.clock.advance(const Duration(minutes: 2));
      final SweepResult after = await f.service.sweep();
      expect(after.releasedSessions, contains(sessionId));
      expect(await f.service.hasStagingResidue(sessionId), isFalse);
      expect(await f.stagingFileCount(sessionId), 0);
    });

    test('sweep 幂等：重复跑不会重复释放', () async {
      final WebShareFixture f = await WebShareFixture.create();
      addTearDown(f.dispose);
      final String sessionId = await f.service.openSession(
        clientPubkey: kClientPubkey,
      );
      await f.service.revokeSession(sessionId);
      f.clock.advance(const Duration(minutes: 11));

      final SweepResult first = await f.service.sweep();
      expect(first.releasedSessions, contains(sessionId));
      final SweepResult second = await f.service.sweep();
      expect(second.releasedSessions, isEmpty);
    });
  });

  group('配额', () {
    test('超配额 → quotaExceeded(507)，且不创建文件', () async {
      // 配额压到 1KB，方便真触发。
      final WebShareFixture f = await WebShareFixture.create(quotaBytes: 1024);
      addTearDown(f.dispose);
      final String sessionId = await f.service.openSession(
        clientPubkey: kClientPubkey,
      );
      final UploadGrant grant = f.service.acknowledgeAcceptedOffer(
        sessionId: sessionId,
        offerId: 'o4',
        fileName: 'big.bin',
        declaredSize: 4096,
      );
      await expectLater(
        f.service.beginAuthorizedUpload(
          sessionId: sessionId,
          offerId: 'o4',
          fileName: 'big.bin',
          declaredSize: 4096,
          token: grant.token,
          uploadId: 'up0004',
        ),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.quotaExceeded,
          ),
        ),
      );
      // 被配额拒绝时也不该留下目录。
      expect(await f.stagingFileCount(sessionId), 0);
      expect(
        await Directory(
          '${f.stagingRoot.path}${Platform.pathSeparator}$sessionId',
        ).exists(),
        isFalse,
      );
    });

    test('配额是累计的：两次小上传超过总量也被拒', () async {
      final WebShareFixture f = await WebShareFixture.create(quotaBytes: 1024);
      addTearDown(f.dispose);
      final String sessionId = await f.service.openSession(
        clientPubkey: kClientPubkey,
      );
      // 第一次 600 字节：成功。
      final UploadGrant g1 = f.service.acknowledgeAcceptedOffer(
        sessionId: sessionId,
        offerId: 'o5',
        fileName: 'a1.bin',
        declaredSize: 600,
      );
      await f.service.beginAuthorizedUpload(
        sessionId: sessionId,
        offerId: 'o5',
        fileName: 'a1.bin',
        declaredSize: 600,
        token: g1.token,
        uploadId: 'up0005',
      );
      await f.service.writeChunk(
        sessionId: sessionId,
        uploadId: 'up0005',
        offset: 0,
        data: List<int>.filled(600, 1),
      );

      // 第二次 600 字节：累计 1200 > 1024，应被拒。
      final UploadGrant g2 = f.service.acknowledgeAcceptedOffer(
        sessionId: sessionId,
        offerId: 'o6',
        fileName: 'a2.bin',
        declaredSize: 600,
      );
      await expectLater(
        f.service.beginAuthorizedUpload(
          sessionId: sessionId,
          offerId: 'o6',
          fileName: 'a2.bin',
          declaredSize: 600,
          token: g2.token,
          uploadId: 'up0006',
        ),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.quotaExceeded,
          ),
        ),
      );
    });
  });

  group('路径安全', () {
    test('会话 id 含穿越字符被拒，不会写到临时区外', () async {
      final WebShareFixture f = await WebShareFixture.create();
      addTearDown(f.dispose);
      await expectLater(
        f.service.openSession(clientPubkey: kClientPubkey).then((_) {}),
        completes,
      );
      expect(
        () => f.staging.sessionDir('../../etc'),
        throwsA(isA<LanFileException>()),
      );
      expect(
        () => StagingArea.sanitizeFileName('../../evil.bin'),
        returnsNormally,
      );
      // 分隔符被替换成下划线，不可能逃出目录。
      final String safe = StagingArea.sanitizeFileName('../..\\evil.bin');
      expect(safe.contains('/'), isFalse);
      expect(safe.contains(String.fromCharCode(92)), isFalse);
    });
  });
}

OfferView _offer() => OfferView(
  id: 'offer-x',
  fromLabel: '网页访客',
  origin: OfferOrigin.webSession,
  files: <OfferViewFile>[const OfferViewFile(name: 'f.bin', size: 4)],
  sizeTotal: 4,
  createdAt: DateTime.utc(2026, 11, 4, 12),
  expireAt: DateTime.utc(2026, 11, 4, 12, 30),
  status: 'accepted',
);

FileRef _fakeRef(WebShareFixture f, String sessionId) =>
    LocalRef.root('${f.stagingRoot.path}${Platform.pathSeparator}$sessionId');