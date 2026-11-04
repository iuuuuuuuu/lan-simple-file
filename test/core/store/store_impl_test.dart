// SPDX-License-Identifier: GPL-3.0-only

/// 持久化层测试：全部用**真实临时 sqlite 文件**，不用 in-memory 替身。
///
/// 为什么不 mock：本任务的验收点就是「落盘后仍在」，
/// 内存库会把这个性质整个跳过，测了也说明不了问题。
library;

import 'dart:io';

// hide 掉 drift 与 matcher 的同名匹配器：isNull / isNotNull 两个库都有，
// 同时可见时 Dart 报 ambiguous_import。这里以 flutter_test 的 matcher 为准。
import 'package:drift/drift.dart' hide Column, Table, isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/store.dart';
import 'package:lan_simple_file/core/contracts/types.dart';
import 'package:lan_simple_file/core/store/database.dart';
import 'package:lan_simple_file/core/store/database_opener.dart';
import 'package:lan_simple_file/core/store/migrations.dart';
import 'package:lan_simple_file/core/store/store_impl.dart';
import 'package:lan_simple_file/core/store/tables.dart';

/// 合法 peerId：p_ + 恰好 13 位小写字母数字（PeerId 的正则 ^p_[a-z0-9]{13}$）。
///
/// 结构 = 固定 11 位 "7fk3m9x2a1" + 2 位后缀 = 13 位。
/// 后缀补齐到 2 位，避免调用方传 "00" 时不小心变成 14 位。
/// 注意：docs/plan.md 第 6.1 节示例 p_7fk3m9x2a1cd 的主体只有 12 位，
/// 与冻结契约的 ^p_[a-z0-9]{13}$ 不一致。契约优先，这里按 13 位构造。
PeerId _peer(String suffix) {
  const String base = '7fk3m9x2a1c'; // 11 位，+2 位后缀 = 13
  final String body = base + suffix.padLeft(2, '0').substring(0, 2);
  assert(body.length == 13, 'peerId body 必须是 13 位，实际 ${body.length}');
  return PeerId.parse('p_$body');
}

ShareId _shareId(String raw) => ShareId.parse(raw);

DeviceRecord _device({String name = 'YG', bool online = true}) {
  return DeviceRecord(
    peerId: _peer('00'),
    publicKey: Uint8List.fromList(List<int>.generate(32, (int i) => i)),
    name: name,
    avatarHash: 'sha256:ab12cd34ef56ab78',
    os: 'windows',
    firstSeen: DateTime.utc(2026, 11, 4, 1, 2, 3),
    lastSeen: DateTime.utc(2026, 11, 4, 4, 5, 6),
    online: online,
    isSelf: true,
    isGuest: false,
    note: 'note',
  );
}

ShareRecord _share(
  String id, {
  String displayName = '共享目录',
  bool enabled = true,
  DateTime? revokedAt,
  String? sessionId,
  bool isEphemeral = false,
}) {
  return ShareRecord(
    id: _shareId(id),
    kind: 'folder',
    rootKind: 'local',
    rootUri: 'D:/媒体',
    displayName: displayName,
    ownerPeerId: _peer('00'),
    createdAt: DateTime.utc(2026, 11, 4, 2, 0, 0),
    mode: ShareMode.lan,
    enabled: enabled,
    missing: false,
    isEphemeral: isEphemeral,
    expiresAt: DateTime.utc(2026, 11, 5, 2, 0, 0),
    passwordHash: null,
    groupId: null,
    maxSpeedKbps: 4096,
    revokedAt: revokedAt,
    sessionId: sessionId,
  );
}

MessageRecord _message(
  String id, {
  String threadId = 'th_1',
  required Hlc hlc,
  String body = 'hi',
}) {
  return MessageRecord(
    id: id,
    threadId: threadId,
    senderPeerId: _peer('00'),
    kind: MessageKind.text,
    hlc: hlc,
    ts: DateTime.utc(2026, 11, 4, 3, 0, 0),
    body: body,
    attachJson: '',
    sig: 'sig',
    revokedAt: null,
    revokeReason: null,
    editedAt: null,
  );
}

Hlc _hlc(int ms, int counter) => Hlc(millis: ms, counter: counter, origin: 'p_7fk3m9x2a1a0');

