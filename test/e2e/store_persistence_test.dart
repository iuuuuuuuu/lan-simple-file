// SPDX-License-Identifier: GPL-3.0-only

/// M0 端到端验收（第二部分）：持久化层真实落盘与重启存活。
///
/// 这条不做则 M0 过不了：store 的单测在它自己的夹具里跑绿，
/// 但只有 Lead 从外部按契约调用，才能证明 LanFileStore 这个门面真的可用。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/store/store_impl.dart';

void main() {
  late Directory tmp;
  late File dbFile;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lsf_store_e2e_');
    dbFile = File('${tmp.path}${Platform.pathSeparator}app.sqlite');
  });

  tearDown(() {
    if (tmp.existsSync()) {
      tmp.deleteSync(recursive: true);
    }
  });

  ShareRecord share({required String id, required String name, int? speed}) =>
      ShareRecord(
        id: ShareId.parse(id),
        kind: 'folder',
        rootKind: 'localPath',
        rootUri: 'D:/shared/photos',
        displayName: name,
        ownerPeerId: PeerId.parse('p_kzdvvj2umnduy'),
        createdAt: DateTime.utc(2026, 11, 4, 7, 0, 0),
        mode: ShareMode.token,
        enabled: true,
        missing: false,
        isEphemeral: false,
        maxSpeedKbps: speed,
      );

  test('真实落盘：写入 share -> close -> reopen -> 数据仍在且字段一致', () async {
    final LanFileStore first = await LanFileStoreImpl.open(dbFile: dbFile);
    await first.upsertShare(share(id: '7Qm2xK', name: '相册', speed: 8000));
    await first.setSetting('theme', 'dark');
    await first.close();

    expect(dbFile.existsSync(), isTrue);
    expect(dbFile.lengthSync(), greaterThan(0));

    final LanFileStore second = await LanFileStoreImpl.open(dbFile: dbFile);
    final ShareRecord? loaded = await second.findShare(ShareId.parse('7Qm2xK'));
    expect(loaded, isNotNull);
    expect(loaded!.displayName, '相册');
    expect(loaded.rootUri, 'D:/shared/photos');
    expect(loaded.mode, ShareMode.token);
    expect(loaded.enabled, isTrue);
    expect(loaded.maxSpeedKbps, 8000);
    expect(loaded.ownerPeerId.value, 'p_kzdvvj2umnduy');
    expect(loaded.createdAt.toUtc(), DateTime.utc(2026, 11, 4, 7, 0, 0));
    expect(await second.getSetting('theme'), 'dark');
    await second.close();
  });

  test('upsert 幂等：同 id 写两次只留一条，且字段更新生效', () async {
    final LanFileStore store = await LanFileStoreImpl.open(dbFile: dbFile);
    await store.upsertShare(share(id: 'abc123', name: '旧名字'));
    await store.upsertShare(share(id: 'abc123', name: '新名字', speed: 1024));
    final List<ShareRecord> all = await store.listShares();
    expect(all.length, 1);
    expect(all.single.displayName, '新名字');
    expect(all.single.maxSpeedKbps, 1024);
    await store.close();
  });

  test('revokeShare 后仍可查到 revokedAt（撤销要可查，不能整条消失）', () async {
    final LanFileStore store = await LanFileStoreImpl.open(dbFile: dbFile);
    await store.upsertShare(share(id: 'r3voke', name: '待撤销'));
    final DateTime at = DateTime.utc(2026, 11, 4, 8, 0, 0);
    await store.revokeShare(ShareId.parse('r3voke'), at: at);
    final ShareRecord? rec = await store.findShare(ShareId.parse('r3voke'));
    expect(rec, isNotNull);
    expect(rec!.isRevoked, isTrue);
    expect(rec.revokedAt!.toUtc(), at);
    await store.close();
  });

  test('消息幂等：同 id 写两次不重复，字段往返正确', () async {
    final LanFileStore store = await LanFileStoreImpl.open(dbFile: dbFile);
    final PeerId sender = PeerId.parse('p_kzdvvj2umnduy');
    final String thread = 'd_${sender.value}';
    final MessageRecord msg = MessageRecord(
      id: '${sender.value}:1',
      threadId: thread,
      senderPeerId: sender,
      kind: MessageKind.text,
      hlc: Hlc(millis: 1767225600000, counter: 0, origin: sender.value),
      ts: DateTime.utc(2026, 11, 4, 7, 0, 0),
      body: '你好',
      attachJson: '{}',
      sig: 'sig',
    );
    await store.putMessage(msg);
    await store.putMessage(msg);
    final List<MessageRecord> list = await store.listMessages(thread, limit: 10);
    expect(list.length, 1);
    expect(list.single.body, '你好');
    expect(list.single.kind, MessageKind.text);
    await store.close();
  });

  test('settings 跨 reopen 持久（应用设置不能丢）', () async {
    final LanFileStore a = await LanFileStoreImpl.open(dbFile: dbFile);
    await a.setSetting('theme', 'dark');
    await a.setSetting('download_dir', 'D:/Downloads');
    await a.close();

    final LanFileStore b = await LanFileStoreImpl.open(dbFile: dbFile);
    expect(await b.getSetting('theme'), 'dark');
    expect(await b.getSetting('download_dir'), 'D:/Downloads');
    expect(await b.getSetting('not_set_key'), isNull);
    await b.close();
  });
}
