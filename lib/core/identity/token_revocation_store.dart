// SPDX-License-Identifier: GPL-3.0-only

/// 能力凭证的吊销表：内存一份、磁盘一份。
///
/// 语义：`isRevoked` 只要内存或磁盘任一侧命中就返回 `true`；`revoke`
/// 两处都写，任何时候都不吞异常——写盘失败必须是可判定的失败，不能
/// 让调用方误以为「已经吊销」。
library;

import 'dart:convert';
import 'dart:io';

import '../contracts/errors.dart';

/// 吊销记录的文件名；相对构造时给的目录。
const String kRevocationFileName = 'revoked_tokens.json';

/// 吊销表：内存 + 落盘。
///
/// `TokenRevocationStore()` 只开内存表，供测试与「本次会话临时吊销」；
/// `TokenRevocationStore.persistent(file)` 额外落盘，跨重启仍生效。
final class TokenRevocationStore {
  /// 只开内存表。
  TokenRevocationStore() : _file = null;

  /// 落盘到 [file]；文件不存在时视为空表，父目录会被创建。
  TokenRevocationStore.persistent(File file) : _file = file;

  final File? _file;
  final Set<String> _memory = <String>{};

  /// 是否已有磁盘后端。
  bool get isPersistent => _file != null;

  /// 当前内存表中已吊销的条目数（不含仅存在于磁盘的历史项）。
  int get memoryRevokedCount => _memory.length;

  /// 吊销一个 jti。
  ///
  /// 重复吊销是幂等的；写盘失败抛 [LanFileException]（码 [LanFileErrorCode.io]），
  /// 并保证内存表里也记上，避免「磁盘写失败 → 本进程内仍然放行」。
  Future<void> revoke(String jti) async {
    if (jti.isEmpty) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        'jti 不能为空',
      );
    }
    _memory.add(jti);
    final File? file = _file;
    if (file == null) {
      return;
    }
    await _mutateFile(file, (Set<String> disk) {
      disk.add(jti);
      return disk;
    });
  }

  /// jti 是否已被吊销。
  ///
  /// 内存命中直接返回，不读盘；未命中才去磁盘查历史项。
  Future<bool> isRevoked(String jti) async {
    if (jti.isEmpty) {
      return false;
    }
    // revokeAll 之后一切皆吊销；哨兵优先，避免「先 revokeAll 再逐条查」漏判。
    if (_memory.contains(allTokensSentinel)) {
      return true;
    }
    if (_memory.contains(jti)) {
      return true;
    }
    final File? file = _file;
    if (file == null) {
      return false;
    }
    final Set<String> disk = await _readFile(file);
    // 磁盘上的哨兵同样代表「全量失效」，与内存表语义一致。
    if (disk.contains(allTokensSentinel)) {
      return true;
    }
    return disk.contains(jti);
  }

  /// 吊销全部：`revokeAll` 之后，**任何** jti 都视为已吊销。
  ///
  /// 实现上用哨兵值 [allTokensSentinel] 落盘，而不是清空后逐条写；
  /// 这样即使之后又有人尝试 `revoke` 个别 jti，全量失效的语义不变。
  Future<void> revokeAll() async {
    _memory.add(allTokensSentinel);
    final File? file = _file;
    if (file == null) {
      return;
    }
    await _mutateFile(file, (Set<String> disk) {
      disk
        ..clear()
        ..add(allTokensSentinel);
      return disk;
    });
  }

  /// 「所有 token 均已吊销」的哨兵；不可能与真实 jti 冲突
  /// （真实 jti 由 base64url 字符组成，不含 `*`）。
  static const String allTokensSentinel = '*';

  Future<Set<String>> _readFile(File file) async {
    final Set<String> result = <String>{};
    final bool exists = await file.exists();
    if (!exists) {
      return result;
    }
    final String raw;
    try {
      raw = await file.readAsString();
    } on FileSystemException catch (error) {
      throw LanFileException(
        LanFileErrorCode.io,
        '读取吊销表失败: ${file.path}',
        cause: error,
      );
    }
    if (raw.trim().isEmpty) {
      return result;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      throw LanFileException(
        LanFileErrorCode.io,
        '吊销表不是合法 JSON: ${file.path}',
        cause: error,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw LanFileException(
        LanFileErrorCode.io,
        '吊销表结构非法: ${file.path}',
      );
    }
    final Object? entries = decoded['jti'];
    if (entries is! List<Object?>) {
      throw LanFileException(
        LanFileErrorCode.io,
        '吊销表缺少 jti 数组: ${file.path}',
      );
    }
    for (final Object? entry in entries) {
      if (entry is String && entry.isNotEmpty) {
        result.add(entry);
      }
    }
    return result;
  }

  Future<void> _mutateFile(
    File file,
    Set<String> Function(Set<String> current) mutate,
  ) async {
    final Set<String> disk = await _readFile(file);
    final Set<String> next = mutate(disk);
    final String encoded = jsonEncode(<String, Object?>{
      'v': 1,
      'jti': next.toList()..sort(),
    });
    try {
      final Directory parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      final File temp = File('${file.path}.tmp');
      await temp.writeAsString(encoded, flush: true);
      await temp.rename(file.path);
    } on FileSystemException catch (error) {
      throw LanFileException(
        LanFileErrorCode.io,
        '写入吊销表失败: ${file.path}',
        cause: error,
      );
    }
  }
}
