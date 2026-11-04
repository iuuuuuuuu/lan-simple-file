// SPDX-License-Identifier: GPL-3.0-only

/// `GET /s/:shareId/zip`：目录的流式 zip 打包（zip64 + store，不压缩）。
///
/// 本文件自己写 zip 结构，而不是把内容塞进 archive 的 Archive：
/// archive 的 ArchiveFile 必须持有完整 content，打包大目录会直接 OOM，
/// 且 store 模式与逐条目 zip64 标记不由调用方直接控制。
///
/// 每个条目走**两遍**：第一遍只算 CRC-32 与长度（进程内只占一个读块），
/// 第二遍把字节原样发出去。代价是磁盘读两次，换来的是：
///   - 进程内内存恒定（不随文件大小增长）；
///   - 本地头里能写真实 CRC 与长度，不需要 data descriptor，
///     对老解压器（含 7-Zip、Windows 资源管理器、archive 包）兼容性最好。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:lan_simple_file/core/contracts/contracts.dart';

import '../response.dart';
import '../router.dart';
import 'share_api.dart';
import 'tree_api.dart';

/// 超过这个数量的文件就不打包，改返回清单 JSON。
const int kZipMaxEntries = 2000;

/// 扫描目录时一旦超过「上限 + 1」个文件就立刻停止，不做完整遍历。
const int kZipScanLimit = kZipMaxEntries + 1;

/// 单个条目在 zip 内的路径长度上限。
const int kZipMaxNameLength = 4096;

/// 读文件的块大小。
const int kZipReadChunkBytes = 256 * 1024;

/// zip 方法：0 = store（不压缩）。
const int kZipMethodStore = 0;

/// zip64 的 32 位 sentinel。
const int _kSentinel32 = 0xffffffff;

/// DOS 时间起点。
const int _kDosEpochYear = 1980;

/// 打包结论。
sealed class ZipPlan {
  const ZipPlan();
}

/// 可以直接流式打包。
final class ZipBundle extends ZipPlan {
  const ZipBundle({
    required this.target,
    required this.baseKey,
    required this.entries,
  });

  final ShareTarget target;

  /// 被打包的目录自身的 itemKey；条目名以它为基准。
  final String baseKey;
  final List<FileRef> entries;
}

/// 文件太多，按清单返回。
final class ZipManifest extends ZipPlan {
  const ZipManifest({
    required this.target,
    required this.total,
    required this.sample,
  });

  final ShareTarget target;
  final int total;

  /// 清单前若干项，供前端展示。
  final List<FileRef> sample;
}

/// 递归扫描 [key] 下的全部文件；超过 [kZipScanLimit] 立即判为清单模式。
Future<ZipPlan> planZip(ShareTarget target, ItemKey key) async {
  final FileRef root = await resolveShareItem(target, key);
  final List<FileRef> files = <FileRef>[];
  final List<FileRef> queue = <FileRef>[root];
  while (queue.isNotEmpty) {
    final FileRef current = queue.removeLast();
    if (!current.isDirectory) {
      files.add(current);
      if (files.length > kZipScanLimit) {
        return ZipManifest(
          target: target,
          total: files.length,
          sample: files.take(20).toList(),
        );
      }
      continue;
    }
    String? cursor;
    do {
      final FileEntryPage page = await current.list(
        cursor: cursor,
        limit: kTreeMaxLimit,
      );
      for (final FileEntry entry in page.entries) {
        final FileRef child = await current.child(entry.itemKey);
        if (child.isDirectory) {
          queue.add(child);
        } else {
          files.add(child);
          if (files.length > kZipScanLimit) {
            return ZipManifest(
              target: target,
              total: files.length,
              sample: files.take(20).toList(),
            );
          }
        }
      }
      cursor = page.nextCursor;
    } while (cursor != null);
  }
  if (files.length > kZipMaxEntries) {
    return ZipManifest(
      target: target,
      total: files.length,
      sample: files.take(20).toList(),
    );
  }
  return ZipBundle(target: target, baseKey: root.itemKey.value, entries: files);
}

/// 条目在 zip 内的相对路径，以被打包的目录 [baseKey] 为基准，
/// 分隔符统一成斜杠。
String zipEntryName(String baseKey, FileRef ref) {
  final String? inside = shareRelativeKey(baseKey, ref.itemKey.value);
  final String relative = inside == null || inside.isEmpty
      ? ref.displayName
      : inside;
  final String sanitized = relative.replaceAll(String.fromCharCode(0x5c), '/');
  if (sanitized.isEmpty ||
      sanitized.length > kZipMaxNameLength ||
      sanitized.startsWith('/')) {
    throw LanFileException(
      LanFileErrorCode.invalidArgument,
      '条目路径非法或过长: ${ref.displayName}',
    );
  }
  return sanitized;
}

