// SPDX-License-Identifier: GPL-3.0-only

/// 生产环境的静态资源来源：从 Flutter asset bundle 读内置网页。
///
/// 存在理由：`MemoryStaticAssetSource` 只适合测试（内存表），
/// 真机上页面必须来自打包进 app 的 asset，否则取件页/访客页会 404。
///
/// [fallbackDir] 是为测试与开发留的磁盘回退：`flutter test` 没有 asset bundle
/// （rootBundle 在非 widget 环境拿不到），若只走 bundle，端到端测试的页面路由会永远 404。
library;

import 'dart:io';

import 'package:flutter/services.dart';

import 'static_handler.dart';
/// 从 asset bundle 读 assets/web/ 下的资源，可选用磁盘目录兜底。
final class FlutterAssetSource implements StaticAssetSource {
  const FlutterAssetSource({
    this.bundle,
    this.prefix = 'assets/web/',
    this.fallbackDir,
  });

  /// 资源包；默认根包。测试可注入假 bundle。
  final AssetBundle? bundle;

  /// 资源前缀，与 pubspec 里声明的路径一致。
  final String prefix;

  /// 磁盘回退目录（如仓库根的 assets/web）。
  ///
  /// 只在 bundle 读不到时使用；真机上通常不需要。
  final String? fallbackDir;

  AssetBundle get _bundle => bundle ?? rootBundle;

  @override
  Future<Uint8List?> load(String path) async {
    final String normalized = normalizeAssetPath(path);
    if (normalized.isEmpty) {
      return null;
    }
    final Uint8List? fromBundle = await _loadFromBundle(normalized);
    if (fromBundle != null) {
      return fromBundle;
    }
    return _loadFromDisk(normalized);
  }

  Future<Uint8List?> _loadFromBundle(String normalized) async {
    try {
      final ByteData data = await _bundle.load(prefix + normalized);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } on Object {
      // 资源不存在时返回 null（路由据此出 404），不抛——
      // 抛异常会让「页面缺失」表现成 500，掩盖真正原因。
      return null;
    }
  }

  Future<Uint8List?> _loadFromDisk(String normalized) async {
    final String? dir = fallbackDir;
    if (dir == null) {
      return null;
    }
    final String relative = normalized.replaceAll('/', Platform.pathSeparator);
    final File file = File(dir + Platform.pathSeparator + relative);
    try {
      if (!await file.exists()) {
        return null;
      }
      return await file.readAsBytes();
    } on Object {
      return null;
    }
  }
}
