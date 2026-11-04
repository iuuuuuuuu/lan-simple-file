// SPDX-License-Identifier: GPL-3.0-only

/// share_guard 与 index_scanner 的单元测试。
///
/// 全部走真实临时目录；符号链接 / junction 逃逸用真实文件系统构造。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/errors.dart';
import 'package:lan_simple_file/core/contracts/file_ref.dart';
import 'package:lan_simple_file/core/contracts/store.dart';
import 'package:lan_simple_file/core/contracts/types.dart';
import 'package:lan_simple_file/core/files/local_ref.dart';
import 'package:lan_simple_file/core/files/local_ref_factory.dart';
import 'package:lan_simple_file/core/shares/index_scanner.dart';
import 'package:lan_simple_file/core/shares/share_guard.dart';
import 'package:lan_simple_file/core/store/store_impl.dart';
import 'package:path/path.dart' as p;

void expectInvalidArgument(void Function() body, String reason) {
  try {
    body();
  } on LanFileException catch (e) {
    expect(
      e.code,
      LanFileErrorCode.invalidArgument,
      reason: '$reason：期望 invalidArgument，实际 ${e.code.name}',
    );
    return;
  }
  fail('$reason：期望抛 LanFileException(invalidArgument)，实际没有抛');
}

void main() {
  const ShareGuard guard = ShareGuard();
  late Directory sandbox;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('lsf_guard_');
  });

  tearDown(() {
    if (sandbox.existsSync()) {
      sandbox.deleteSync(recursive: true);
    }
  });

  group('ShareGuard.normalizeRoot', () {
    test('桌面绝对路径通过并规范化', () {
      final String normalized = guard.normalizeRoot(
        kind: ShareRootKind.localPath,
        rootUri: p.join(sandbox.path, 'a', 'b', '..', 'c'),
      );
      expect(
        p.equals(normalized, p.join(sandbox.path, 'a', 'c')),
        isTrue,
        reason: '应归一化点段：$normalized',
      );
    });

    test('桌面相对路径被拒', () {
      for (final String bad in <String>['shared', '..', r'..\..\windows']) {
        expectInvalidArgument(
          () => guard.normalizeRoot(
            kind: ShareRootKind.localPath,
            rootUri: bad,
          ),
          '相对分享根 $bad',
        );
      }
    });

    test('空分享根被拒', () {
      expectInvalidArgument(
        () => guard.normalizeRoot(
          kind: ShareRootKind.localPath,
          rootUri: '   ',
        ),
        '空分享根',
      );
    });

    test('SAF 树 URI 通过，非 content scheme 被拒', () {
      const String tree =
          'content://com.android.externalstorage.documents/tree/primary%3ADCIM';
      expect(
        guard.normalizeRoot(kind: ShareRootKind.safTree, rootUri: tree),
        tree,
      );
      expectInvalidArgument(
        () => guard.normalizeRoot(
          kind: ShareRootKind.safTree,
          rootUri: 'file:///sdcard/DCIM',
        ),
        'SAF 用 file://',
      );
      expectInvalidArgument(
        () => guard.normalizeRoot(
          kind: ShareRootKind.safTree,
          rootUri: 'content://x/../escape',
        ),
        'SAF 含双点段',
      );
    });

    test('mediaStore 明确不支持', () {
      expect(
        () => guard.normalizeRoot(
          kind: ShareRootKind.mediaStore,
          rootUri: 'content://media/external/images',
        ),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.unsupported,
          ),
        ),
      );
    });
  });

  group('ShareGuard.rejectEscapingRelative', () {
    test('四种穿越写法全部被拒', () {
      for (final String bad in <String>[
        '..',
        '../x',
        r'..\x',
        r'a\..\..\b',
        '/abs',
        'C:/x',
        '//server/share/x',
      ]) {
        expectInvalidArgument(
          () => guard.rejectEscapingRelative(bad),
          '越界写法 $bad',
        );
      }
    });

    test('正常键（含中文与空格）通过', () {
      guard.rejectEscapingRelative('中文 目录/文件.txt');
      guard.rejectEscapingRelative('a/b/c.txt');
    });

    test('空键被拒', () {
      expectInvalidArgument(() => guard.rejectEscapingRelative(''), '空键');
    });
  });

  group('ShareGuard.normalizeItemKey', () {
    test('桌面：符号链接逃逸被拒', () {
      final Directory outside = Directory(p.join(sandbox.path, 'outside'))
        ..createSync();
      final Directory root = Directory(p.join(sandbox.path, 'root'))
        ..createSync();
      try {
        Link(p.join(root.path, 'escape')).createSync(outside.path);
      } on FileSystemException {
        markTestSkipped('本机无法创建软链接（缺少 SeCreateSymbolicLinkPrivilege）');
        return;
      }
      expectInvalidArgument(
        () => guard.normalizeItemKey(
          kind: ShareRootKind.localPath,
          rootUri: root.path,
          itemKey: ItemKey.parse('escape/inner.txt'),
        ),
        '符号链接逃逸',
      );
    });

    test('桌面：junction 逃逸被拒', () {
      if (!Platform.isWindows) {
        markTestSkipped('仅 Windows 有 junction');
        return;
      }
      final Directory outside = Directory(p.join(sandbox.path, 'outside'))
        ..createSync();
      final Directory root = Directory(p.join(sandbox.path, 'root'))
        ..createSync();
      final ProcessResult pr = Process.runSync('cmd', <String>[
        '/c',
        'mklink',
        '/J',
        p.join(root.path, 'junction'),
        outside.path,
      ]);
      expect(
        pr.exitCode,
        0,
        reason: 'mklink /J 失败：${pr.stdout}${pr.stderr}',
      );
      expectInvalidArgument(
        () => guard.normalizeItemKey(
          kind: ShareRootKind.localPath,
          rootUri: root.path,
          itemKey: ItemKey.parse('junction/secret.txt'),
        ),
        'junction 逃逸',
      );
    });

    test('桌面：正常键通过', () {
      final Directory root = Directory(p.join(sandbox.path, 'root2'))
        ..createSync();
      File(p.join(root.path, 'a.txt')).writeAsStringSync('x');
      expect(
        guard.normalizeItemKey(
          kind: ShareRootKind.localPath,
          rootUri: root.path,
          itemKey: ItemKey.parse('a.txt'),
        ),
        'a.txt',
      );
    });
  });

  group('ShareGuard.canRead', () {
    test('可读返回 true，缺失返回 false', () async {
      final Directory root = Directory(p.join(sandbox.path, 'readable'))
        ..createSync();
      expect(
        await guard.canRead(
          const LocalRefFactory(),
          ShareRootKind.localPath,
          root.path,
        ),
        isTrue,
      );
      expect(
        await guard.canRead(
          const LocalRefFactory(),
          ShareRootKind.localPath,
          p.join(sandbox.path, 'absent'),
        ),
        isFalse,
      );
    });
  });

  group('IndexScanner', () {
    late LanFileStoreImpl store;
    late ShareId shareId;

    setUp(() async {
      store = await LanFileStoreImpl.open(
        dbFile: File(p.join(sandbox.path, 'scan.db')),
      );
      shareId = ShareId.parse('scan-0001');
      // share_item 对 share 有真实外键约束，扫之前必须先有分享记录——
      // 这与生产路径一致：create 永远先 upsertShare 再排后台首扫。
      await store.upsertShare(
        ShareRecord(
          id: shareId,
          kind: 'folder',
          rootKind: ShareRootKind.localPath.name,
          rootUri: p.join(sandbox.path, 'tree'),
          displayName: '扫描测试',
          ownerPeerId: PeerId.parse('p_aaaaaaaaaaaaa'),
          createdAt: DateTime.utc(2026, 1, 1),
          mode: ShareMode.lan,
          enabled: true,
          missing: false,
          isEphemeral: false,
        ),
      );
    });

    tearDown(() async {
      await store.close();
    });

    test('扫真实三层树，条目数与目录数正确', () async {
      final Directory root = Directory(p.join(sandbox.path, 'tree'))
        ..createSync();
      File(p.join(root.path, 'a.txt')).writeAsStringSync('12345');
      final Directory d1 = Directory(p.join(root.path, 'd1'))..createSync();
      File(p.join(d1.path, 'b.txt')).writeAsStringSync('xx');
      final Directory d2 = Directory(p.join(d1.path, 'd2'))..createSync();
      File(p.join(d2.path, 'c.txt')).writeAsStringSync('z');

      final IndexScanner scanner = IndexScanner(store: store);
      final ScanResult result = await scanner.scan(
        shareId: shareId,
        root: LocalRef.root(root.path),
      );

      expect(result.directoriesVisited, 3, reason: '根 + d1 + d2');
      expect(result.itemsIndexed, 5, reason: 'a.txt, d1, b.txt, d2, c.txt');
      expect(result.truncated, isFalse);
      expect(result.failures, 0);

      final List<ShareItemRecord> items = await store.listItems(shareId);
      expect(items.length, 5);
      final ShareItemRecord dirRow = items.firstWhere(
        (ShareItemRecord r) => r.itemKey.value == 'd1',
      );
      expect(dirRow.isDir, isTrue);
      final ShareItemRecord fileRow = items.firstWhere(
        (ShareItemRecord r) => r.itemKey.value == 'a.txt',
      );
      expect(fileRow.size, 5);
      expect(fileRow.isDir, isFalse);
    });

    test('maxItems 上限会置 truncated 且不超写', () async {
      final Directory root = Directory(p.join(sandbox.path, 'many'))
        ..createSync();
      for (var i = 0; i < 20; i++) {
        File(p.join(root.path, 'n$i.txt')).writeAsStringSync('x');
      }
      final IndexScanner scanner = IndexScanner(store: store, maxItems: 7);
      final ScanResult result = await scanner.scan(
        shareId: shareId,
        root: LocalRef.root(root.path),
      );
      expect(result.truncated, isTrue);
      expect(result.itemsIndexed, 7);
      expect((await store.listItems(shareId)).length, 7);
    });

    test('batchSize=1 时也能写全（分批落盘无误）', () async {
      final Directory root = Directory(p.join(sandbox.path, 'batch'))
        ..createSync();
      for (var i = 0; i < 9; i++) {
        File(p.join(root.path, 'b$i.txt')).writeAsStringSync('x');
      }
      final IndexScanner scanner = IndexScanner(store: store, batchSize: 1);
      final ScanResult result = await scanner.scan(
        shareId: shareId,
        root: LocalRef.root(root.path),
      );
      expect(result.itemsIndexed, 9);
      expect((await store.listItems(shareId)).length, 9);
    });

    test('重复扫描幂等：同 share 扫两次仍只有一份', () async {
      final Directory root = Directory(p.join(sandbox.path, 'idem'))
        ..createSync();
      File(p.join(root.path, 'x.txt')).writeAsStringSync('x');
      final IndexScanner scanner = IndexScanner(store: store);
      await scanner.scan(shareId: shareId, root: LocalRef.root(root.path));
      await scanner.scan(shareId: shareId, root: LocalRef.root(root.path));
      expect((await store.listItems(shareId)).length, 1);
    });
  });
}