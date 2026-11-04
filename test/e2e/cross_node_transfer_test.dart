// SPDX-License-Identifier: GPL-3.0-only

/// Lead 侧端到端：跨节点真实下载。
///
/// A 起服务并共享文件；B 用 TransferService + StoreTargetResolver 真的从 A 拉下来，
/// 校验 sha256 一致。这条打通「发现 -> 解析地址 -> Range 下载 -> 校验」整条链路。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/assembly.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/transfer/store_target_resolver.dart';
import 'package:lan_simple_file/core/transfer/transfer_service_impl.dart';

/// 用固定地址的 endpoints，模拟「发现层已经知道 A 在哪」。
final class _FixedEndpoints implements PeerEndpointSource {
  _FixedEndpoints(this.peer, this.host, this.port);

  final PeerId peer;
  final String host;
  final int port;

  @override
  Future<({String host, int port})?> findEndpoint(PeerId p) async =>
      p == peer ? (host: host, port: port) : null;
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lsf_xnode_');
    webAssetsFallbackDir = 'assets${Platform.pathSeparator}web';
  });
  tearDown(() {
    for (int i = 0; i < 8; i++) {
      try {
        if (tmp.existsSync()) {
          tmp.deleteSync(recursive: true);
        }
        return;
      } on FileSystemException {
        sleep(const Duration(milliseconds: 150));
      }
    }
  });

  test('跨节点真实下载：A 共享 -> B 拉到本地 -> 字节一致', () async {
    final AppServices a = await AppAssembler.assemble(
      dataDir: Directory('${tmp.path}${Platform.pathSeparator}a'),
      httpPortOverride: 0,
      udpPortOverride: 0,
      enableDiscovery: false,
      name: 'A',
    );
    try {
      final Directory root =
          Directory('${tmp.path}${Platform.pathSeparator}shared')
            ..createSync();
      // 1MB 随机内容，验证分片与校验
      final List<int> payload =
          List<int>.generate(1024 * 1024, (int i) => (i * 37 + 11) % 256);
      final File src =
          File('${root.path}${Platform.pathSeparator}blob.bin')
            ..writeAsBytesSync(payload);

      final ShareRecord share = await a.shares.create(
        CreateShareRequest(
          rootKind: ShareRootKind.localPath,
          rootUri: root.path,
          displayName: 'A 的分享',
          mode: ShareMode.lan,
        ),
      );

      // B 侧：直接用 A 的真实端口作为「已发现地址」。
      final PeerId aPeer = a.identity.peerId;
      final TransferServiceImpl transfer = TransferServiceImpl(
        resolver: StoreTargetResolver(
          endpoints: _FixedEndpoints(aPeer, '127.0.0.1', a.port),
        ),
      );

      final String targetDir = '${tmp.path}${Platform.pathSeparator}downloads';
      Directory(targetDir).createSync();

      final TransferRecord rec = await transfer.download(
        peer: aPeer,
        share: share.id,
        itemKey: ItemKey.parse('blob.bin'),
        targetDir: targetDir,
      );

      // download() 内部 await _drive(task)，返回时任务已经跑完，
      // 所以这里直接断言返回值，不要再订阅进度流（那时已错过全部推送）。
      expect(rec.status, TransferStatus.done,
          reason: 'download 返回即应完成，实际: ${rec.status.name}');
      expect(rec.bytesDone, rec.bytesTotal, reason: '完成态必须字节写满');
      expect(rec.bytesTotal, payload.length);

      // 落盘字节必须与源一致
      final File out =
          File('$targetDir${Platform.pathSeparator}blob.bin');
      expect(out.existsSync(), isTrue, reason: '成品文件必须存在');
      final List<int> got = out.readAsBytesSync();
      expect(got.length, payload.length, reason: '字节数一致');
      expect(got, equals(payload), reason: '逐字节一致');

      // 源文件未被改动
      expect(src.lengthSync(), payload.length);
    } finally {
      await a.stop();
    }
  });

  test('未知对端：下载必须立刻 providerOffline，不挂起', () async {
    final TransferServiceImpl transfer = TransferServiceImpl(
      resolver: StoreTargetResolver(
        endpoints: _FixedEndpoints(
          PeerId.parse('p_aaaaaaaaaaaaa'),
          '192.168.1.9',
          47778,
        ),
      ),
    );
    await expectLater(
      transfer.download(
        peer: PeerId.parse('p_zzzzzzzzzzzzz'),
        share: ShareId.parse('7Qm2xK'),
        itemKey: ItemKey.parse('a.txt'),
        targetDir: tmp.path,
      ),
      throwsA(
        isA<LanFileException>().having(
          (LanFileException e) => e.code,
          'code',
          LanFileErrorCode.providerOffline,
        ),
      ),
    );
  });
}