// SPDX-License-Identifier: GPL-3.0-only

/// Lead 侧验证：deletedBy 必须真落到列里并读回。
///
/// 这条来自 ui-dev 的真实往返探针（ROUND_TRIP_OK=false），
/// 补列与映射后由 Lead 独立复验，避免「改完就说好了」。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/store/store_impl.dart';

void main() {
  late Directory tmp;
  late File dbFile;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lsf_deleted_by_');
    dbFile = File('${tmp.path}${Platform.pathSeparator}app.sqlite');
  });
  tearDown(() {
    for (int i = 0; i < 5; i++) {
      try {
        if (tmp.existsSync()) {
          tmp.deleteSync(recursive: true);
        }
        return;
      } on FileSystemException {
        sleep(const Duration(milliseconds: 100));
      }
    }
  });

  final PeerId owner = PeerId.parse('p_7fk3m9x2a1c02');
  final PeerId sender = PeerId.parse('p_kzdvvj2umnduy');

  MessageRecord msg({PeerId? deletedBy, DateTime? revokedAt}) =>
      MessageRecord(
        id: '${sender.value}:1',
        threadId: 'g_abc',
        senderPeerId: sender,
        kind: MessageKind.text,
        hlc: const Hlc(millis: 1767225600000, counter: 0, origin: 'p_kzdvvj2umnduy'),
        ts: DateTime.utc(2026, 11, 4, 7, 0, 0),
        body: '被群主删掉的这条',
        attachJson: '{}',
        sig: 'sig',
        deletedBy: deletedBy,
        revokedAt: revokedAt,
      );

  test('deletedBy 真落列：写群主身份 -> 读回一致（不是 null）', () async {
    final LanFileStore store = await LanFileStoreImpl.open(dbFile: dbFile);
    await store.putMessage(msg(deletedBy: owner, revokedAt: DateTime.utc(2026, 11, 4, 8)));
    final List<MessageRecord> list = await store.listMessages('g_abc', limit: -1);
    expect(list.length, 1);
    expect(list.single.deletedBy, isNotNull, reason: '这正是 ui-dev 探针报的静默丢失');
    expect(list.single.deletedBy!.value, owner.value);
    await store.close();
  });

  test('deletedBy 为 null 时读回也是 null（本人删除的语义）', () async {
    final LanFileStore store = await LanFileStoreImpl.open(dbFile: dbFile);
    await store.putMessage(msg());
    final List<MessageRecord> list = await store.listMessages('g_abc', limit: -1);
    expect(list.single.deletedBy, isNull);
    await store.close();
  });

  test('deletedBy 跨 close/reopen 仍在（真列才有的性质）', () async {
    final LanFileStore a = await LanFileStoreImpl.open(dbFile: dbFile);
    await a.putMessage(msg(deletedBy: owner, revokedAt: DateTime.utc(2026, 11, 4, 8)));
    await a.close();

    final LanFileStore b = await LanFileStoreImpl.open(dbFile: dbFile);
    final List<MessageRecord> list = await b.listMessages('g_abc', limit: -1);
    expect(list.single.deletedBy, isNotNull);
    expect(list.single.deletedBy!.value, owner.value);
    await b.close();
  });
}
