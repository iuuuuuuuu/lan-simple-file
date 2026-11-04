// SPDX-License-Identifier: GPL-3.0-only

/// HTTP 响应工具：统一 JSON/错误体、Range 协商、RFC 5987 文件名。
///
/// 本文件不依赖路由；[fileRangeResponse] 可被任何持有 [FileRef] 的调用方直接使用。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:lan_simple_file/core/contracts/contracts.dart';

/// 一段闭区间的字节范围，语义与 HTTP `Range: bytes=start-end` 一致。
final class ByteRange {
  const ByteRange(this.start, this.endInclusive);

  final int start;

  /// 闭区间末端，实际发送的字节数为 `endInclusive - start + 1`。
  final int endInclusive;

  int get length => endInclusive - start + 1;

  @override
  String toString() => 'ByteRange($start-$endInclusive)';

  @override
  bool operator ==(Object other) =>
      other is ByteRange &&
      other.start == start &&
      other.endInclusive == endInclusive;

  @override
  int get hashCode => Object.hash(start, endInclusive);
}

/// Range 头的解析结论。
enum RangeOutcome {
  /// 没有 Range 头，按完整实体返回 200。
  absent,

  /// 语法合法且可满足，返回 206。
  satisfiable,

  /// 语法合法但落在实体之外，返回 416。
  unsatisfiable,

  /// 语法非法、单位不支持或多段（本实现不支持分段 multipart），忽略该头按 200 返回。
  ignored,
}

/// Range 头解析结果，[range] 仅在 [RangeOutcome.satisfiable] 时非空。
final class RangeParseResult {
  const RangeParseResult(this.outcome, [this.range]);

  const RangeParseResult.absent() : this(RangeOutcome.absent);

  const RangeParseResult.ignored() : this(RangeOutcome.ignored);

  const RangeParseResult.unsatisfiable() : this(RangeOutcome.unsatisfiable);

  const RangeParseResult.satisfiable(ByteRange range)
      : this(RangeOutcome.satisfiable, range);

  final RangeOutcome outcome;
  final ByteRange? range;

  @override
  String toString() => 'RangeParseResult(${outcome.name}, $range)';
}

/// 解析 `Range: bytes=...`。
///
/// 只支持单段范围；多段（含逗号）按 [RangeOutcome.ignored] 处理，
/// 因为本项目只做单文件分片并发，每个连接只取一段。
RangeParseResult parseRangeHeader(String? header, int totalBytes) {
  if (header == null || header.trim().isEmpty) {
    return const RangeParseResult.absent();
  }
  final String trimmed = header.trim();
  final int eq = trimmed.indexOf('=');
  if (eq <= 0) return const RangeParseResult.ignored();
  final String unit = trimmed.substring(0, eq).trim().toLowerCase();
  if (unit != 'bytes') return const RangeParseResult.ignored();
  final String spec = trimmed.substring(eq + 1).trim();
  if (spec.isEmpty) return const RangeParseResult.ignored();
  if (spec.contains(',')) return const RangeParseResult.ignored();

  final int dash = spec.indexOf('-');
  if (dash < 0) return const RangeParseResult.ignored();
  final String rawStart = spec.substring(0, dash).trim();
  final String rawEnd = spec.substring(dash + 1).trim();
  if (rawStart.isEmpty && rawEnd.isEmpty) return const RangeParseResult.ignored();

  if (totalBytes < 0) {
    throw ArgumentError.value(totalBytes, 'totalBytes', '实体长度不能为负');
  }
  if (totalBytes == 0) return const RangeParseResult.unsatisfiable();

  if (rawStart.isEmpty) {
    // 后缀范围 bytes=-N：取末尾 N 字节。
    final int? suffix = int.tryParse(rawEnd);
    if (suffix == null) return const RangeParseResult.ignored();
    if (suffix == 0) return const RangeParseResult.unsatisfiable();
    final int start = suffix >= totalBytes ? 0 : totalBytes - suffix;
    return RangeParseResult.satisfiable(ByteRange(start, totalBytes - 1));
  }

  final int? start = int.tryParse(rawStart);
  if (start == null) return const RangeParseResult.ignored();
  if (start >= totalBytes) return const RangeParseResult.unsatisfiable();
  if (rawEnd.isEmpty) {
    return RangeParseResult.satisfiable(ByteRange(start, totalBytes - 1));
  }
  final int? end = int.tryParse(rawEnd);
  if (end == null) return const RangeParseResult.ignored();
  if (end < start) return const RangeParseResult.ignored();
  final int clamped = end >= totalBytes ? totalBytes - 1 : end;
  return RangeParseResult.satisfiable(ByteRange(start, clamped));
}

