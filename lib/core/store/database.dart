// SPDX-License-Identifier: GPL-3.0-only

/// drift 数据库：schema v1 与迁移策略的挂载点。
///
/// 本文件只声明「库长什么样」（表清单、schemaVersion、migration）；
/// 打开方式与连接级 pragma 在 database_opener.dart；
/// 业务读写一律经 store_impl.dart 的 LanFileStore 暴露，禁止裸 DAO 穿透。
library;

import 'package:drift/drift.dart';

import '../contracts/store.dart';
// database.g.dart 是本 library 的 part，只能看到本文件的 import 集。
// Offers.origin 用 textEnum<OfferOrigin>()，而 OfferOrigin 声明在 types.dart，
// 因此这里必须显式 import；只靠 tables.dart 的 import 不会传递过来。
import '../contracts/types.dart';
import 'migrations.dart';
import 'tables.dart';

part 'database.g.dart';

/// 应用数据库。
///
/// 表清单见 tables.dart；表名与字段名对齐 docs/plan.md 第 5 节。
@DriftDatabase(
  tables: <Type>[
    Devices,
    Shares,
    ShareItems,
    Grants,
    Threads,
    Grps,
    GroupMembers,
    GroupKeys,
    Messages,
    Attachments,
    Offers,
    Transfers,
    GuestSessions,
    MsgSeens,
    PeerBlocks,
    Settings,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// [e] 通常是由 database_opener.dart 造出来的 NativeDatabase。
  AppDatabase(super.e);

  @override
  int get schemaVersion => kSchemaVersion;

  @override
  MigrationStrategy get migration => buildMigrationStrategy(this);
}
