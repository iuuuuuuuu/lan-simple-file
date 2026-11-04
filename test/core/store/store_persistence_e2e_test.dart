// SPDX-License-Identifier: GPL-3.0-only

/// 端到端落盘验证：完全按 Lead 描述的验收脚本走一遍。
///
/// 与 store_impl_test.dart 的区别：这里不共享 setUp 的 store 实例，
/// 每个阶段都独立 open，模拟「应用重启」而不是「同一个对象反复用」。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/store.dart';
import 'package:lan_simple_file/core/contracts/types.dart';
import 'package:lan_simple_file/core/store/store_impl.dart';

PeerId _peer01() => PeerId.parse('p_7fk3m9x2a1c01');

void main() {
  test('end-to-end: open(真实临时文件) -> 写 share -> close -> reopen -> 数据仍在', () async {
    final Directory dir =
        await Directory.systemTemp.createTemp('lsf_e2e_store_');
    final File dbFile =
        File('${dir.path}${Platform.pathSeparator}lan.sqlite');
    final ShareId shareId = ShareId.parse('sh_e2e01');

    try {
      // ---- 阶段 1：写入 ----
      final LanFileStoreImpl first =
          await LanFileStoreImpl.open(dbFile: dbFile);
      expect(dbFile.existsSync(), isTrue, reason: 'open 必须真的建出库文件');
      await first.upsertShare(
        ShareRecord(
          id: shareId,
          kind: 'folder',
          rootKind: 'local',
          rootUri: r'D:\共享\照片',
          displayName: '家庭照片',
          ownerPeerId: _peer01(),
          createdAt: DateTime.utc(2026, 11, 4, 12, 34, 56),
          mode: ShareMode.password,
          enabled: true,
          missing: false,
          isEphemeral: false,
          passwordHash: 'argon2id:v19:m65536',
          sessionId: 'gs_e2e',
          maxSpeedKbps: null,
        ),
      );
      await first.setSetting('display_name', 'YG');
      await first.close();

      // ---- 阶段 2：重开，逐字段比对 ----
      final LanFileStoreImpl second =
          await LanFileStoreImpl.open(dbFile: dbFile);
      final ShareRecord? got = await second.findShare(shareId);
      expect(got, isNotNull, reason: 'close+reopen 后 share 必须还在');
      expect(got!.id, shareId);
      expect(got.displayName, '家庭照片');
      expect(got.rootUri, r'D:\共享\照片');
      expect(got.ownerPeerId, _peer01());
      expect(got.createdAt, DateTime.utc(2026, 11, 4, 12, 34, 56));
      expect(got.mode, ShareMode.password);
      expect(got.passwordHash, 'argon2id:v19:m65536');
      expect(got.sessionId, 'gs_e2e');
      expect(got.isEphemeral, isFalse);
      expect(got.enabled, isTrue);
      expect(got.maxSpeedKbps, isNull);
      expect(await second.getSetting('display_name'), 'YG');
      await second.close();
    } finally {
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
    }
  });
}