/// 构造 `Content-Disposition` 头值。
///
/// 同时给出 ASCII 兜底名与 RFC 8187 的 `filename*`：老客户端读 `filename`，
/// 新客户端读 `filename*`。CR/LF/NUL 等控制字符直接丢弃，
/// 因此文件名无法注入额外的头字段。
String contentDispositionHeader(
  String filename, {
  String disposition = 'attachment',
}) {
  final String safe = sanitizeHeaderFilename(filename);
  final String fallback = _asciiFallbackName(safe);
  final String encoded = encodeRfc5987(safe);
  return '$disposition; filename="$fallback"; filename*=UTF-8\'\'$encoded';
}

/// 去掉文件名里的头注入字符与不可见控制字符，并限制长度。
String sanitizeHeaderFilename(String filename) {
  final StringBuffer buffer = StringBuffer();
  for (final int rune in filename.runes) {
    if (rune < 0x20 || rune == 0x7f) continue;
    buffer.writeCharCode(rune);
  }
  String cleaned = buffer.toString().trim();
  if (cleaned.length > 200) {
    cleaned = cleaned.substring(0, 200);
  }
  return cleaned;
}

/// RFC 8187 的 percent-encoding：仅保留 attr-char，其余按 UTF-8 字节编码。
String encodeRfc5987(String value) {
  final StringBuffer buffer = StringBuffer();
  for (final int byte in utf8.encode(value)) {
    if (_isAttrChar(byte)) {
      buffer.writeCharCode(byte);
    } else {
      buffer.write('%');
      buffer.write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
    }
  }
  return buffer.toString();
}

String _asciiFallbackName(String filename) {
  final StringBuffer buffer = StringBuffer();
  for (final int rune in filename.runes) {
    if (rune > 0x7e) {
      buffer.write('_');
      continue;
    }
    if (rune == 0x22 || rune == 0x5c || rune == 0x2f || rune == 0x3b) {
      buffer.write('_');
      continue;
    }
    buffer.writeCharCode(rune);
  }
  final String fallback = buffer.toString().trim();
  if (fallback.isEmpty) return 'download';
  if (fallback.length > 120) return fallback.substring(0, 120);
  return fallback;
}

/// RFC 8187 attr-char：字母数字与 `!#$&+-.^_`|~`。
bool _isAttrChar(int byte) {
  if (byte >= 0x30 && byte <= 0x39) return true; // 0-9
  if (byte >= 0x41 && byte <= 0x5a) return true; // A-Z
  if (byte >= 0x61 && byte <= 0x7a) return true; // a-z
  const List<int> extra = <int>[
    0x21, // !
    0x23, // #
    0x24, // $
    0x26, // &
    0x2b, // +
    0x2d, // -
    0x2e, // .
    0x5e, // ^
    0x5f, // _
    0x60, // `
    0x7c, // |
    0x7e, // ~
  ];
  return extra.contains(byte);
}

/// 写出 JSON 响应；HEAD 请求由 dart:io 自动丢体，头与长度保持与 GET 一致。
Future<void> jsonResponse(
  HttpResponse res,
  int status,
  Map<String, Object?> body,
) async {
  final Uint8List bytes = Uint8List.fromList(utf8.encode(jsonEncode(body)));
  res.statusCode = status;
  res.headers.contentType = ContentType.json;
  res.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
  res.contentLength = bytes.length;
  res.add(bytes);
  await res.close();
}

