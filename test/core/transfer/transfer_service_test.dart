// SPDX-License-Identifier: GPL-3.0-only

/// 端到端下载测试：真 HttpServer 提供 Range，真 HttpClient 拉取，真落盘比对。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/transfer/checksum.dart';
import 'package:lan_simple_file/core/transfer/partial_file.dart';
import 'package:lan_simple_file/core/transfer/transfer_service_impl.dart';

import 'support/range_test_server.dart';

const String kPeer = 'p_7fk3m9x2a1cdk';
const String kShare = 'share-abc123';

PeerId _peer() => PeerId.parse(kPeer);
ShareId _share() => ShareId.parse(kShare);
ItemKey _key([String v = 'dir/file.bin']) => ItemKey.parse(v);

String _sha256Of(Uint8List bytes) => sha256.convert(bytes).toString();

TransferServiceImpl _service(Uri url, {int chunkBytes = 256 * 1024}) =>
    TransferServiceImpl(
      resolver: StaticTargetResolver(url),
      chunkBytes: chunkBytes,
      retryBackoff: const Duration(milliseconds: 20),
    );

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lsf_transfer_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('下载', () {
    test('8MB 文件全量下载，落盘 sha256 与服务端一致', () async {
      const int size = 8 * 1024 * 1024;
      final RangeTestServer server = await RangeTestServer.start(size);
      final TransferServiceImpl service = _service(server.urlFor('f.bin'));
      addTearDown(() async {
        await service.dispose();
        await server.stop();
      });

      final TransferRecord record = await service.download(
        peer: _peer(),
        share: _share(),
        itemKey: _key(),
        targetDir: tempDir.path,
        fileName: 'out.bin',
        expectedChecksum: _sha256Of(server.payload),
        checksumAlgorithm: ChecksumAlgorithm.sha256,
      );

      expect(record.status, TransferStatus.done);
      expect(record.bytesTotal, size);
      expect(record.bytesDone, size);

      final File out = File('${tempDir.path}/out.bin');
      expect(await out.exists(), isTrue);
      expect(await out.length(), size);
      expect(_sha256Of(await out.readAsBytes()), _sha256Of(server.payload));
      // .part 与 .partmeta 都应被清理。
      expect(File('${out.path}.part').existsSync(), isFalse);
      expect(File('${out.path}.partmeta').existsSync(), isFalse);
    });

    test('分片走 Range 且并发不超过契约上限', () async {
      const int size = 2 * 1024 * 1024;
      final RangeTestServer server = await RangeTestServer.start(size);
      final TransferServiceImpl service =
          _service(server.urlFor('f.bin'), chunkBytes: 128 * 1024);
      addTearDown(() async {
        await service.dispose();
        await server.stop();
      });

      await service.download(
        peer: _peer(),
        share: _share(),
        itemKey: _key(),
        targetDir: tempDir.path,
        fileName: 'out.bin',
      );

      expect(server.rangeRequests, isNotEmpty);
      // 每次 Range 请求都不应超过分片大小。
      for (final RangeRequestLog log in server.rangeRequests) {
        final int len = log.end! - log.start! + 1;
        expect(len, lessThanOrEqualTo(128 * 1024));
      }
      expect(service.concurrency, LanFileConstants.downloadConcurrency);
    });

    test('空文件（0 字节）也能完成', () async {
      final RangeTestServer server = await RangeTestServer.start(0);
      final TransferServiceImpl service = _service(server.urlFor('empty.bin'));
      addTearDown(() async {
        await service.dispose();
        await server.stop();
      });

      final TransferRecord record = await service.download(
        peer: _peer(),
        share: _share(),
        itemKey: _key('empty.bin'),
        targetDir: tempDir.path,
        fileName: 'empty.bin',
      );
      expect(record.bytesTotal, 0);
      expect(record.status, TransferStatus.done);
      expect(await File('${tempDir.path}/empty.bin').length(), 0);
    });
  });

  group('续传', () {
    test('中途断开 → resume 只补缺口，不重下已完成区间', () async {
      const int size = 1024 * 1024;
      final RangeTestServer server = await RangeTestServer.start(size)
        ..breakAfterBytes = 100 * 1024; // 每个响应只给 100KB 就断
      final TransferServiceImpl service =
          _service(server.urlFor('f.bin'), chunkBytes: 256 * 1024);
      addTearDown(() async {
        await service.dispose();
        await server.stop();
      });

      // 第一次必然失败（每个分片都收不满）。
      await expectLater(
        service.download(
          peer: _peer(),
          share: _share(),
          itemKey: _key(),
          targetDir: tempDir.path,
          fileName: 'out.bin',
        ),
        throwsA(isA<LanFileException>()),
      );

      // 下载抛错后仍能通过 taskIds 找到这个任务。
      expect(service.taskIds, hasLength(1));
      final String id = service.taskIds.single;

      // 断点文件与元数据都应该还在。
      final File part = File('${tempDir.path}/out.bin.part');
      final File meta = File('${tempDir.path}/out.bin.partmeta');
      expect(part.existsSync(), isTrue);
      expect(meta.existsSync(), isTrue);

      final PartMeta? before = await PartialFile.peekMeta('${tempDir.path}/out.bin');
      expect(before, isNotNull);
      final int completedBefore = before!.completedRanges
          .fold<int>(0, (int sum, ByteInterval i) => sum + i.length);
      expect(completedBefore, 0, reason: '收不满的分片不应被记成已完成');

      // 恢复服务端，再 resume：应该只请求剩余部分。
      server.breakAfterBytes = null;
      server.requests.clear();

      final TransferRecord resumed = await service.resume(id);
      expect(resumed.status, TransferStatus.done);
      expect(
        _sha256Of(await File('${tempDir.path}/out.bin').readAsBytes()),
        _sha256Of(server.payload),
      );

      // 中断时一片都没写成功，所以续传要从头下完整 size；
      // 额外的 1 字节来自探测用的 Range: bytes=0-0。
      final int requestedAfter = server.totalRequestedBytes;
      expect(
        requestedAfter,
        size + 1,
        reason: '中断时零完成，续传应覆盖全部字节（+1 字节为探测请求）',
      );
    });

    test('部分完成后续传：只请求剩余字节', () async {
      const int size = 512 * 1024;
      final RangeTestServer server = await RangeTestServer.start(size);
      final TransferServiceImpl service =
          _service(server.urlFor('f.bin'), chunkBytes: 128 * 1024);
      addTearDown(() async {
        await service.dispose();
        await server.stop();
      });

      // 手工造一个「前半已完成」的断点。
      final PartialFile partial = await PartialFile.open(
        targetPath: '${tempDir.path}/out.bin',
        total: size,
        etag: server.etag,
      );
      await partial.writeAt(0, server.payload.sublist(0, size ~/ 2));
      await partial.flushMeta(algorithm: 'sha256');
      // 必须关句柄：Windows 上未释放的 .part 会让后续 rename/delete 直接失败。
      await partial.closeHandle();
      final PartMeta? seeded = await PartialFile.peekMeta('${tempDir.path}/out.bin');
      expect(seeded!.completedRanges, <ByteInterval>[ByteInterval(0, size ~/ 2)]);

      final TransferRecord record = await service.download(
        peer: _peer(),
        share: _share(),
        itemKey: _key(),
        targetDir: tempDir.path,
        fileName: 'out.bin',
        expectedChecksum: _sha256Of(server.payload),
        checksumAlgorithm: ChecksumAlgorithm.sha256,
      );
      expect(record.status, TransferStatus.done);

      // 服务端实际被请求的字节总数应约为后半段。
      expect(
        server.totalRequestedBytes,
        lessThanOrEqualTo(size),
        reason: '不应把已完成的前半段再下一遍',
      );
      final File out = File('${tempDir.path}/out.bin');
      expect(_sha256Of(await out.readAsBytes()), _sha256Of(server.payload));
    });

    test('etag 变化 → 丢弃旧断点从头下（不拼旧字节）', () async {
      const int size = 256 * 1024;
      final RangeTestServer server = await RangeTestServer.start(size);
      final TransferServiceImpl service =
          _service(server.urlFor('f.bin'), chunkBytes: 64 * 1024);
      addTearDown(() async {
        await service.dispose();
        await server.stop();
      });

      // 用旧 etag 造断点，但服务端内容已换成 v2（字节也换了）。
      final PartialFile stale = await PartialFile.open(
        targetPath: '${tempDir.path}/out.bin',
        total: size,
        etag: '"v-old"',
      );
      await stale.writeAt(0, Uint8List(size ~/ 2)); // 全是 0 的旧内容
      await stale.flushMeta(algorithm: 'sha256');
      await stale.closeHandle();

      server.etag = '"v2"';
      server.payload.setAll(0, RangeTestServer.patternFor(size));

      final TransferRecord record = await service.download(
        peer: _peer(),
        share: _share(),
        itemKey: _key(),
        targetDir: tempDir.path,
        fileName: 'out.bin',
        expectedChecksum: _sha256Of(server.payload),
        checksumAlgorithm: ChecksumAlgorithm.sha256,
      );
      expect(record.status, TransferStatus.done);

      final File out = File('${tempDir.path}/out.bin');
      expect(
        _sha256Of(await out.readAsBytes()),
        _sha256Of(server.payload),
        reason: 'etag 变了必须整份重下，不能保留旧断点的字节',
      );
    });
  });

  group('校验', () {
    test('损坏字节 → 抛 checksumMismatch', () async {
      const int size = 128 * 1024;
      final RangeTestServer server = await RangeTestServer.start(size)
        ..corruptPayload = true;
      final TransferServiceImpl service = _service(server.urlFor('f.bin'));
      addTearDown(() async {
        await service.dispose();
        await server.stop();
      });

      await expectLater(
        service.download(
          peer: _peer(),
          share: _share(),
          itemKey: _key(),
          targetDir: tempDir.path,
          fileName: 'out.bin',
          expectedChecksum: _sha256Of(server.payload),
          checksumAlgorithm: ChecksumAlgorithm.sha256,
        ),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.checksumMismatch,
          ),
        ),
      );

      // 校验失败不应把损坏文件 rename 成成品。
      expect(File('${tempDir.path}/out.bin').existsSync(), isFalse);
    });
  });
}