/// 把时间转成 DOS 的 (date, time)。
({int date, int time}) dosTimestamp(DateTime at) {
  final DateTime utc = at.toUtc();
  final int year = utc.year < _kDosEpochYear ? _kDosEpochYear : utc.year;
  if (year > 2107) {
    return (date: (127 << 9) | (1 << 5) | 1, time: 0);
  }
  final int date = ((year - _kDosEpochYear) << 9) | (utc.month << 5) | utc.day;
  final int time = (utc.hour << 11) | (utc.minute << 5) | (utc.second ~/ 2);
  return (date: date, time: time);
}

/// 一个已确定元信息的待写条目。
final class ZipEntryMeta {
  const ZipEntryMeta({
    required this.name,
    required this.size,
    required this.crc,
    required this.dosDate,
    required this.dosTime,
    required this.localOffset,
  });

  final List<int> name;
  final int size;
  final int crc;
  final int dosDate;
  final int dosTime;
  final int localOffset;

  bool get sizeNeedsZip64 => size >= _kSentinel32;

  bool get offsetNeedsZip64 => localOffset >= _kSentinel32;

  bool get needsZip64 => sizeNeedsZip64 || offsetNeedsZip64;
}

/// `GET /s/:shareId/zip?path=`。
Handler shareZipHandler(ShareSource source) {
  return (HttpRequest request) async {
    final ShareTarget target = await requireShare(
      source,
      _segment(request.uri, 2),
    );
    final ItemKey key = decodeSharePath(
      request.uri.queryParameters['path'] ?? '',
    );
    final ZipPlan plan = await planZip(target, key);
    switch (plan) {
      case ZipManifest(:final total, :final sample):
        await jsonResponse(request.response, HttpStatus.ok, <String, Object?>{
          'mode': 'manifest',
          'reason': '文件数超过 $kZipMaxEntries，改为逐项下载',
          'total': total,
          'sample': <Map<String, Object?>>[
            for (final FileRef ref in sample)
              <String, Object?>{
                'key': ref.itemKey.value,
                'name': ref.displayName,
              },
          ],
        });
        return;
      case ZipBundle(:final baseKey, :final entries):
        if (entries.isEmpty) {
          throw const LanFileException(
            LanFileErrorCode.notFound,
            '该目录下没有可打包的文件',
          );
        }
        await _streamZip(request, target, baseKey, entries);
        return;
    }
  };
}

