// SPDX-License-Identifier: GPL-3.0-only

/// 本机 profile 的读写接口与内存实现（后续替换为 store 支撑的实现）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:lan_simple_file/core/contracts/contracts.dart';

import '../response.dart';
import '../router.dart';

/// 名字长度上限，防止超长字段进公告与页面。
const int kMaxProfileNameLength = 64;

/// 读取请求体时接受的最大字节数；profile 只有两个短字段。
const int kMaxProfileBodyBytes = 4 * 1024;

/// 本机可公开的 profile 来源。
///
/// 只暴露 ping/profile 需要的三个字段；头像用哈希而不是字节，
/// 与公告里的 `av` 字段保持同一个值域。
abstract interface class ProfileSource {
  PeerId get peerId;

  String get name;

  /// 头像内容哈希，形如 `sha256:...`；未设置时为空串。
  String get avatarHash;

  /// 覆盖名字与头像哈希；实现方负责持久化。
  Future<void> update({required String name, required String avatarHash});
}

/// 保存后的资料立即通知界面和公告层。
final class StoredProfileSource implements ProfileSource {
  StoredProfileSource({
    required this.store,
    required this.peerId,
    required String name,
    required String avatarHash,
  }) : _profile = (name: name, avatarHash: avatarHash);
  final LanFileStore store;
  @override
  final PeerId peerId;
  ({String name, String avatarHash}) _profile;
  final StreamController<void> _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  Future<void> Function()? onChanged;
  @override
  String get name => _profile.name;
  @override
  String get avatarHash => _profile.avatarHash;

  @override
  Future<void> update({
    required String name,
    required String avatarHash,
  }) async {
    final String nextName = normalizeProfileName(name);
    final String nextHash = normalizeAvatarHash(avatarHash);
    await store.setSetting('profile.name', nextName);
    await store.setSetting('profile.avatarHash', nextHash);
    final DeviceRecord? old = await store.findDevice(peerId);
    if (old != null) {
      await store.upsertDevice(
        DeviceRecord(
          peerId: old.peerId,
          publicKey: old.publicKey,
          name: nextName,
          avatarHash: nextHash,
          os: old.os,
          firstSeen: old.firstSeen,
          lastSeen: old.lastSeen,
          online: old.online,
          isSelf: old.isSelf,
          isGuest: old.isGuest,
          note: old.note,
        ),
      );
    }
    _profile = (name: nextName, avatarHash: nextHash);
    _changes.add(null);
    await onChanged?.call();
  }

  Future<void> dispose() => _changes.close();
}

/// 进程内内存实现；重启即丢失，仅用于 M0 骨架与测试。
final class MemoryProfileSource implements ProfileSource {
  MemoryProfileSource({
    required this.peerId,
    String name = '',
    String avatarHash = '',
  }) : _profile = (name: name, avatarHash: avatarHash);

  @override
  final PeerId peerId;

  ({String name, String avatarHash}) _profile;

  @override
  String get name => _profile.name;

  @override
  String get avatarHash => _profile.avatarHash;

  @override
  Future<void> update({
    required String name,
    required String avatarHash,
  }) async {
    _profile = (name: name, avatarHash: avatarHash);
  }
}

/// `GET /api/v1/profile`：返回 {peerId, name, avatarHash}。
Handler profileGetHandler(ProfileSource source) {
  return (HttpRequest request) async {
    await jsonResponse(request.response, HttpStatus.ok, <String, Object?>{
      'peerId': source.peerId.value,
      'name': source.name,
      'avatarHash': source.avatarHash,
    });
  };
}

