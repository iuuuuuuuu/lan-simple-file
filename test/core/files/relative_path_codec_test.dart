// SPDX-License-Identifier: GPL-3.0-only

/// relative_path_codec 的门禁测试：四种穿越变体必须全部被拒。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/errors.dart';
import 'package:lan_simple_file/core/contracts/types.dart';
import 'package:lan_simple_file/core/files/relative_path_codec.dart';
import 'package:path/path.dart' as p;

/// 美元符：用来拼 Windows 备用数据流路径，避免在源码里写出难辨认的转义。
const String _dollar = r'$';

/// 断言 [body] 抛 invalidArgument 的 [LanFileException]。
void expectInvalidArgument(void Function() body, String reason) {
  try {
    body();
  } on LanFileException catch (e) {
    expect(
      e.code,
      LanFileErrorCode.invalidArgument,
      reason: '$reason：错误码应为 invalidArgument，实际 ${e.code.name}',
    );
    return;
  }
  fail('$reason：期望抛 LanFileException(invalidArgument)，实际没有抛');
}

void main() {
  late Directory sandbox;
  late Directory root;
  late Directory outside;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('lsf_codec_');
    root = Directory(p.join(sandbox.path, 'root'))..createSync();
    outside = Directory(p.join(sandbox.path, 'outside'))..createSync();
    File(p.join(outside.path, 'secret.txt')).writeAsStringSync('top-secret');
  });

  tearDown(() {
    if (sandbox.existsSync()) {
      sandbox.deleteSync(recursive: true);
    }
  });

  group('toItemKey 正常路径', () {
    test('根自身映射成 rootItemKey', () {
      expect(toItemKey(root.path, root.path), rootItemKey);
    });

    test('多层嵌套转成 POSIX 分隔的相对键', () {
      final Directory deep = Directory(
        p.join(root.path, 'a', 'b', 'c'),
      )..createSync(recursive: true);
      final File f = File(p.join(deep.path, 'x.txt'))..writeAsStringSync('x');
      expect(toItemKey(root.path, f.path), 'a/b/c/x.txt');
    });

    test('中文名与空格名保持原样', () {
      final File f = File(p.join(root.path, '中文 名字.txt'))
        ..writeAsStringSync('x');
      expect(toItemKey(root.path, f.path), '中文 名字.txt');
    });

    test('接受的绝对路径带扩展长度前缀也能解析', () {
      final File f = File(p.join(root.path, 'p.txt'))..writeAsStringSync('x');
      expect(toItemKey(root.path, toIoPath(f.path)), 'p.txt');
    });
  });

  group('toItemKey 越界拒绝', () {
    test('兄弟目录越界', () {
      expectInvalidArgument(
        () => toItemKey(root.path, p.join(outside.path, 'secret.txt')),
        'toItemKey 兄弟目录',
      );
    });

    test('点段形式越界', () {
      expectInvalidArgument(
        () =>
            toItemKey(root.path, p.join(root.path, '..', 'outside', 'secret.txt')),
        'toItemKey 点段越界',
      );
    });

    test('相对路径直接拒绝', () {
      expectInvalidArgument(
        () => toItemKey(root.path, 'a.txt'),
        'toItemKey 相对路径',
      );
      expectInvalidArgument(
        () => toItemKey(root.path, p.join('..', '..', 'windows', 'system32')),
        'toItemKey 相对穿越',
      );
    });

    test('分享根不是绝对路径时拒绝', () {
      expectInvalidArgument(
        () => normalizeRootPath('shared'),
        'normalizeRootPath 相对',
      );
      expectInvalidArgument(
        () => normalizeRootPath(p.join('..', 'shared')),
        'normalizeRootPath 穿越',
      );
    });
  });

  group('toAbsolutePath 四种穿越变体', () {
    test('变体 1：反斜杠双点段', () {
      expectInvalidArgument(
        () => toAbsolutePath(
          root.path,
          ItemKey.parse(r'..\..\windows\system32'),
        ),
        'toAbsolutePath 反斜杠双点',
      );
      expectInvalidArgument(
        () => toAbsolutePath(root.path, ItemKey.parse(r'a\..\..\escape.txt')),
        'toAbsolutePath 夹心双点',
      );
    });

    test('变体 2：正斜杠双点段', () {
      expectInvalidArgument(
        () => toAbsolutePath(root.path, ItemKey.parse('../../etc/passwd')),
        'toAbsolutePath 正斜杠双点',
      );
      expectInvalidArgument(
        () => toAbsolutePath(root.path, ItemKey.parse('a/../../escape.txt')),
        'toAbsolutePath 夹心正斜杠双点',
      );
    });

    test('变体 3：绝对路径与盘符', () {
      expectInvalidArgument(
        () => toAbsolutePath(
          root.path,
          ItemKey.parse(p.join(outside.path, 'secret.txt')),
        ),
        'toAbsolutePath 绝对路径',
      );
      expectInvalidArgument(
        () => toAbsolutePath(root.path, ItemKey.parse('C:/Windows/system32')),
        'toAbsolutePath 盘符',
      );
      expectInvalidArgument(
        () => toAbsolutePath(root.path, ItemKey.parse(r'\\server\share\x')),
        'toAbsolutePath UNC',
      );
    });

    test('变体 4：符号链接逃逸', () {
      final String linkPath = p.join(root.path, 'escape');
      try {
        Link(linkPath).createSync(outside.path);
      } on FileSystemException {
        // Windows 未开启开发者模式时会拒绝创建软链接；如实标记跳过，不伪造通过。
        markTestSkipped('本机无法创建软链接（缺少 SeCreateSymbolicLinkPrivilege）');
        return;
      }
      expectInvalidArgument(
        () => toAbsolutePath(root.path, ItemKey.parse('escape/secret.txt')),
        'toAbsolutePath 符号链接逃逸',
      );
      expectInvalidArgument(
        () => toAbsolutePath(root.path, ItemKey.parse('escape')),
        'toAbsolutePath 符号链接本身',
      );
      // 宿主的原件仍然可读，证明只是被闸门挡住，不是文件不存在。
      expect(File(p.join(outside.path, 'secret.txt')).existsSync(), isTrue);
    });

    test('junction 逃逸（Windows 目录联接）', () {
      if (!Platform.isWindows) {
        markTestSkipped('仅 Windows 有 junction');
        return;
      }
      final String linkPath = p.join(root.path, 'junction');
      final ProcessResult pr = Process.runSync('cmd', <String>[
        '/c',
        'mklink',
        '/J',
        linkPath,
        outside.path,
      ]);
      expect(
        pr.exitCode,
        0,
        reason: 'mklink /J 失败：${pr.stdout}${pr.stderr}',
      );
      expectInvalidArgument(
        () => toAbsolutePath(root.path, ItemKey.parse('junction/secret.txt')),
        'toAbsolutePath junction 逃逸',
      );
    });
  });

  group('toAbsolutePath 正常路径', () {
    test('rootItemKey 解析回分享根本身', () {
      expect(
        p.equals(
          toAbsolutePath(root.path, ItemKey.parse(rootItemKey)),
          root.path,
        ),
        isTrue,
      );
    });

    test('中文与空格名的往返一致', () {
      final File f = File(p.join(root.path, '目录 一', '文件 二.txt'))
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
      final String key = toItemKey(root.path, f.path);
      expect(key, '目录 一/文件 二.txt');
      expect(
        p.equals(toAbsolutePath(root.path, ItemKey.parse(key)), f.path),
        isTrue,
      );
    });

    test('引导点段被归一化', () {
      expect(
        p.equals(
          toAbsolutePath(root.path, ItemKey.parse('./a/./b.txt')),
          p.join(root.path, 'a', 'b.txt'),
        ),
        isTrue,
      );
    });
  });

  group('isInside 纯判定', () {
    test('root 内、root 自身、root 外', () {
      expect(isInside(root.path, root.path), isTrue);
      expect(isInside(root.path, p.join(root.path, 'a', 'b.txt')), isTrue);
      expect(isInside(root.path, outside.path), isFalse);
      expect(isInside(root.path, p.join(outside.path, 'secret.txt')), isFalse);
    });

    test('兄弟前缀不算在内（share 与 share-other）', () {
      final Directory sibling = Directory('${root.path}-other')..createSync();
      expect(isInside(root.path, p.join(sibling.path, 'x.txt')), isFalse);
    });

    test('不抛异常：非法入参一律 false', () {
      expect(isInside('shared', p.join(root.path, 'a.txt')), isFalse);
      expect(isInside(root.path, 'a.txt'), isFalse);
      expect(isInside('', ''), isFalse);
    });

    test('符号链接指向 root 之外时判 false', () {
      final String linkPath = p.join(root.path, 'out');
      try {
        Link(linkPath).createSync(outside.path);
      } on FileSystemException {
        markTestSkipped('本机无法创建软链接（缺少 SeCreateSymbolicLinkPrivilege）');
        return;
      }
      expect(isInside(root.path, linkPath), isFalse);
      expect(isInside(root.path, p.join(linkPath, 'secret.txt')), isFalse);
    });
  });

  group('itemKey 规范化与拼接', () {
    test('空串与单点归一成 rootItemKey', () {
      expect(normalizeItemKey(''), rootItemKey);
      expect(normalizeItemKey('.'), rootItemKey);
      expect(normalizeItemKey('./'), rootItemKey);
    });

    test('反斜杠统一成斜杠', () {
      expect(normalizeItemKey(r'a\b\c.txt'), 'a/b/c.txt');
    });

    test('joinItemKey 在 root 上退化为子键', () {
      expect(joinItemKey(rootItemKey, 'a/b.txt'), 'a/b.txt');
      expect(joinItemKey('a', 'b.txt'), 'a/b.txt');
      expect(joinItemKey('a', ''), 'a');
    });

    test('joinItemKey 拒绝越界子键', () {
      expectInvalidArgument(() => joinItemKey('a', '..'), 'joinItemKey 双点');
      expectInvalidArgument(() => joinItemKey('a', '../../x'), 'joinItemKey 穿越');
    });

    test('控制字符与 Windows 数据流被拒', () {
      expectInvalidArgument(
        () => normalizeItemKey('a\u0000b'),
        'itemKey 控制字符',
      );
      if (Platform.isWindows) {
        expectInvalidArgument(
          () => normalizeItemKey('a.txt::${_dollar}DATA'),
          'itemKey 数据流',
        );
      }
    });
  });

  group('toIoPath / stripExtendedPrefix', () {
    test('Windows 上加前缀，strip 后还原', () {
      if (!Platform.isWindows) {
        markTestSkipped('扩展长度前缀只在 Windows 上存在');
        return;
      }
      final String ioPath = toIoPath(root.path);
      expect(
        ioPath.startsWith(r'\\?\'),
        isTrue,
        reason: '应加扩展长度前缀：$ioPath',
      );
      expect(p.equals(stripExtendedPrefix(ioPath), root.path), isTrue);
    });

    test('非绝对路径拒绝', () {
      if (!Platform.isWindows) {
        markTestSkipped('扩展长度前缀只在 Windows 上存在');
        return;
      }
      expectInvalidArgument(
        () => toIoPath(r'relative\x.txt'),
        'toIoPath 相对',
      );
    });
  });
}
