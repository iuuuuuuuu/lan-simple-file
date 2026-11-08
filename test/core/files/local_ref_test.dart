// SPDX-License-Identifier: GPL-3.0-only

/// LocalRef 与 LocalRefFactory 的行为测试：全部使用真实临时目录，无 mock。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/errors.dart';
import 'package:lan_simple_file/core/contracts/file_ref.dart';
import 'package:lan_simple_file/core/contracts/types.dart';
import 'package:lan_simple_file/core/files/local_ref.dart';
import 'package:lan_simple_file/core/files/local_ref_factory.dart';
import 'package:lan_simple_file/core/files/relative_path_codec.dart';
import 'package:path/path.dart' as p;

/// 把 [stream] 的分块拼成一条整字节流，顺带记录块数以便断言分块行为。
Future<List<int>> drain(
  Stream<List<int>> stream, {
  List<int>? chunkSizes,
}) async {
  final List<int> out = <int>[];
  await for (final List<int> chunk in stream) {
    chunkSizes?.add(chunk.length);
    out.addAll(chunk);
  }
  return out;
}

void main() {
  late Directory sandbox;
  late Directory rootDir;
  late String rootPath;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('lsf_localref_');
    rootDir = Directory(p.join(sandbox.path, 'root'))..createSync();
    rootPath = rootDir.path;
  });

  tearDown(() {
    if (sandbox.existsSync()) {
      sandbox.deleteSync(recursive: true);
    }
  });

  group('构造与越界闸门', () {
    test('root() 打开分享根本身', () async {
      final LocalRef ref = LocalRef.root(rootPath);
      expect(ref.itemKey.value, rootItemKey);
      expect(ref.isDirectory, isTrue);
      expect(await ref.exists(), isTrue);
      expect(await ref.length(), 0);
      expect(ref.displayName, 'root');
    });

    test('构造阶段就拒绝双点段', () {
      for (final String bad in <String>['..', '../../etc', 'a/../../b']) {
        expect(
          () => LocalRef(rootPath: rootPath, relativePath: bad),
          throwsA(
            isA<LanFileException>().having(
              (LanFileException e) => e.code,
              'code',
              LanFileErrorCode.invalidArgument,
            ),
          ),
          reason: '应拒绝：$bad',
        );
      }
    });

    test('构造阶段就拒绝绝对路径与盘符', () {
      for (final String bad in <String>[
        p.join(sandbox.path, 'other.txt'),
        'C:/Windows/system32',
        '//server/share/x',
      ]) {
        expect(
          () => LocalRef(rootPath: rootPath, relativePath: bad),
          throwsA(isA<LanFileException>()),
          reason: '应拒绝：$bad',
        );
      }
    });

    test('构造阶段就拒绝符号链接逃逸', () {
      final Directory outside = Directory(p.join(sandbox.path, 'outside'))
        ..createSync();
      File(p.join(outside.path, 'secret.txt')).writeAsStringSync('x');
      try {
        Link(p.join(rootPath, 'escape')).createSync(outside.path);
      } on FileSystemException {
        markTestSkipped('本机无法创建软链接');
        return;
      }
      expect(
        () => LocalRef(rootPath: rootPath, relativePath: 'escape/secret.txt'),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.invalidArgument,
          ),
        ),
      );
    });

    test('分享根必须是绝对路径', () {
      expect(
        () => LocalRef.root('relative/share'),
        throwsA(isA<LanFileException>()),
      );
    });
  });

  group('list 分页（3 层嵌套，真实目录）', () {
    /// 建 a/b/c 三层，每层放若干文件，返回全部叶子的 itemKey 集合。
    Set<String> buildTree(Directory base) {
      final Set<String> expected = <String>{};
      for (var i = 0; i < 7; i++) {
        final String name = 'f$i.txt';
        File(p.join(base.path, name)).writeAsStringSync('$i');
        expected.add(
          p
              .relative(p.join(base.path, name), from: rootPath)
              .replaceAll(r'\', '/'),
        );
      }
      final Directory l2 = Directory(p.join(base.path, 'layer2'))..createSync();
      for (var i = 0; i < 5; i++) {
        final String name = 'g$i.txt';
        File(p.join(l2.path, name)).writeAsStringSync('$i');
        expected.add(
          p
              .relative(p.join(l2.path, name), from: rootPath)
              .replaceAll(r'\', '/'),
        );
      }
      final Directory l3 = Directory(p.join(l2.path, 'layer3'))..createSync();
      for (var i = 0; i < 3; i++) {
        final String name = 'h$i.txt';
        File(p.join(l3.path, name)).writeAsStringSync('$i');
        expected.add(
          p
              .relative(p.join(l3.path, name), from: rootPath)
              .replaceAll(r'\', '/'),
        );
      }
      return expected;
    }

    test('逐层分页不重不漏', () async {
      final Set<String> expectedFiles = buildTree(rootDir);
      final LocalRef rootRef = LocalRef.root(rootPath);

      // 第一层：翻完所有页，断言恰好是 [layer2, f0..f6] 共 8 项。
      final List<FileEntry> level1 = <FileEntry>[];
      String? cursor;
      var pages = 0;
      do {
        final FileEntryPage page = await rootRef.list(cursor: cursor, limit: 3);
        level1.addAll(page.entries);
        cursor = page.nextCursor;
        pages++;
        expect(pages, lessThanOrEqualTo(10), reason: '分页应能终止');
      } while (cursor != null);
      expect(pages, 3, reason: '8 项 / 每页 3 项 = 3 页');
      expect(level1.length, 8);
      expect(level1.map((FileEntry e) => e.name).toList(), <String>[
        'layer2',
        'f0.txt',
        'f1.txt',
        'f2.txt',
        'f3.txt',
        'f4.txt',
        'f5.txt',
        'f6.txt',
      ], reason: '文件夹优先，同类按键升序');

      // 第二层与第三层：递归收集所有文件，和预期的集合严格相等。
      final Set<String> seen = <String>{};
      Future<void> walk(FileRef ref) async {
        String? c;
        do {
          final FileEntryPage page = await ref.list(cursor: c, limit: 2);
          for (final FileEntry e in page.entries) {
            if (e.isDirectory) {
              await walk(await ref.child(ItemKey.parse(e.itemKey.value)));
            } else {
              expect(
                seen.add(e.itemKey.value),
                isTrue,
                reason: '重复项：${e.itemKey.value}',
              );
            }
          }
          c = page.nextCursor;
        } while (c != null);
      }

      await walk(rootRef);
      expect(seen, expectedFiles);
      expect(seen.length, expectedFiles.length);
    });

    test('directory cursor survives deletion and crosses into files', () async {
      final removed = Directory(p.join(rootPath, 'y-folder'))..createSync();
      Directory(p.join(rootPath, 'z-folder')).createSync();
      File(p.join(rootPath, 'a.txt')).writeAsStringSync('a');
      final ref = LocalRef.root(rootPath);
      final first = await ref.list(limit: 1);
      expect(first.entries.single.name, 'y-folder');
      removed.deleteSync();
      final second = await ref.list(cursor: first.nextCursor, limit: 1);
      expect(second.entries.single.name, 'z-folder');
      final third = await ref.list(cursor: second.nextCursor, limit: 1);
      expect(third.entries.single.name, 'a.txt');
      expect(third.nextCursor, isNull);
    });

    test('cursor 恰好是上一页最后一条的 itemKey', () async {
      for (var i = 0; i < 5; i++) {
        File(p.join(rootPath, 'n$i')).writeAsStringSync('x');
      }
      final LocalRef rootRef = LocalRef.root(rootPath);
      final FileEntryPage first = await rootRef.list(limit: 2);
      expect(first.entries.length, 2);
      expect(first.nextCursor, first.entries.last.itemKey.value);
      final FileEntryPage second = await rootRef.list(
        cursor: first.nextCursor,
        limit: 2,
      );
      expect(second.entries.map((FileEntry e) => e.name).toList(), <String>[
        'n2',
        'n3',
      ]);
    });

    test('末页 nextCursor 为 null，hasMore 为 false', () async {
      File(p.join(rootPath, 'only.txt')).writeAsStringSync('x');
      final FileEntryPage page = await LocalRef.root(rootPath).list(limit: 10);
      expect(page.entries.length, 1);
      expect(page.nextCursor, isNull);
      expect(page.hasMore, isFalse);
    });

    test('limit 等于条目数时不出多余的下一页', () async {
      for (var i = 0; i < 3; i++) {
        File(p.join(rootPath, 'm$i')).writeAsStringSync('x');
      }
      final FileEntryPage page = await LocalRef.root(rootPath).list(limit: 3);
      expect(page.entries.length, 3);
      expect(page.nextCursor, isNull);
    });

    test('游标落在末尾之后返回空页而不是报错', () async {
      File(p.join(rootPath, 'z.txt')).writeAsStringSync('x');
      final FileEntryPage page = await LocalRef.root(rootPath)
          .list(cursor: 'z.txt', limit: 5);
      expect(page.entries, isEmpty);
      expect(page.nextCursor, isNull);
    });

    test('对文件调用 list 抛 invalidArgument', () async {
      final File f = File(p.join(rootPath, 'plain.txt'))
        ..writeAsStringSync('x');
      final LocalRef ref = LocalRef(
        rootPath: rootPath,
        relativePath: 'plain.txt',
      );
      expect(await ref.exists(), isTrue);
      await expectLater(
        ref.list(limit: 10),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.invalidArgument,
          ),
        ),
      );
      expect(f.existsSync(), isTrue);
    });

    test('limit <= 0 抛 invalidArgument', () async {
      await expectLater(
        LocalRef.root(rootPath).list(limit: 0),
        throwsA(isA<LanFileException>()),
      );
    });

    test('逃出 root 的 junction 不进入列表', () async {
      if (!Platform.isWindows) {
        markTestSkipped('仅 Windows 有 junction');
        return;
      }
      final Directory outside = Directory(p.join(sandbox.path, 'outside'))
        ..createSync();
      File(p.join(outside.path, 'secret.txt')).writeAsStringSync('x');
      File(p.join(rootPath, 'inside.txt')).writeAsStringSync('x');
      final ProcessResult pr = Process.runSync('cmd', <String>[
        '/c',
        'mklink',
        '/J',
        p.join(rootPath, 'junction'),
        outside.path,
      ]);
      expect(pr.exitCode, 0, reason: 'mklink /J 失败：${pr.stdout}${pr.stderr}');
      final FileEntryPage page = await LocalRef.root(rootPath).list(limit: 50);
      expect(page.entries.map((FileEntry e) => e.name).toList(), <String>[
        'inside.txt',
      ]);
    });
  });

  group('特殊文件名', () {
    test('中文名、空格名、超长名各一例', () async {
      final String longName = 'L' * 120 + '.txt';
      final List<String> names = <String>[
        '中文文件名.txt',
        '带 空格 的名字.txt',
        longName,
      ];
      for (final String n in names) {
        File(p.join(rootPath, n)).writeAsStringSync('content-of-$n');
      }
      final FileEntryPage page = await LocalRef.root(rootPath).list(limit: 50);
      final Map<String, FileEntry> byName = <String, FileEntry>{
        for (final FileEntry e in page.entries) e.name: e,
      };
      for (final String n in names) {
        expect(byName.containsKey(n), isTrue, reason: '列表里缺少：$n');
        final LocalRef ref = LocalRef(rootPath: rootPath, relativePath: n);
        expect(ref.displayName, n);
        expect(await ref.exists(), isTrue);
        expect(utf8.decode(await drain(ref.openRead())), 'content-of-$n');
        expect(byName[n]!.size, utf8.encode('content-of-$n').length);
      }
      // 超长名往返也要一致。
      expect(
        p.equals(
          toAbsolutePath(rootPath, ItemKey.parse(longName)),
          p.join(rootPath, longName),
        ),
        isTrue,
      );
    });

    test('深嵌套超长路径（> 260 字符）仍可列举与读取', () async {
      var deepPath = rootPath;
      for (var i = 0; i < 5; i++) {
        deepPath = p.join(deepPath, 'd' * 60);
      }
      final Directory deep = Directory(deepPath)..createSync(recursive: true);
      expect(deepPath.length, greaterThan(260));
      final File f = File(p.join(deep.path, 'deep.txt'))
        ..writeAsStringSync('deep-content');
      final String key = toItemKey(rootPath, f.path);
      final LocalRef ref = LocalRef(rootPath: rootPath, relativePath: key);
      expect(await ref.exists(), isTrue, reason: '长路径必须可访问：$deepPath');
      expect(await ref.length(), 'deep-content'.length);
      expect(utf8.decode(await drain(ref.openRead())), 'deep-content');
      // 摆到最深那层目录上再列举，验证「超长路径 + 目录列举」也走通。
      final List<String> segments = key.split('/');
      final String parentKey = segments.take(segments.length - 1).join('/');
      final LocalRef parentRef = LocalRef(
        rootPath: rootPath,
        relativePath: parentKey,
      );
      expect(parentRef.isDirectory, isTrue);
      final FileEntryPage page = await parentRef.list(limit: 5);
      expect(page.entries.single.name, 'deep.txt');
      expect(page.entries.single.itemKey.value, key);
      // 从该目录句柄拿子项句柄，走的是 root 内全量键坐标系。
      final FileRef childRef = await parentRef.child(
        ItemKey.parse(page.entries.single.itemKey.value),
      );
      expect(childRef.itemKey.value, key);
      expect(await childRef.exists(), isTrue);
    });
  });

  group('openRead 分片读取', () {
    test('10MB 文件分片拼接后 sha256 与原文件一致', () async {
      final File src = File(p.join(rootPath, 'big.bin'));
      final Random rnd = Random(20261104);
      // 逐块写，避免一次性申请 10MB 内存里的随机数生成开销。
      final IOSink sink = src.openWrite();
      final List<int> all = <int>[];
      var written = 0;
      while (written < 10 * 1024 * 1024) {
        final List<int> block = List<int>.generate(
          64 * 1024,
          (_) => rnd.nextInt(256),
        );
        sink.add(block);
        all.addAll(block);
        written += block.length;
      }
      await sink.flush();
      await sink.close();
      expect(await src.length(), 10 * 1024 * 1024);

      final String expected = sha256.convert(all).toString();
      expect(expected, sha256.convert(await src.readAsBytes()).toString());

      final LocalRef ref = LocalRef(
        rootPath: rootPath,
        relativePath: 'big.bin',
      );
      final List<int> chunkSizes = <int>[];
      final List<int> collected = await drain(
        ref.openRead(),
        chunkSizes: chunkSizes,
      );
      expect(collected.length, 10 * 1024 * 1024);
      expect(sha256.convert(collected).toString(), expected);
      // 块大小 256KB 起步：10MB 应被切成 40 块左右，而不是一次性读完。
      expect(chunkSizes.length, greaterThanOrEqualTo(40));
      expect(
        chunkSizes.every((int n) => n <= 256 * 1024),
        isTrue,
        reason: '单块不得超过 256KB：$chunkSizes.take(5)',
      );
    });

    test('start / endExclusive 切片与原文一致', () async {
      final List<int> payload = List<int>.generate(5000, (int i) => i % 256);
      File(p.join(rootPath, 'slice.bin')).writeAsBytesSync(payload);
      final LocalRef ref = LocalRef(
        rootPath: rootPath,
        relativePath: 'slice.bin',
      );

      expect(
        await drain(ref.openRead(start: 1000, endExclusive: 2000)),
        payload.sublist(1000, 2000),
      );
      expect(await drain(ref.openRead(start: 4999)), <int>[payload[4999]]);
      expect(await drain(ref.openRead(start: 5000)), isEmpty);
      expect(await drain(ref.openRead(endExclusive: 0)), isEmpty);
      expect(await drain(ref.openRead(start: 0, endExclusive: 5000)), payload);
    });

    test('越界读取抛 invalidArgument 而不是静默截断', () async {
      File(p.join(rootPath, 'small.bin'))
          .writeAsBytesSync(List<int>.filled(10, 7));
      final LocalRef ref = LocalRef(
        rootPath: rootPath,
        relativePath: 'small.bin',
      );

      Future<void> expectInvalid(Stream<List<int>> s, String reason) async {
        await expectLater(
          s,
          emitsError(
            isA<LanFileException>().having(
              (LanFileException e) => e.code,
              'code',
              LanFileErrorCode.invalidArgument,
            ),
          ),
          reason: reason,
        );
      }

      await expectInvalid(ref.openRead(start: 11), 'start 超出长度');
      await expectInvalid(ref.openRead(endExclusive: 11), 'end 超出长度');
      await expectInvalid(ref.openRead(start: -1), 'start 为负');
      await expectInvalid(
        ref.openRead(start: 5, endExclusive: 4),
        'end 小于 start',
      );
    });

    test('目录读取抛 invalidArgument', () async {
      final LocalRef ref = LocalRef(
        rootPath: rootPath,
        relativePath: rootItemKey,
      );
      await expectLater(ref.openRead(), emitsError(isA<LanFileException>()));
    });

    test('超过 4GiB 的偏移量不被截断（稀疏文件，不占真实磁盘）', () async {
      // 只在 NTFS 上稀疏分配，避免真的写 5GiB。
      if (!Platform.isWindows) {
        markTestSkipped('稀疏大文件用例只在 Windows/NTFS 上跑');
        return;
      }
      final File f = File(p.join(rootPath, 'sparse.bin'))..createSync();
      final RandomAccessFile raf = f.openSync(mode: FileMode.write);
      try {
        // Opening in write mode clears the sparse flag on Windows.
        final sparse = await Process.run('fsutil.exe', [
          'sparse',
          'setflag',
          f.path,
        ]);
        expect(sparse.exitCode, 0, reason: '${sparse.stdout}${sparse.stderr}');
        final attributes = await Process.run('powershell.exe', [
          '-NoProfile',
          '-NonInteractive',
          '-WindowStyle',
          'Hidden',
          '-Command',
          "[int][System.IO.File]::GetAttributes('${f.path.replaceAll("'", "''")}')",
        ]);
        expect(attributes.exitCode, 0, reason: '${attributes.stderr}');
        expect(int.parse(attributes.stdout.toString().trim()) & 512, 512);
        raf.truncateSync(5 * 1024 * 1024 * 1024 + 16);
        raf.setPositionSync(5 * 1024 * 1024 * 1024);
        raf.writeFromSync(<int>[1, 2, 3, 4, 5, 6, 7, 8]);
      } finally {
        raf.closeSync();
      }

      final LocalRef ref = LocalRef(
        rootPath: rootPath,
        relativePath: 'sparse.bin',
      );
      expect(await ref.length(), 5 * 1024 * 1024 * 1024 + 16);
      final List<int> tail = await drain(
        ref.openRead(
          start: 5 * 1024 * 1024 * 1024,
          endExclusive: 5 * 1024 * 1024 * 1024 + 8,
        ),
      );
      expect(tail, <int>[1, 2, 3, 4, 5, 6, 7, 8]);
      expect((await ref.fingerprint()).startsWith('5368709136-'), isTrue);
    });
  });

  group('exists / fingerprint / 元数据', () {
    test('不存在的文件 exists() 返回 false 且不抛', () async {
      final LocalRef ref = LocalRef(
        rootPath: rootPath,
        relativePath: 'nope.txt',
      );
      expect(await ref.exists(), isFalse);
      expect(await ref.lastModified(), isNull);
    });

    test('文件被删除后 exists() 转为 false', () async {
      final File f = File(p.join(rootPath, 'temp.txt'))..writeAsStringSync('x');
      final LocalRef ref = LocalRef(
        rootPath: rootPath,
        relativePath: 'temp.txt',
      );
      expect(await ref.exists(), isTrue);
      f.deleteSync();
      expect(await ref.exists(), isFalse);
    });

    test('fingerprint 形如 size-mtimeMs 且随内容变化', () async {
      final File f = File(p.join(rootPath, 'fp.bin'))
        ..writeAsStringSync('12345');
      final LocalRef ref = LocalRef(rootPath: rootPath, relativePath: 'fp.bin');
      final String fp1 = await ref.fingerprint();
      expect(
        RegExp(r'^\d+-\d+$').hasMatch(fp1),
        isTrue,
        reason: '格式应为 size-mtimeMs，实际 $fp1',
      );
      final List<String> parts = fp1.split('-');
      expect(parts.length, 2);
      expect(parts[0], '5');
      expect(int.parse(parts[1]), greaterThan(0));

      f.writeAsStringSync('1234567890');
      final String fp2 = await ref.fingerprint();
      expect(fp2.split('-')[0], '10');
      expect(fp1 != fp2, isTrue);
    });

    test('指纹中的 mtime 与 lastModified 一致', () async {
      File(p.join(rootPath, 'mt.bin')).writeAsStringSync('abc');
      final LocalRef ref = LocalRef(rootPath: rootPath, relativePath: 'mt.bin');
      final DateTime? mtime = await ref.lastModified();
      expect(mtime, isNotNull);
      expect(
        (await ref.fingerprint()).split('-')[1],
        mtime!.millisecondsSinceEpoch.toString(),
      );
    });

    test('toEntry 的 kind / size 正确', () async {
      File(p.join(rootPath, 'e.txt')).writeAsStringSync('abcd');
      Directory(p.join(rootPath, 'edir')).createSync();
      final FileEntry fileEntry = LocalRef(
        rootPath: rootPath,
        relativePath: 'e.txt',
      ).toEntry();
      expect(fileEntry.kind, EntryKind.file);
      expect(fileEntry.size, 4);
      expect(fileEntry.name, 'e.txt');
      final FileEntry dirEntry = LocalRef(
        rootPath: rootPath,
        relativePath: 'edir',
      ).toEntry();
      expect(dirEntry.kind, EntryKind.directory);
      expect(dirEntry.isDirectory, isTrue);
    });
  });

  group('child 与 itemKey 坐标系', () {
    test('child 接受 root 内全量键', () async {
      Directory(p.join(rootPath, 'sub')).createSync();
      File(p.join(rootPath, 'sub', 'x.txt')).writeAsStringSync('x');
      final LocalRef parent = LocalRef(rootPath: rootPath, relativePath: 'sub');
      final FileRef kid = await parent.child(ItemKey.parse('sub/x.txt'));
      expect(kid.itemKey.value, 'sub/x.txt');
      expect(await kid.exists(), isTrue);
    });

    test('child 只按根锚定键解析：相对名不会被拼到父节点之后', () async {
      Directory(p.join(rootPath, 'sub2')).createSync();
      File(p.join(rootPath, 'sub2', 'y.txt')).writeAsStringSync('y');
      final LocalRef parent = LocalRef(
        rootPath: rootPath,
        relativePath: 'sub2',
      );
      // 契约规定 childKey 的坐标系只有「根锚定完整键」一种。
      // 因此传 'y.txt' 等于在根下找 y.txt，而不是 sub2/y.txt。
      final FileRef kid = await parent.child(ItemKey.parse('y.txt'));
      expect(kid.itemKey.value, 'y.txt');
      expect(await kid.exists(), isFalse, reason: '根下没有 y.txt，只有 sub2/y.txt');
      // 传根锚定完整键才拿得到子项。
      final FileRef realKid = await parent.child(ItemKey.parse('sub2/y.txt'));
      expect(realKid.itemKey.value, 'sub2/y.txt');
      expect(await realKid.exists(), isTrue);
    });

    test('child 越界抛 invalidArgument', () async {
      final LocalRef parent = LocalRef(
        rootPath: rootPath,
        relativePath: rootItemKey,
      );
      await expectLater(
        parent.child(ItemKey.parse('../escape.txt')),
        throwsA(isA<LanFileException>()),
      );
    });
  });

  group('LocalRefFactory', () {
    const LocalRefFactory factory = LocalRefFactory();

    test('rootKind 是 localPath', () {
      expect(factory.rootKind, ShareRootKind.localPath);
    });

    test('openRoot 打开存在的目录，缺失时抛 notFound', () async {
      final FileRef ref = await factory.openRoot(rootPath);
      expect(ref.itemKey.value, rootItemKey);
      expect(await ref.exists(), isTrue);
      await expectLater(
        factory.openRoot(p.join(sandbox.path, 'missing')),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.notFound,
          ),
        ),
      );
    });

    test('resolve 正常项与缺失项的错误码', () async {
      File(p.join(rootPath, 'r.txt')).writeAsStringSync('x');
      final FileRef ref = await factory.resolve(
        rootPath,
        ItemKey.parse('r.txt'),
      );
      expect(await ref.exists(), isTrue);
      await expectLater(
        factory.resolve(rootPath, ItemKey.parse('absent.txt')),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.notFound,
          ),
        ),
      );
      await expectLater(
        factory.resolve(rootPath, ItemKey.parse('../../etc/passwd')),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.invalidArgument,
          ),
        ),
      );
    });

    test('canRead 正常/缺失/非目录', () async {
      expect(await factory.canRead(rootPath), isTrue);
      expect(await factory.canRead(p.join(sandbox.path, 'missing')), isFalse);
      final File f = File(p.join(sandbox.path, 'file.txt'))
        ..writeAsStringSync('x');
      expect(await factory.canRead(f.path), isFalse);
    });
  });

  group('委托给契约的一致性', () {
    test('LocalRef 满足 FileRef 的全部成员', () {
      final FileRef ref = LocalRef.root(rootPath);
      // 这些调用只要不抛就说明签名与契约一致。
      expect(ref.itemKey.value, isNotEmpty);
      expect(ref.displayName, isNotEmpty);
      ref.toEntry();
    });
  });
}