Future<void> _streamZip(
  HttpRequest request,
  ShareTarget target,
  String baseKey,
  List<FileRef> entries,
) async {
  final HttpResponse response = request.response;
  response.statusCode = HttpStatus.ok;
  response.headers.contentType = ContentType('application', 'zip');
  response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
  response.headers.set(
    'content-disposition',
    contentDispositionHeader('${target.displayName}.zip'),
  );
  if (request.method == 'HEAD') {
    await response.close();
    return;
  }

  final List<ZipEntryMeta> central = <ZipEntryMeta>[];
  int offset = 0;
  for (final FileRef ref in entries) {
    final ({int size, int crc}) digest = await _digestOf(ref);
    final String name = zipEntryName(baseKey, ref);
    final List<int> nameBytes = utf8.encode(name);
    final DateTime? modified = await ref.lastModified();
    final ({int date, int time}) stamp = dosTimestamp(
      modified ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    final ZipEntryMeta meta = ZipEntryMeta(
      name: nameBytes,
      size: digest.size,
      crc: digest.crc,
      dosDate: stamp.date,
      dosTime: stamp.time,
      localOffset: offset,
    );
    final Uint8List localHeader = zipLocalHeader(meta);
    response.add(localHeader);
    offset += localHeader.length;
    // 第二遍：原样转发字节，进程内只占一个读块。
    await for (final List<int> chunk in ref.openRead()) {
      response.add(chunk);
      offset += chunk.length;
    }
    central.add(meta);
    await response.flush();
  }

  final int centralStart = offset;
  final BytesBuilder builder = BytesBuilder(copy: false);
  for (final ZipEntryMeta meta in central) {
    builder.add(zipCentralHeader(meta));
  }
  final Uint8List centralBytes = builder.takeBytes();
  response.add(centralBytes);
  offset += centralBytes.length;
  response.add(zipEndOfCentralDirectory(central, centralStart, offset));
  await response.close();
}

/// 第一遍：算出长度与 CRC-32。
Future<({int size, int crc})> _digestOf(FileRef ref) async {
  int crc = 0xffffffff;
  int size = 0;
  try {
    await for (final List<int> chunk in ref.openRead()) {
      size += chunk.length;
      crc = _crc32Update(crc, chunk);
    }
  } on LanFileException catch (error) {
    throw LanFileException(
      error.code,
      '读取 ${ref.displayName} 失败: ${error.message}',
      cause: error,
    );
  }
  return (size: size, crc: crc ^ 0xffffffff);
}

const int _kCrcTableSize = 256;

final List<int> _crcTable = _buildCrcTable();

List<int> _buildCrcTable() {
  final List<int> table = List<int>.filled(_kCrcTableSize, 0);
  for (int index = 0; index < _kCrcTableSize; index++) {
    int value = index;
    for (int bit = 0; bit < 8; bit++) {
      value = (value & 1) != 0 ? (value >> 1) ^ 0xedb88320 : value >> 1;
    }
    table[index] = value;
  }
  return table;
}

int _crc32Update(int crc, List<int> bytes) {
  int value = crc;
  for (final int byte in bytes) {
    value = _crcTable[(value ^ byte) & 0xff] ^ (value >> 8);
  }
  return value;
}

Uint8List zipLocalHeader(ZipEntryMeta meta) {
  final bool zip64 = meta.sizeNeedsZip64;
  final int extraLength = zip64 ? 20 : 0;
  final Uint8List header = Uint8List(30 + meta.name.length + extraLength);
  final ByteData view = ByteData.view(header.buffer);
  int at = 0;
  view.setUint32(at, 0x04034b50, Endian.little);
  at += 4;
  view.setUint16(at, zip64 ? 45 : 20, Endian.little);
  at += 2;
  view.setUint16(at, 0, Endian.little); // 无 data descriptor
  at += 2;
  view.setUint16(at, kZipMethodStore, Endian.little);
  at += 2;
  view.setUint16(at, meta.dosTime, Endian.little);
  at += 2;
  view.setUint16(at, meta.dosDate, Endian.little);
  at += 2;
  view.setUint32(at, meta.crc, Endian.little);
  at += 4;
  view.setUint32(at, zip64 ? _kSentinel32 : meta.size, Endian.little);
  at += 4;
  view.setUint32(at, zip64 ? _kSentinel32 : meta.size, Endian.little);
  at += 4;
  view.setUint16(at, meta.name.length, Endian.little);
  at += 2;
  view.setUint16(at, extraLength, Endian.little);
  at += 2;
  header.setRange(at, at + meta.name.length, meta.name);
  at += meta.name.length;
  if (zip64) {
    view.setUint16(at, 0x0001, Endian.little);
    at += 2;
    view.setUint16(at, 16, Endian.little);
    at += 2;
    view.setUint64(at, meta.size, Endian.little);
    at += 8;
    view.setUint64(at, meta.size, Endian.little);
  }
  return header;
}

Uint8List zipCentralHeader(ZipEntryMeta meta) {
  // zip64 extra 的字段顺序固定：usize, csize, localOffset。
  final bool sizeExtra = meta.sizeNeedsZip64;
  final bool offsetExtra = meta.offsetNeedsZip64;
  final int payload = (sizeExtra ? 16 : 0) + (offsetExtra ? 8 : 0);
  final int extraLength = payload == 0 ? 0 : 4 + payload;
  final Uint8List header = Uint8List(46 + meta.name.length + extraLength);
  final ByteData view = ByteData.view(header.buffer);
  int at = 0;
  view.setUint32(at, 0x02014b50, Endian.little);
  at += 4;
  view.setUint16(at, (3 << 8) | 45, Endian.little); // made by: Unix, 4.5
  at += 2;
  view.setUint16(at, meta.needsZip64 ? 45 : 20, Endian.little);
  at += 2;
  view.setUint16(at, 0, Endian.little); // flags
  at += 2;
  view.setUint16(at, kZipMethodStore, Endian.little);
  at += 2;
  view.setUint16(at, meta.dosTime, Endian.little);
  at += 2;
  view.setUint16(at, meta.dosDate, Endian.little);
  at += 2;
  view.setUint32(at, meta.crc, Endian.little);
  at += 4;
  view.setUint32(at, sizeExtra ? _kSentinel32 : meta.size, Endian.little);
  at += 4;
  view.setUint32(at, sizeExtra ? _kSentinel32 : meta.size, Endian.little);
  at += 4;
  view.setUint16(at, meta.name.length, Endian.little);
  at += 2;
  view.setUint16(at, extraLength, Endian.little);
  at += 2;
  view.setUint16(at, 0, Endian.little); // comment length
  at += 2;
  view.setUint16(at, 0, Endian.little); // disk number start
  at += 2;
  view.setUint16(at, 0, Endian.little); // internal attrs
  at += 2;
  view.setUint32(at, 0, Endian.little); // external attrs
  at += 4;
  view.setUint32(
    at,
    offsetExtra ? _kSentinel32 : meta.localOffset,
    Endian.little,
  );
  at += 4;
  header.setRange(at, at + meta.name.length, meta.name);
  at += meta.name.length;
  if (extraLength > 0) {
    view.setUint16(at, 0x0001, Endian.little);
    at += 2;
    view.setUint16(at, payload, Endian.little);
    at += 2;
    if (sizeExtra) {
      view.setUint64(at, meta.size, Endian.little);
      at += 8;
      view.setUint64(at, meta.size, Endian.little);
      at += 8;
    }
    if (offsetExtra) {
      view.setUint64(at, meta.localOffset, Endian.little);
    }
  }
  return header;
}

Uint8List zipEndOfCentralDirectory(
  List<ZipEntryMeta> central,
  int centralStart,
  int centralEnd,
) {
  final int count = central.length;
  final int centralSize = centralEnd - centralStart;
  final bool needsZip64 = count >= 0xffff ||
      centralStart >= _kSentinel32 ||
      centralSize >= _kSentinel32;
  if (!needsZip64) {
    final Uint8List tail = Uint8List(22);
    final ByteData view = ByteData.view(tail.buffer);
    view.setUint32(0, 0x06054b50, Endian.little);
    view.setUint16(4, 0, Endian.little); // disk number
    view.setUint16(6, 0, Endian.little); // disk with central dir
    view.setUint16(8, count, Endian.little); // entries on this disk
    view.setUint16(10, count, Endian.little); // entries total
    view.setUint32(12, centralSize, Endian.little);
    view.setUint32(16, centralStart, Endian.little);
    view.setUint16(20, 0, Endian.little); // comment length
    return tail;
  }
  // APPNOTE 4.3.14.1：签名 4 + size 8 + versionMadeBy 2 + versionNeeded 2 +
  // diskNumber 4 + diskWithCentralDir 4 + entriesOnDisk 8 + entriesTotal 8 +
  // centralSize 8 + centralOffset 8 = 56 字节。
  final Uint8List zip64 = Uint8List(56);
  final ByteData v64 = ByteData.view(zip64.buffer);
  v64.setUint32(0, 0x06064b50, Endian.little);
  v64.setUint64(4, 44, Endian.little); // 之后的记录长度
  v64.setUint16(12, (3 << 8) | 45, Endian.little); // made by: Unix 4.5
  v64.setUint16(14, 45, Endian.little);
  v64.setUint32(16, 0, Endian.little);
  v64.setUint32(20, 0, Endian.little);
  v64.setUint64(24, count, Endian.little);
  v64.setUint64(32, count, Endian.little);
  v64.setUint64(40, centralSize, Endian.little);
  v64.setUint64(48, centralStart, Endian.little);

  // 4.3.15：locator 20 字节。
  final Uint8List locator = Uint8List(20);
  final ByteData vLoc = ByteData.view(locator.buffer);
  vLoc.setUint32(0, 0x07064b50, Endian.little);
  vLoc.setUint32(4, 0, Endian.little); // disk with zip64 EOCD
  vLoc.setUint64(8, centralEnd, Endian.little); // zip64 EOCD 的偏移
  vLoc.setUint32(16, 1, Endian.little); // total disks

  // 末尾再补一个普通 EOCD：从尾部向前扫签名的老解压器仍能命中。
  final Uint8List legacy = zipLegacyEocd(count, centralSize, centralStart);
  return Uint8List.fromList(<int>[...zip64, ...locator, ...legacy]);
}

Uint8List zipLegacyEocd(int count, int centralSize, int centralStart) {
  final Uint8List tail = Uint8List(22);
  final ByteData view = ByteData.view(tail.buffer);
  view.setUint32(0, 0x06054b50, Endian.little);
  view.setUint16(4, 0, Endian.little);
  view.setUint16(6, 0, Endian.little);
  view.setUint16(8, 0xffff, Endian.little);
  view.setUint16(10, 0xffff, Endian.little);
  view.setUint32(12, _kSentinel32, Endian.little);
  view.setUint32(16, _kSentinel32, Endian.little);
  view.setUint16(20, 0, Endian.little);
  return tail;
}

/// 把 zip 路由注册到 [router] 上。
void registerZipRoutes(Router router, ShareSource source) {
  router.get('/s/:shareId/zip', shareZipHandler(source));
}

String _segment(Uri uri, int index) {
  final List<String> parts = uri.path.split('/');
  return index < parts.length ? parts[index] : '';
}