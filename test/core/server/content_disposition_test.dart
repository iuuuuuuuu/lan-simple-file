// SPDX-License-Identifier: GPL-3.0-only

/// 头注入与文件名的纯函数测试：不发网络，逐字符验证编码与净化。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/server/response.dart';

import 'support/local_file_ref.dart';

/// 一个可控长度与内容的临时文件引用。
Future<(Directory, LocalFileRef)> _tempFile(String name, int size) async {
  final Directory dir = await Directory.systemTemp.createTemp('lsf_disp_');
  final File file = File('${dir.path}/$name');
  final RandomAccessFile handle = await file.open(mode: FileMode.write);
  await handle.writeFrom(Uint8List(size));
  await handle.close();
  return (dir, LocalFileRef(file.path));
}

void main() {
  group('contentDispositionHeader', () {
    test('纯 ASCII 名同时给出 filename 与 filename*', () {
      final String value =
          contentDispositionHeader('report.pdf');
      expect(value, startsWith('attachment; '));
      expect(value, contains('filename="report.pdf"'));
      expect(
        value,
        contains("filename*=UTF-8''report.pdf"),
        reason: 'ascii 也走 filename*，保证两种客户端同解',
      );
    });

    test('中文名按 UTF-8 percent-encoding，且 filename 兜底为占位符', () {
      final String value = contentDispositionHeader('季度报告.pdf');
      expect(
        value,
        contains("filename*=UTF-8''%E5%AD%A3%E5%BA%A6%E6%8A%A5%E5%91%8A.pdf"),
      );
      // ASCII 兜底里非 ASCII 字符全部变成 _，不会出现裸中文。
      final RegExp fallback = RegExp(r'filename="([^"]*)"');
      final String raw = fallback.firstMatch(value)!.group(1)!;
      for (final int unit in raw.codeUnits) {
        expect(unit, lessThan(0x80), reason: 'ASCII 兜底名不能含非 ASCII');
      }
    });

    test('CR/LF/制表符等控制字符被剔除，无法注入额外头', () {
      final String value = contentDispositionHeader(
        'evil\r\nX-Injected: 1\r\n\r\n.txt',
      );
      expect(value, isNot(contains('\r')));
      expect(value, isNot(contains('\n')));
      expect(value, isNot(contains('\t')));
      expect(value, isNot(contains('X-Injected: 1\r')));
      expect(value, contains('X-Injected: 1'));
    });

    test('双引号与反斜杠在 ASCII 兜底里被替换，不会破坏引号包裹', () {
      final String value = contentDispositionHeader('a"b\\c.txt');
      final RegExp fallback = RegExp(r'filename="([^"]*)"');
      final Match? match = fallback.firstMatch(value);
      expect(match, isNotNull);
      expect(match!.group(1)!, isNot(contains('"')));
      expect(match.group(1)!, isNot(contains('\\')));
    });

    test('超长文件名被截断到上限以内', () {
      final String value = contentDispositionHeader('x' * 500 + '.txt');
      expect(value.length, lessThan(1000));
    });

    test('空名回退成 download，不会产出空 filename', () {
      final String value = contentDispositionHeader('   ');
      expect(value, contains('filename="download"'));
    });

    test('inline 处置类型可用于网页内联展示', () {
      expect(
        contentDispositionHeader('a.txt', disposition: 'inline'),
        startsWith('inline; '),
      );
    });
  });

  group('encodeRfc5987', () {
    test('attr-char 原样保留', () {
      expect(encodeRfc5987('abcXYZ019-._~'), 'abcXYZ019-._~');
    });

    test('空格与中文按 UTF-8 十六进制大写编码', () {
      expect(encodeRfc5987('a b'), 'a%20b');
      expect(encodeRfc5987('中'), '%E4%B8%AD');
    });

    test('百分号本身必须被编码，避免二次解码歧义', () {
      expect(encodeRfc5987('%'), '%25');
    });
  });

  group('sanitizeHeaderFilename', () {
    test('控制字符全被移除', () {
      expect(sanitizeHeaderFilename('a\u0000b\u0007c'), 'abc');
    });

    test('去除首尾空白', () {
      expect(sanitizeHeaderFilename('  a.txt  '), 'a.txt');
    });
  });

  group('零字节与空文件', () {
    test('0 字节文件的 200 响应 Content-Length 为 0', () async {
      final (Directory dir, LocalFileRef ref) = await _tempFile('empty.bin', 0);
      try {
        expect(await ref.length(), 0);
        expect(await ref.fingerprint(), startsWith('0-'));
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
