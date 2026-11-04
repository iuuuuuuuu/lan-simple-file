// SPDX-License-Identifier: GPL-3.0-only

/// 库文件定位与打开方式：把「文件路径 -> QueryExecutor」这一步与业务隔开。
///
/// 分开的理由：
/// - [defaultDatabaseFile] 依赖 path_provider（Flutter 平台通道），只有应用启动能用；
/// - [openExecutor] 只吃 dart:io 的 File，单元测试可以直接用临时文件，
///   不需要任何平台通道。LanFileStoreImpl.open 走的是后者。
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 库文件名。
const String kDatabaseFileName = 'lan_simple_file.sqlite';

/// 连接级 pragma。
///
/// WAL 必须在事务外设置，因此这些语句放在 NativeDatabase 的 setup 回调里，
/// 而不是 MigrationStrategy.beforeOpen（后者在事务内，journal_mode 会静默失效）。
///
/// 各条目的作用：
/// - journal_mode=WAL：计划第 4 节要求；读写并发不互斥，崩溃恢复更快。
/// - foreign_keys=ON：SQLite 默认关闭外键，不打开则 share_item/grant 的级联删除形同虚设。
/// - busy_timeout：多连接争锁时等待而不是立刻抛 SQLITE_BUSY。
const List<String> kConnectionPragmas = <String>[
  'PRAGMA journal_mode = WAL',
  'PRAGMA foreign_keys = ON',
  'PRAGMA busy_timeout = 5000',
];

/// 应用数据目录下的库文件；只在真实应用启动时调用。
Future<File> defaultDatabaseFile() async {
  final Directory dir = await getApplicationSupportDirectory();
  return File(p.join(dir.path, kDatabaseFileName));
}

/// 把真实文件包装成 drift 执行器（当前 isolate）。
///
/// 测试优先用这个：不跨 isolate，断言与异常都直观。
QueryExecutor openExecutor(File dbFile) {
  return NativeDatabase(
    dbFile,
    // 回调参数类型由 drift 的 DatabaseSetup 从上下文推断，
    // 无需显式 import package:sqlite3（它不是直接依赖）。
    setup: (database) {
      for (final String pragma in kConnectionPragmas) {
        database.execute(pragma);
      }
    },
  );
}

/// 同上，但库跑在后台 isolate；应用启动时用这个，避免 IO 阻塞 UI 线程。
QueryExecutor openBackgroundExecutor(File dbFile) {
  return NativeDatabase.createInBackground(
    dbFile,
    setup: (database) {
      for (final String pragma in kConnectionPragmas) {
        database.execute(pragma);
      }
    },
  );
}