/// `PUT /api/v1/profile`：改写名字与头像哈希，返回改写后的同一结构。
Handler profilePutHandler(ProfileSource source) {
  return (HttpRequest request) async {
    final Map<String, Object?> body = await readJsonObject(request);
    final Object? rawName = body['name'];
    if (rawName != null && rawName is! String) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        'name 必须是字符串',
      );
    }
    final Object? rawAvatar = body['avatarHash'];
    if (rawAvatar != null && rawAvatar is! String) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        'avatarHash 必须是字符串',
      );
    }
    if (rawName == null && rawAvatar == null) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        'PUT profile 至少需要 name 或 avatarHash',
      );
    }

    final String nextName = normalizeProfileName(
      rawName == null ? source.name : rawName as String,
    );
    final String nextAvatar = normalizeAvatarHash(
      rawAvatar == null ? source.avatarHash : rawAvatar as String,
    );
    await source.update(name: nextName, avatarHash: nextAvatar);

    await jsonResponse(request.response, HttpStatus.ok, <String, Object?>{
      'peerId': source.peerId.value,
      'name': source.name,
      'avatarHash': source.avatarHash,
    });
  };
}

/// 把 profile 路由注册到 [router] 上。
void registerProfileRoutes(Router router, ProfileSource source) {
  final String base = '${LanFileConstants.apiPrefix}/profile';
  router.get(base, profileGetHandler(source));
  router.put(base, profilePutHandler(source));
}

/// 校验并归一化名字：去首尾空白、拒绝控制字符、限制长度。
String normalizeProfileName(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) {
    throw const LanFileException(LanFileErrorCode.invalidArgument, '名字不能为空');
  }
  for (final int unit in trimmed.codeUnits) {
    if (unit < 0x20 || unit == 0x7f) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        '名字不能包含控制字符',
      );
    }
  }
  if (trimmed.runes.length > kMaxProfileNameLength) {
    throw const LanFileException(
      LanFileErrorCode.invalidArgument,
      '名字不能超过 $kMaxProfileNameLength 个字符',
    );
  }
  return trimmed;
}

/// 校验并归一化头像哈希：空串表示「清除」，否则必须是合法 [AvatarHash]。
String normalizeAvatarHash(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  if (AvatarHash.tryParse(trimmed) == null) {
    throw const LanFileException(
      LanFileErrorCode.invalidArgument,
      'avatarHash 必须是 sha256:<hex> 形式',
    );
  }
  return trimmed;
}

/// 请求体排空上限：超过这个量就不再等客户端把 body 发完，直接断开。
const int kMaxDrainBodyBytes = 8 * 1024 * 1024;

/// 读取并解析 JSON 对象请求体；超限、空体、非对象都抛契约错误。
///
/// 超限时**不会**在流中途 throw：那样请求体没读完，HttpServer 无法把响应写回，
/// 客户端只会看到连接被重置而不是可读的 413。正确做法是先把剩余 body 排空，
/// 再抛错，让 413 真正送达；排空本身另有 [kMaxDrainBodyBytes] 上限兜底。
Future<Map<String, Object?>> readJsonObject(
  HttpRequest request, {
  int maxBytes = kMaxProfileBodyBytes,
}) async {
  final List<int> bytes = <int>[];
  bool exceeded = false;
  int drained = 0;
  await for (final List<int> chunk in request) {
    if (exceeded) {
      // 已判定超限，后续数据只为排空连接，不再累积。
      drained += chunk.length;
      if (drained > kMaxDrainBodyBytes) break;
      continue;
    }
    bytes.addAll(chunk);
    if (bytes.length > maxBytes) {
      exceeded = true;
      bytes.clear();
    }
  }
  if (exceeded) {
    throw const LanFileException(
      LanFileErrorCode.invalidArgument,
      '请求体超过上传上限',
      httpStatus: HttpStatus.requestEntityTooLarge,
    );
  }
  if (bytes.isEmpty) {
    throw const LanFileException(
      LanFileErrorCode.invalidArgument,
      '请求体为空，需要 JSON 对象',
    );
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on FormatException catch (error) {
    throw LanFileException(
      LanFileErrorCode.invalidArgument,
      '请求体不是合法 JSON',
      cause: error,
    );
  }
  if (decoded is! Map<String, Object?>) {
    throw const LanFileException(
      LanFileErrorCode.invalidArgument,
      '请求体必须是 JSON 对象',
    );
  }
  return decoded;
}
