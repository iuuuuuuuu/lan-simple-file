// SPDX-License-Identifier: GPL-3.0-only

library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../contracts/contracts.dart';

const int kMaxAvatarBytes = 1024 * 1024;

/// 头像按内容哈希缓存到设置表；源图片移动后仍可使用。
final class AvatarStore {
  AvatarStore(this.store);
  final LanFileStore store;
  Uint8List? selfBytes;
  final Map<String, Uint8List> _cache = <String, Uint8List>{};

  Future<void> loadSelf(String hash) async {
    selfBytes = await read(hash);
  }

  Future<Uint8List?> read(String hash) async {
    if (hash.isEmpty) return null;
    if (_cache.containsKey(hash)) return _cache[hash];
    final String? raw = await store.getSetting('avatar.$hash');
    if (raw == null) return null;
    try {
      final Uint8List bytes = base64Decode(raw);
      if (bytes.length > kMaxAvatarBytes ||
          'sha256:${sha256.convert(bytes)}' != hash) {
        return null;
      }
      _cache[hash] = bytes;
      return bytes;
    } on FormatException {
      return null;
    }
  }

  Future<String> put(Uint8List bytes, {String? expectedHash}) async {
    if (bytes.isEmpty || bytes.length > kMaxAvatarBytes) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        '头像不能超过 1 MB',
      );
    }
    // 设置界面将图片统一裁剪为 PNG，缓存不接受可执行的 SVG 内容。
    const List<int> png = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < png.length ||
        Iterable<int>.generate(png.length).any((int i) => bytes[i] != png[i])) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        '头像需要 PNG 图片',
      );
    }
    final String hash = 'sha256:${sha256.convert(bytes)}';
    if (expectedHash != null && hash != expectedHash) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        '头像内容与公告的哈希不一致',
      );
    }
    await store.setSetting('avatar.$hash', base64Encode(bytes));
    _cache[hash] = Uint8List.fromList(bytes);
    return hash;
  }
}
