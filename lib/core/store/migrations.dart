// SPDX-License-Identifier: GPL-3.0-only

/// schema 版本与迁移策略：v1 建表；v2 起在 onUpgrade 里追加步骤。
///
/// 迁移必须能在「已经跑过一半」的库上安全重跑：每个 upgrade 分支都要可重入。
library;

import 'package:drift/drift.dart';

import 'database.dart';

/// 当前 schema 版本。改动 tables.dart 的结构必须同时递增此值并补 upgrade 步骤。
const int kSchemaVersion = 1;

/// 构造迁移策略。
///
/// pragma（WAL / foreign_keys / busy_timeout）不在这里设置，统一交给
/// database_opener.dart 里 NativeDatabase 的 setup 回调：
/// 那时连接刚打开、事务尚未开始，journal_mode 才会真正生效。
/// 具体实测依据见 store_impl_test.dart 中 PRAGMA 断言用例。
MigrationStrategy buildMigrationStrategy(AppDatabase db) {
  return MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      // v1 是首个版本，没有更早的线上版本需要升级。
      // 后续版本在此按 from 分派，例如：
      //   if (from < 2) {
      //     await m.addColumn(db.shares, db.shares.someColumn);
      //   }
    },
  );
}
