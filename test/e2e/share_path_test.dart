// SPDX-License-Identifier: GPL-3.0-only

/// Lead 侧验收：拖入建共享背后的 sharePath 必须真的能建出来。
///
/// 用户实测报的是「已创建 0 个共享，1 个失败」，根因是 handler 从未注入。
/// 这条盯的是注入后真正的建共享路径：文件 -> kind=file（root 为其父目录）、
/// 目录 -> kind=folder。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/assembly.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lsf_sharepath_');
  });
  tearDown(() {
    for (int i = 0; i < 8; i++) {
      try {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        sleep(const Duration(milliseconds: 150));
      }
    }
  });

  Future<AppServices> boot(String suffix) => AppAssembler.assemble(
    dataDir: Directory('${tmp.path}${Platform.pathSeparator}$suffix'),
    httpPortOverride: 0,
    udpPortOverride: 0,
    enableDiscovery: false,
  );

  test('拖入单文件：建成 kind=file，root 保存完整源路径', () async {
    final AppServices s = await boot('a');
    try {
      final File f = File('${tmp.path}${Platform.pathSeparator}照片.jpg')
        ..writeAsBytesSync(<int>[1, 2, 3, 4, 5]);

      final ShareRecord rec = await s.sharePath(f.path);
      expect(rec.kind, 'file');
      expect(rec.displayName, '照片.jpg');
      expect(rec.rootUri, f.path, reason: '源路径独立保存，修改分享名称后仍指向原文件');
      expect(rec.enabled, isTrue);
      expect(rec.missing, isFalse);
    } finally {
      await s.stop();
    }
  });

  test('拖入目录：建成 kind=folder，root 是它自己', () async {
    final AppServices s = await boot('b');
    try {
      final Directory d = Directory('${tmp.path}${Platform.pathSeparator}素材')
        ..createSync();
      File('${d.path}${Platform.pathSeparator}a.txt').writeAsStringSync('x');

      final ShareRecord rec = await s.sharePath(d.path);
      expect(rec.kind, 'folder');
      expect(rec.displayName, '素材');
      expect(rec.rootUri, d.path);
    } finally {
      await s.stop();
    }
  });

  test('不存在的路径必须抛 notFound（不是静默成功）', () async {
    final AppServices s = await boot('c');
    try {
      await expectLater(
        s.sharePath('${tmp.path}${Platform.pathSeparator}不存在.txt'),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.notFound,
          ),
        ),
      );
    } finally {
      await s.stop();
    }
  });

  test('建完的分享会出现在 listMine 里（UI 列表能看到）', () async {
    final AppServices s = await boot('d');
    try {
      final File f = File('${tmp.path}${Platform.pathSeparator}x.bin')
        ..writeAsStringSync('data');
      final ShareRecord rec = await s.sharePath(f.path);
      final List<ShareRecord> mine = await s.shares.listMine();
      expect(mine.map((ShareRecord r) => r.id.value), contains(rec.id.value));
    } finally {
      await s.stop();
    }
  });
}