/// 把契约错误映射为状态码 + `{"code","message"}`。
Future<void> errorResponse(HttpResponse res, LanFileException e) async {
  await jsonResponse(res, e.resolvedHttpStatus, <String, Object?>{
    'code': e.code.name,
    'message': e.message,
  });
}

/// 带 Range / ETag / HEAD 语义的整文件响应。
///
/// 支持：
/// - 200 全量、206 单段、416 越界（附 `Content-Range: bytes */N`）
/// - HEAD 不发送实体但 `Content-Length` 与 GET 相同
/// - `Accept-Ranges: bytes`、`ETag`、`If-None-Match` → 304
/// - `Content-Disposition: attachment; filename="..."; filename*=UTF-8''...`
///
/// [downloadName] 为空时使用 [FileRef.displayName]。
Future<void> fileRangeResponse(
  HttpResponse res,
  FileRef ref,
  HttpRequest req, {
  String? downloadName,
}) async {
  if (ref.isDirectory) {
    throw const LanFileException(
      LanFileErrorCode.invalidArgument,
      '目录不支持按单文件读取',
    );
  }

  final int total;
  final String fingerprint;
  try {
    total = await ref.length();
    fingerprint = await ref.fingerprint();
  } on LanFileException {
    rethrow;
  } catch (error) {
    throw LanFileException(
      LanFileErrorCode.io,
      '读取文件元信息失败: ${ref.displayName}',
      cause: error,
    );
  }

  final String etag = '"$fingerprint"';
  res.headers.set(HttpHeaders.etagHeader, etag);
  res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
  res.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
  res.headers.set(
    'content-disposition',
    contentDispositionHeader(downloadName ?? ref.displayName),
  );
  res.headers.contentType = _contentTypeOf(ref.toEntry().mime);

  final String? ifNoneMatch = req.headers.value(HttpHeaders.ifNoneMatchHeader);
  if (ifNoneMatch != null && _etagMatches(ifNoneMatch, etag)) {
    res.statusCode = HttpStatus.notModified;
    res.contentLength = 0;
    await res.close();
    return;
  }

  final bool isHead = req.method == 'HEAD';
  final RangeParseResult parsed = parseRangeHeader(
    req.headers.value(HttpHeaders.rangeHeader),
    total,
  );

  switch (parsed.outcome) {
    case RangeOutcome.absent:
    case RangeOutcome.ignored:
      res.statusCode = HttpStatus.ok;
      res.contentLength = total;
      if (isHead || total == 0) {
        await res.close();
        return;
      }
      await res.addStream(ref.openRead());
      await res.close();
      return;

    case RangeOutcome.unsatisfiable:
      res.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes */$total',
      );
      await errorResponse(
        res,
        LanFileException(
          LanFileErrorCode.invalidArgument,
          '请求的字节范围超出文件长度',
          httpStatus: HttpStatus.requestedRangeNotSatisfiable,
        ),
      );
      return;

    case RangeOutcome.satisfiable:
      final ByteRange range = parsed.range!;
      res.statusCode = HttpStatus.partialContent;
      res.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes ${range.start}-${range.endInclusive}/$total',
      );
      res.contentLength = range.length;
      if (isHead) {
        await res.close();
        return;
      }
      await res.addStream(
        ref.openRead(start: range.start, endExclusive: range.endInclusive + 1),
      );
      await res.close();
      return;
  }
}

bool _etagMatches(String headerValue, String etag) {
  for (final String candidate in headerValue.split(',')) {
    String value = candidate.trim();
    if (value == '*') return true;
    if (value.startsWith('W/')) {
      value = value.substring(2).trim();
    }
    if (value == etag) return true;
  }
  return false;
}

ContentType _contentTypeOf(String? mime) {
  if (mime == null || mime.isEmpty) {
    return ContentType.binary;
  }
  final List<String> parts = mime.split('/');
  if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
    return ContentType.binary;
  }
  try {
    return ContentType(parts[0], parts[1]);
  } on Object {
    return ContentType.binary;
  }
}
