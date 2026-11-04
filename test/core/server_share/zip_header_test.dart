// SPDX-License-Identifier: GPL-3.0-only

/// zip_header_test：直接验证 zip 头部字节布局，重点是 zip64 分支。
///
/// 为什么不真写 4 GiB 文件：CRC 与长度两遍扫描会让单条用例跑上分钟级。
/// 这里改为对头部构造函数做字节级断言——zip64 的触发条件、extra 字段
/// 顺序（usize, csize, localOffset）与 sentinel 都必须逐字节正确，
/// 任何一处错位都会让解压器读到垃圾长度。
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/server/api/zip_api.dart';

Uint8List names(String value) => Uint8List.fromList(value.codeUnits);

ZipEntryMeta meta({
  required int size,
  int localOffset = 0,
  String name = 'a.txt',
  int crc = 0x12345678,
}) {
  return ZipEntryMeta(
    name: names(name),
    size: size,
    crc: crc,
    dosDate: ((2026 - 1980) << 9) | (11 << 5) | 4,
    dosTime: (13 << 11) | (45 << 5) | 15,
    localOffset: localOffset,
  );
}

void main() {
  group('zip 本地头', () {
    test('小文件不写 zip64 extra，长度字段写真实值', () {
      final ZipEntryMeta entry = meta(size: 1234);
      final Uint8List header = zipLocalHeader(entry);
      final ByteData view = ByteData.view(header.buffer);
      expect(view.getUint32(0, Endian.little), 0x04034b50);
      expect(view.getUint16(4, Endian.little), 20, reason: 'versionNeeded');
      expect(view.getUint16(8, Endian.little), kZipMethodStore);
      expect(view.getUint32(14, Endian.little), 0x12345678, reason: 'crc');
      expect(view.getUint32(18, Endian.little), 1234);
      expect(view.getUint32(22, Endian.little), 1234);
      expect(view.getUint16(26, Endian.little), 'a.txt'.length);
      expect(view.getUint16(28, Endian.little), 0, reason: '无 extra');
      expect(header.length, 30 + 'a.txt'.length);
    });

    test('超过 4 GiB 时长度字段写 0xFFFFFFFF 并附 zip64 extra（16 字节）', () {
      final ZipEntryMeta entry = meta(size: 0x100000001);
      final Uint8List header = zipLocalHeader(entry);
      final ByteData view = ByteData.view(header.buffer);
      expect(view.getUint16(4, Endian.little), 45, reason: 'versionNeeded 4.5');
      expect(view.getUint32(18, Endian.little), 0xFFFFFFFF);
      expect(view.getUint32(22, Endian.little), 0xFFFFFFFF);
      expect(view.getUint16(28, Endian.little), 20, reason: 'extra 长度');
      final int extraAt = 30 + 'a.txt'.length;
      expect(view.getUint16(extraAt, Endian.little), 0x0001);
      expect(view.getUint16(extraAt + 2, Endian.little), 16);
      expect(view.getUint64(extraAt + 4, Endian.little), 0x100000001);
      expect(view.getUint64(extraAt + 12, Endian.little), 0x100000001);
      expect(header.length, 30 + 'a.txt'.length + 20);
    });
  });

  group('zip 中央目录头', () {
    test('普通条目：无 extra，offset 写真实值', () {
      final ZipEntryMeta entry = meta(size: 10, localOffset: 500);
      final Uint8List header = zipCentralHeader(entry);
      final ByteData view = ByteData.view(header.buffer);
      expect(view.getUint32(0, Endian.little), 0x02014b50);
      expect(view.getUint16(10, Endian.little), kZipMethodStore);
      expect(view.getUint32(16, Endian.little), 0x12345678, reason: 'crc');
      expect(view.getUint32(20, Endian.little), 10);
      expect(view.getUint32(24, Endian.little), 10);
      expect(view.getUint16(30, Endian.little), 0, reason: '无 extra');
      expect(view.getUint32(42, Endian.little), 500, reason: 'localOffset');
    });

    test('偏移超 4 GiB：只写 localOffset 的 zip64 extra（8 字节）', () {
      final ZipEntryMeta entry = meta(size: 10, localOffset: 0x100000002);
      final Uint8List header = zipCentralHeader(entry);
      final ByteData view = ByteData.view(header.buffer);
      expect(view.getUint32(20, Endian.little), 10, reason: '尺寸放得下');
      expect(view.getUint32(24, Endian.little), 10);
      expect(view.getUint16(30, Endian.little), 12, reason: '4 + 8');
      expect(view.getUint32(42, Endian.little), 0xFFFFFFFF, reason: 'sentinel');
      final int extraAt = 46 + 'a.txt'.length;
      expect(view.getUint16(extraAt, Endian.little), 0x0001);
      expect(view.getUint16(extraAt + 2, Endian.little), 8);
      expect(view.getUint64(extraAt + 4, Endian.little), 0x100000002);
    });

    test('尺寸与偏移都超 4 GiB：extra 内按 usize,csize,offset 顺序排布', () {
      final ZipEntryMeta entry = meta(size: 0x100000003, localOffset: 0x200000004);
      final Uint8List header = zipCentralHeader(entry);
      final ByteData view = ByteData.view(header.buffer);
      expect(view.getUint16(30, Endian.little), 28, reason: '4 + 24');
      final int extraAt = 46 + 'a.txt'.length;
      expect(view.getUint16(extraAt + 2, Endian.little), 24);
      expect(view.getUint64(extraAt + 4, Endian.little), 0x100000003);
      expect(view.getUint64(extraAt + 12, Endian.little), 0x100000003);
      expect(view.getUint64(extraAt + 20, Endian.little), 0x200000004);
    });
  });

  group('zip 中央目录尾', () {
    test('条目少且偏移小：只写 22 字节普通 EOCD', () {
      final Uint8List tail = zipEndOfCentralDirectory(
        <ZipEntryMeta>[meta(size: 1)],
        100,
        200,
      );
      expect(tail.length, 22);
      final ByteData view = ByteData.view(tail.buffer);
      expect(view.getUint32(0, Endian.little), 0x06054b50);
      expect(view.getUint16(8, Endian.little), 1);
      expect(view.getUint32(12, Endian.little), 100, reason: '中央目录长度');
      expect(view.getUint32(16, Endian.little), 100, reason: '中央目录起点');
    });

    test('偏移超 4 GiB：写 zip64 EOCD + locator + 兼容 EOCD', () {
      final Uint8List tail = zipEndOfCentralDirectory(
        <ZipEntryMeta>[meta(size: 1)],
        0x100000005,
        0x100000005,
      );
      expect(tail.length, 56 + 20 + 22);
      final ByteData view = ByteData.view(tail.buffer);
      expect(view.getUint32(0, Endian.little), 0x06064b50, reason: 'zip64 EOCD');
      expect(view.getUint64(24, Endian.little), 1);
      expect(view.getUint64(48, Endian.little), 0x100000005);
      expect(view.getUint32(56, Endian.little), 0x07064b50, reason: 'locator');
      expect(view.getUint64(64, Endian.little), 0x100000005,
          reason: 'locator 指向 zip64 EOCD');
      expect(view.getUint32(72, Endian.little), 1, reason: 'total disks');
      expect(
        view.getUint32(76, Endian.little),
        0x06054b50,
        reason: '尾部仍有普通 EOCD 供老解压器扫描',
      );
    });
  });
}
