// SPDX-License-Identifier: GPL-3.0-only

/// 校验算法：流式累加，全程 int64，不把整文件读进内存。
///
/// 默认 xxh3（快，适合局域网大文件）；sha256 可选（跨端对账 / 强一致场景）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:xxh3/xxh3.dart';

/// 支持的校验算法。
enum ChecksumAlgorithm {
  /// 64 位 xxh3，输出 16 位小写十六进制。
  xxh3,

  /// SHA-256，输出 64 位小写十六进制。
  sha256,
}

/// 把算法名解析成枚举；未知算法抛契约错误而不是静默回退。
ChecksumAlgorithm parseChecksumAlgorithm(String raw) {
  final String normalized = raw.trim().toLowerCase();
  switch (normalized) {
    case 'xxh3':
      return ChecksumAlgorithm.xxh3;
    case 'sha256':
      return ChecksumAlgorithm.sha256;
    default:
      throw LanFileException(
        LanFileErrorCode.unsupported,
        '不支持的校验算法: $raw',
      );
  }
}

/// 一次流式校验的累加器。
///
/// 用法：反复 [add] 后调 [digest] 取十六进制串；同一个实例可以连续 [add]，
/// 但 [digest] 之后不应再 [add]（重算请新建实例）。
final class ChecksumAccumulator {
  ChecksumAccumulator(this.algorithm);

  final ChecksumAlgorithm algorithm;

  XXH3State? _xxh3;
  ByteConversionSink? _sha256Input;
  _DigestSink? _digestSink;
  int _bytes = 0;

  /// 已累加的字节数；用于断言「校验覆盖了完整长度」。
  int get byteCount => _bytes;

  /// 累加一段字节。
  void add(List<int> chunk) {
    if (chunk.isEmpty) return;
    _bytes += chunk.length;
    switch (algorithm) {
      case ChecksumAlgorithm.xxh3:
        final XXH3State state = _xxh3 ??= xxh3Stream();
        state.update(
          chunk is Uint8List ? chunk : Uint8List.fromList(chunk),
        );
        return;
      case ChecksumAlgorithm.sha256:
        _ensureSha256();
        _sha256Input!.add(chunk);
        return;
    }
  }

  void _ensureSha256() {
    if (_sha256Input != null) return;
    final _DigestSink sink = _DigestSink();
    _digestSink = sink;
    _sha256Input = sha256.startChunkedConversion(sink);
  }

  /// 结束累加并返回小写十六进制摘要。
  String digest() {
    switch (algorithm) {
      case ChecksumAlgorithm.xxh3:
        final XXH3State state = _xxh3 ??= xxh3Stream();
        return state.digestString();
      case ChecksumAlgorithm.sha256:
        _ensureSha256();
        _sha256Input!.close();
        final Digest? value = _digestSink!.value;
        if (value == null) {
          throw const LanFileException(
            LanFileErrorCode.internal,
            'sha256 摘要未产出',
          );
        }
        return value.toString();
    }
  }
}

final class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}

/// 读取整个文件算摘要；大文件走 [openRead] 流式，不整块载入内存。
Future<String> checksumOfFile(
  File file,
  ChecksumAlgorithm algorithm,
) async {
  final ChecksumAccumulator accumulator = ChecksumAccumulator(algorithm);
  await for (final List<int> chunk in file.openRead()) {
    accumulator.add(chunk);
  }
  return accumulator.digest();
}

/// 读取 [FileRef] 算摘要；支持只算某个区间，供分片校验复用。
Future<String> checksumOfRef(
  FileRef ref,
  ChecksumAlgorithm algorithm, {
  int? start,
  int? endExclusive,
}) async {
  final ChecksumAccumulator accumulator = ChecksumAccumulator(algorithm);
  await for (final List<int> chunk in ref.openRead(
    start: start,
    endExclusive: endExclusive,
  )) {
    accumulator.add(chunk);
  }
  return accumulator.digest();
}

/// 比较两个十六进制摘要，忽略大小写差异。
bool checksumEquals(String expected, String actual) =>
    expected.trim().toLowerCase() == actual.trim().toLowerCase();

/// 校验失败时构造契约错误，附带期望/实际值便于定位。
LanFileException checksumMismatchError({
  required String expected,
  required String actual,
  required ChecksumAlgorithm algorithm,
  String? subject,
}) {
  final String suffix = subject == null ? '' : ' ($subject)';
  return LanFileException(
    LanFileErrorCode.checksumMismatch,
    '校验不一致$suffix：期望 $expected，实际 $actual'
    '（$algorithm.name）',
  );
}

/// 计算 [FileRef] 的指纹（size-mtime），供 ETag 比对。
Future<String> fingerprintOf(FileRef ref) => ref.fingerprint();

/// 把摘要串规范化成可比较形式，非法输入直接抛契约错误。
String normalizeChecksum(String raw, ChecksumAlgorithm algorithm) {
  final String trimmed = raw.trim().toLowerCase();
  final int expectedLength =
      algorithm == ChecksumAlgorithm.sha256 ? 64 : 16;
  if (trimmed.length != expectedLength) {
    throw LanFileException(
      LanFileErrorCode.invalidArgument,
      '$algorithm.name 摘要长度应为 $expectedLength，实际 ${trimmed.length}',
    );
  }
  for (final int unit in trimmed.codeUnits) {
    final bool isDigit = unit >= 0x30 && unit <= 0x39;
    final bool isHexLetter = unit >= 0x61 && unit <= 0x66;
    if (!isDigit && !isHexLetter) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '$algorithm.name 摘要含非十六进制字符',
      );
    }
  }
  return trimmed;
}

/// base64 形式摘要（部分 HTTP 头用 base64 而非 hex）。
String checksumToBase64(String hex) {
  final List<int> bytes = <int>[];
  for (int i = 0; i + 1 < hex.length; i += 2) {
    bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return base64.encode(bytes);
}