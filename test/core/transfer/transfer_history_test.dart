// SPDX-License-Identifier: GPL-3.0-only
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/store/store_impl.dart';
import 'package:lan_simple_file/core/transfer/transfer_history.dart';

void main() {
  test(
    'concurrent records persist; removing history keeps files and active tasks',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'transfer-history-',
      );
      final file = await File('${directory.path}/report.txt')
          .writeAsString('keep');
      final db = File('${directory.path}/test.sqlite');
      var store = await LanFileStoreImpl.open(dbFile: db);
      var history = StoreTransferHistory(store);
      addTearDown(() async {
        await history.dispose();
        await store.close();
        await directory.delete(recursive: true);
      });
      await store.putTransfer(
        TransferRecord(
          id: 'active',
          direction: TransferDirection.download,
          peerId: PeerId.parse('p_aaaaaaaaaaaaa'),
          shareId: ShareId.parse('share_test'),
          itemKey: ItemKey.parse('report.txt'),
          bytesTotal: 10,
          bytesDone: 3,
          status: TransferStatus.active,
          createdAt: DateTime.utc(2026),
        ),
      );
      await Future.wait(
        List.generate(
          12,
          (index) => history.record(
            name: 'report-$index',
            direction: TransferDirection.download,
            status: 'external',
            localPath: file.path,
          ),
        ),
      );
      expect(await history.list(), hasLength(13));
      final removed = (await history.list()).first.id;
      await history.remove({removed, 'native-active'});
      await history.dispose();
      await store.close();
      store = await LanFileStoreImpl.open(dbFile: db);
      history = StoreTransferHistory(store);
      final entries = await history.list();
      expect(entries, hasLength(11));
      expect(entries.every((e) => e.status == 'external'), isTrue);
      expect(
        entries.any((e) => e.id == removed || e.id == 'native-active'),
        isFalse,
      );
      expect(
        (await store.listTransfers()).single.status,
        TransferStatus.active,
      );
      expect(await file.readAsString(), 'keep');
    },
  );
}