void main() {
  late Directory tempDir;
  late File dbFile;
  late LanFileStoreImpl store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lsf_store_test_');
    dbFile = File('${tempDir.path}${Platform.pathSeparator}test.sqlite');
    store = await LanFileStoreImpl.open(dbFile: dbFile);
  });

  tearDown(() async {
    await store.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('schema', () {
    test('建出全部表，且关键列存在（PRAGMA table_info）', () async {
      final AppDatabase db = store.database;
      final List<QueryRow> tables = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
          .get();
      final Set<String> names =
          tables.map((QueryRow r) => r.read<String>('name')).toSet();

      const List<String> expected = <String>[
        'device',
        'share',
        'share_item',
        'grant',
        'thread',
        'grp',
        'group_member',
        'group_key',
        'message',
        'attach',
        'offer',
        'transfer',
        'guest_session',
        'msg_seen',
        'peer_block',
        'settings',
      ];
      for (final String table in expected) {
        expect(names, contains(table), reason: '缺表 $table');
      }

      // share 表必须含计划要求的三列。
      final List<QueryRow> shareCols =
          await db.customSelect('PRAGMA table_info(share)').get();
      final Set<String> shareColNames =
          shareCols.map((QueryRow r) => r.read<String>('name')).toSet();
      expect(shareColNames, containsAll(<String>[
        'session_id',
        'is_ephemeral',
        'revoked_at',
      ]));

      // offer 表必须有独立的 origin 列（与契约 OfferRecord.origin 一一对应）。
      final List<QueryRow> offerCols =
          await db.customSelect('PRAGMA table_info(offer)').get();
      expect(
        offerCols.map((QueryRow r) => r.read<String>('name')).toSet(),
        contains('origin'),
        reason: 'origin 必须是真实存储列，不能只靠推导',
      );

      // share_item 的复合主键必须是 (share_id, item_key)。
      final List<QueryRow> itemCols =
          await db.customSelect('PRAGMA table_info(share_item)').get();
      final List<String> pkCols = itemCols
          .where((QueryRow r) => r.read<int>('pk') > 0)
          .map((QueryRow r) => r.read<String>('name'))
          .toList()
        ..sort();
      expect(pkCols, <String>['item_key', 'share_id']);
    });

    test('WAL 与外键已真实生效（读回 pragma 实际值）', () async {
      final AppDatabase db = store.database;
      final String journalMode = (await db
              .customSelect('PRAGMA journal_mode').getSingle())
          .read<String>('journal_mode');
      expect(journalMode.toLowerCase(), 'wal');

      final int foreignKeys = (await db
              .customSelect('PRAGMA foreign_keys').getSingle())
          .read<int>('foreign_keys');
      expect(foreignKeys, 1);

      // 断言 opener 的常量表与真正生效的设置一致，防止两边各自漂移。
      expect(
        kConnectionPragmas.any(
          (String p) => p.toLowerCase().contains('journal_mode'),
        ),
        isTrue,
      );
      // 注意：PRAGMA busy_timeout 返回的列名是 timeout，不是 busy_timeout。
      // 实测 {timeout: 5000}；写成 busy_timeout 会拿到 null 而误判为未设置。
      final int busyTimeout = (await db
              .customSelect('PRAGMA busy_timeout').getSingle())
          .read<int>('timeout');
      expect(busyTimeout, 5000);
    });

    test('schema 版本写入 user_version，等于 kSchemaVersion', () async {
      final int version = (await store.database
              .customSelect('PRAGMA user_version').getSingle())
          .read<int>('user_version');
      expect(version, kSchemaVersion);
    });
  });

  group('share upsert', () {
    test('两次同 id upsert 只留一条，且字段更新生效', () async {
      await store.upsertShare(_share('sh_001', displayName: '旧名字'));
      await store.upsertShare(_share('sh_001', displayName: '新名字'));

      final List<ShareRecord> all = await store.listShares();
      expect(all.length, 1);
      expect(all.single.displayName, '新名字');
      expect(all.single.maxSpeedKbps, 4096);

      final ShareRecord? found = await store.findShare(_shareId('sh_001'));
      expect(found, isNotNull);
      expect(found!.displayName, '新名字');
      // 与 _peer('00') 互相印证，而不是硬编码字符串（硬编码会随辅助函数漂移）。
      expect(found.ownerPeerId, _peer('00'));
    });

    test('listShares 按 owner 与 enabledOnly 过滤', () async {
      await store.upsertShare(_share('sh_a', enabled: true));
      await store.upsertShare(_share('sh_b', enabled: false));
      expect((await store.listShares()).length, 2);
      expect((await store.listShares(enabledOnly: true)).length, 1);
      expect((await store.listShares(owner: _peer('00'))).length, 2);
      expect(
        (await store.listShares(owner: PeerId.parse('p_zzzzzzzzzzzzz'))).length,
        0,
      );
    });

    test('markShareMissing 与 revokeShare 生效且幂等', () async {
      await store.upsertShare(_share('sh_m'));
      await store.markShareMissing(_shareId('sh_m'), missing: true);
      await store.markShareMissing(_shareId('sh_m'), missing: true);
      ShareRecord? found = await store.findShare(_shareId('sh_m'));
      expect(found!.missing, isTrue);
      expect(found.enabled, isTrue);

      final DateTime at = DateTime.utc(2026, 11, 4, 5, 0, 0);
      await store.revokeShare(_shareId('sh_m'), at: at);
      await store.revokeShare(_shareId('sh_m'), at: at);
      found = await store.findShare(_shareId('sh_m'));
      expect(found!.isRevoked, isTrue);
      expect(found.revokedAt, at);
      // 撤销后不应再出现在「启用中」的结果里。
      expect(await store.listShares(enabledOnly: true), isEmpty);
    });

    test('撤销不存在的分享不抛异常（幂等）', () async {
      await store.revokeShare(_shareId('sh_absent'), at: DateTime.utc(2026, 1, 1));
      await store.markShareMissing(_shareId('sh_absent'), missing: true);
      expect(await store.findShare(_shareId('sh_absent')), isNull);
    });
  });

  group('share_item', () {
    test('putItems 幂等，listItems 按 prefix 精确过滤', () async {
      await store.upsertShare(_share('sh_i'));
      await store.putItems(<ShareItemRecord>[
        ShareItemRecord(
          shareId: _shareId('sh_i'),
          itemKey: ItemKey('docs/a.txt'),
          size: 10,
          isDir: false,
        ),
        ShareItemRecord(
          shareId: _shareId('sh_i'),
          itemKey: ItemKey('docs/b.txt'),
          size: 20,
          isDir: false,
        ),
        ShareItemRecord(
          shareId: _shareId('sh_i'),
          itemKey: ItemKey('other/c.txt'),
          size: 30,
          isDir: false,
        ),
      ]);
      // 重写同样数据不得产生重复行，也不得抛异常。
      await store.putItems(<ShareItemRecord>[
        ShareItemRecord(
          shareId: _shareId('sh_i'),
          itemKey: ItemKey('docs/a.txt'),
          size: 99,
          isDir: false,
        ),
      ]);

      final List<ShareItemRecord> all = await store.listItems(_shareId('sh_i'));
      expect(all.length, 3);
      final ShareItemRecord a =
          all.firstWhere((ShareItemRecord r) => r.itemKey.value == 'docs/a.txt');
      expect(a.size, 99);

      final List<ShareItemRecord> docs =
          await store.listItems(_shareId('sh_i'), prefix: 'docs/');
      expect(docs.map((ShareItemRecord r) => r.itemKey.value).toList(),
          <String>['docs/a.txt', 'docs/b.txt']);

      // 大小写敏感：前缀匹配不得把 Other/ 也算进 other/。
      await store.putItems(<ShareItemRecord>[
        ShareItemRecord(
          shareId: _shareId('sh_i'),
          itemKey: ItemKey('OTHER/c.txt'),
          size: 40,
          isDir: false,
        ),
      ]);
      final List<ShareItemRecord> lower =
          await store.listItems(_shareId('sh_i'), prefix: 'other/');
      expect(lower.length, 1);
      expect(lower.single.itemKey.value, 'other/c.txt');
    });
  });

  group('messages', () {
    test('listMessages 排序正确，since 为 null 时全量', () async {
      await store.putMessage(_message('m3', hlc: _hlc(300, 0), body: 'c'));
      await store.putMessage(_message('m1', hlc: _hlc(100, 0), body: 'a'));
      await store.putMessage(_message('m2', hlc: _hlc(200, 0), body: 'b'));

      final List<MessageRecord> all =
          await store.listMessages('th_1', since: null, limit: -1);
      expect(all.map((MessageRecord m) => m.id).toList(),
          <String>['m1', 'm2', 'm3']);
      expect(all.first.hlc, _hlc(100, 0));
    });

    test('listMessages 的 since 为严格大于，边界正确', () async {
      await store.putMessage(_message('m1', hlc: _hlc(100, 0)));
      await store.putMessage(_message('m2', hlc: _hlc(200, 0)));
      await store.putMessage(_message('m3', hlc: _hlc(300, 0)));

      final List<MessageRecord> after200 =
          await store.listMessages('th_1', since: _hlc(200, 0), limit: -1);
      expect(after200.map((MessageRecord m) => m.id).toList(), <String>['m3']);

      final List<MessageRecord> after900 =
          await store.listMessages('th_1', since: _hlc(900, 0), limit: -1);
      expect(after900, isEmpty);
    });

    test('listMessages 的 limit 生效且 0/负数视为不限制', () async {
      for (int i = 1; i <= 5; i++) {
        await store.putMessage(_message('m$i', hlc: _hlc(100 * i, 0)));
      }
      expect((await store.listMessages('th_1', limit: 2)).length, 2);
      expect((await store.listMessages('th_1', limit: 0)).length, 5);
      expect((await store.listMessages('th_1', limit: -1)).length, 5);
    });

    test('空表 listMessages 返回空列表而不是异常', () async {
      expect(await store.listMessages('no_such_thread', limit: 10), isEmpty);
    });

    test('zeroPaddedHlc 定宽且可被 Hlc.parse 原样解析回来', () {
      final String small = zeroPaddedHlc(_hlc(9, 1));
      final String large = zeroPaddedHlc(_hlc(10, 1));
      // 定宽：小的字典序必须在前（裸字符串 '9' > '10' 会排反）。
      expect(small.compareTo(large), lessThan(0));
      expect(small.length, large.length);
      // 可逆：定宽不改变语义，解析回来还是原值。
      expect(Hlc.parse(small), _hlc(9, 1));
      expect(Hlc.parse(large), _hlc(10, 1));
    });

    test('同一毫秒不同 counter 的 HLC 排序仍正确（定宽编码验证）', () async {
      await store.putMessage(_message('c2', hlc: _hlc(1000, 2)));
      await store.putMessage(_message('c10', hlc: _hlc(1000, 10)));
      await store.putMessage(_message('c1', hlc: _hlc(1000, 1)));
      final List<MessageRecord> all =
          await store.listMessages('th_1', limit: -1);
      // 定宽编码下 counter 10 必须排在 2 之后，而不是按字符串排在前面。
      expect(all.map((MessageRecord m) => m.id).toList(),
          <String>['c1', 'c2', 'c10']);
    });

    test('revokeMessage 幂等并写入原因', () async {
      await store.putMessage(_message('m1', hlc: _hlc(100, 0)));
      final DateTime at = DateTime.utc(2026, 11, 4, 6, 0, 0);
      await store.revokeMessage('m1', at: at, reason: '误发');
      await store.revokeMessage('m1', at: at, reason: '误发');
      final MessageRecord m = (await store.listMessages('th_1', limit: -1)).single;
      expect(m.isRevoked, isTrue);
      expect(m.revokedAt, at);
      expect(m.revokeReason, '误发');
    });
  });

  group('device / settings', () {
    test('upsertDevice 幂等且能读回', () async {
      await store.upsertDevice(_device(name: '旧'));
      await store.upsertDevice(_device(name: '新', online: false));
      final List<DeviceRecord> all = await store.listDevices();
      expect(all.length, 1);
      expect(all.single.name, '新');
      expect(all.single.online, isFalse);
      expect(all.single.publicKey.length, 32);
    });

    test('getSetting 对缺失键返回 null，setSetting 幂等覆盖', () async {
      expect(await store.getSetting('theme'), isNull);
      await store.setSetting('theme', 'dark');
      await store.setSetting('theme', 'light');
      expect(await store.getSetting('theme'), 'light');
    });
  });

  group('批量与落盘', () {
    test('顺序写 100 条消息一条不丢', () async {
      for (int i = 0; i < 100; i++) {
        await store.putMessage(
          _message('bulk_$i', hlc: _hlc(1000 + i, 0), body: 'body$i'),
        );
      }
      final List<MessageRecord> all = await store.listMessages('th_1', limit: -1);
      expect(all.length, 100);
      expect(all.first.id, 'bulk_0');
      expect(all.last.id, 'bulk_99');
    });

    test('close 后 reopen，share/message/settings 数据仍在且字段一致', () async {
      await store.upsertShare(_share('sh_persist', displayName: '落盘验证'));
      await store.putMessage(_message('m_persist', hlc: _hlc(777, 3), body: '持久'));
      await store.setSetting('locale', 'zh-CN');
      await store.close();

      store = await LanFileStoreImpl.open(dbFile: dbFile);

      final ShareRecord? share = await store.findShare(_shareId('sh_persist'));
      expect(share, isNotNull);
      expect(share!.displayName, '落盘验证');
      expect(share.createdAt, DateTime.utc(2026, 11, 4, 2, 0, 0));
      expect(share.mode, ShareMode.lan);
      expect(share.maxSpeedKbps, 4096);

      final List<MessageRecord> msgs =
          await store.listMessages('th_1', limit: -1);
      expect(msgs.length, 1);
      expect(msgs.single.body, '持久');
      expect(msgs.single.hlc, _hlc(777, 3));

      expect(await store.getSetting('locale'), 'zh-CN');
    });

    test('库文件真实落盘（文件存在且非空）', () async {
      await store.setSetting('k', 'v');
      await store.close();
      expect(dbFile.existsSync(), isTrue);
      expect(dbFile.lengthSync(), greaterThan(0));
      store = await LanFileStoreImpl.open(dbFile: dbFile);
    });
  });

  group('offer / transfer / guest / thread', () {
    test('offer upsert 与待决策列表', () async {
      final OfferRecord pending = OfferRecord(
        id: 'of_1',
        origin: OfferOrigin.peer,
        toPeer: _peer('00'),
        filesJson: '[{"name":"a.txt","size":10}]',
        sizeTotal: 10,
        status: OfferStatusWire.pending,
        createdAt: DateTime.utc(2026, 11, 4, 7, 0, 0),
        expireAt: DateTime.utc(2026, 11, 4, 7, 30, 0),
        fromPeer: _peer('01'),
        fromSession: null,
        note: '请接收',
        decidedAt: null,
      );
      await store.putOffer(pending);
      await store.putOffer(pending);
      expect((await store.listPendingOffers(_peer('00'))).length, 1);

      await store.putOffer(OfferRecord(
        id: 'of_1',
        origin: OfferOrigin.peer,
        toPeer: _peer('00'),
        filesJson: pending.filesJson,
        sizeTotal: 10,
        status: OfferStatusWire.accepted,
        createdAt: pending.createdAt,
        expireAt: pending.expireAt,
        fromPeer: _peer('01'),
        fromSession: null,
        note: pending.note,
        decidedAt: DateTime.utc(2026, 11, 4, 7, 10, 0),
      ));
      expect(await store.listPendingOffers(_peer('00')), isEmpty);
      final OfferRecord? found = await store.findOffer('of_1');
      expect(found!.status, OfferStatusWire.accepted);
      expect(found.origin, OfferOrigin.peer);
    });

    // 以下两条是「origin 是一等列」的回归防线。
    // 旧实现按 from_session != null 推导 origin，两条都会红。
    test('origin=webSession 且 from_session=null，读回仍是 webSession（不靠推导）',
        () async {
      // 这正是会话撤销把 from_session 清空后的情形：
      // 旧实现会把这条读成 peer，属静默漂移。
      await store.putOffer(OfferRecord(
        id: 'of_web_null_session',
        origin: OfferOrigin.webSession,
        toPeer: _peer('00'),
        filesJson: '[]',
        sizeTotal: 0,
        status: OfferStatusWire.pending,
        createdAt: DateTime.utc(2026, 11, 4, 11, 0, 0),
        expireAt: DateTime.utc(2026, 11, 4, 11, 30, 0),
        fromPeer: null,
        fromSession: null,
        note: null,
        decidedAt: null,
      ));
      final OfferRecord? got = await store.findOffer('of_web_null_session');
      expect(got, isNotNull);
      expect(got!.origin, OfferOrigin.webSession,
          reason: 'origin 必须来自存储列，不能由 from_session 是否为空推导');
      expect(got.fromSession, isNull);
      // 仍是待决策，不受 origin 影响。
      expect((await store.listPendingOffers(_peer('00'))).length, 1);
    });

    test('origin=peer 且 from_session 非空，读回仍是 peer（边界）', () async {
      // 反向边界：节点来源但恰好带了会话 id（例如经宿主中继转发的节点 offer）。
      // 旧实现会把这条读成 webSession。
      await store.putOffer(OfferRecord(
        id: 'of_peer_with_session',
        origin: OfferOrigin.peer,
        toPeer: _peer('00'),
        filesJson: '[]',
        sizeTotal: 0,
        status: OfferStatusWire.pending,
        createdAt: DateTime.utc(2026, 11, 4, 12, 0, 0),
        expireAt: DateTime.utc(2026, 11, 4, 12, 30, 0),
        fromPeer: _peer('01'),
        fromSession: 'gs_relay',
        note: null,
        decidedAt: null,
      ));
      final OfferRecord? got = await store.findOffer('of_peer_with_session');
      expect(got, isNotNull);
      expect(got!.origin, OfferOrigin.peer,
          reason: 'from_session 非空不代表 origin 就是 webSession');
      expect(got.fromSession, 'gs_relay');
      expect(got.fromPeer, _peer('01'));
    });

    test('transfer 按状态过滤', () async {
      TransferRecord tr(String id, TransferStatus s) => TransferRecord(
            id: id,
            direction: TransferDirection.download,
            peerId: _peer('00'),
            shareId: _shareId('sh_001'),
            itemKey: ItemKey('docs/a.txt'),
            bytesTotal: 1000,
            bytesDone: s == TransferStatus.done ? 1000 : 100,
            status: s,
            createdAt: DateTime.utc(2026, 11, 4, 8, 0, 0),
            speedBps: 1024,
            finishedAt: null,
            err: null,
          );
      await store.putTransfer(tr('t1', TransferStatus.active));
      await store.putTransfer(tr('t2', TransferStatus.done));
      await store.putTransfer(tr('t2', TransferStatus.done));
      expect((await store.listTransfers()).length, 2);
      expect((await store.listTransfers(status: TransferStatus.done)).length, 1);
    });

    test('guest session 读写', () async {
      final GuestSessionRecord g = GuestSessionRecord(
        sessionId: 'gs_1',
        hostPeer: _peer('00'),
        pubkey: Uint8List.fromList(<int>[1, 2, 3]),
        createdAt: DateTime.utc(2026, 11, 4, 9, 0, 0),
        lastBeat: DateTime.utc(2026, 11, 4, 9, 0, 15),
        quotaBytes: 20 * 1024 * 1024 * 1024,
        usedBytes: 1024,
      );
      await store.putGuestSession(g);
      final GuestSessionRecord? found = await store.findGuestSession('gs_1');
      expect(found!.quotaBytes, 20 * 1024 * 1024 * 1024);
      expect(found.usedBytes, 1024);
      expect(await store.findGuestSession('nope'), isNull);
    });

    test('thread upsert 与 lastMsgHlc 往返', () async {
      final ThreadRecord t = ThreadRecord(
        id: 'th_1',
        kind: 'direct',
        title: 'YG',
        avatarHash: 'sha256:ab12cd34ef56ab78',
        unread: 3,
        muted: false,
        pinned: true,
        createdAt: DateTime.utc(2026, 11, 4, 10, 0, 0),
        peerId: _peer('00'),
        groupId: null,
        lastMsgHlc: _hlc(555, 7),
        lastMsgPreview: '最后一条',
        deletedAt: null,
      );
      await store.upsertThread(t);
      await store.upsertThread(t);
      final List<ThreadRecord> all = await store.listThreads();
      expect(all.length, 1);
      expect(all.single.lastMsgHlc, _hlc(555, 7));
      expect(all.single.unread, 3);
      expect(all.single.pinned, isTrue);
    });
  });
}
