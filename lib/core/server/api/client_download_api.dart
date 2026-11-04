// SPDX-License-Identifier: GPL-3.0-only

import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../../contracts/contracts.dart';
import '../response.dart';
import '../router.dart';

/// 只打包可运行的客户端文件，不包含本机资料和分享的源文件。
class ClientPackageSource {
  ClientPackageSource({required this.runtime, required this.cache});
  final Directory runtime;
  final Directory cache;
  Future<File>? _building;

  Future<File> package() {
    return _building ??= _build().catchError((Object error) {
      _building = null;
      throw error;
    });
  }

  Future<File> _build() async {
    final executable = File(p.join(runtime.path, 'lan_simple_file.exe'));
    final app = File(p.join(runtime.path, 'data', 'app.so'));
    if (!await executable.exists() || !await app.exists()) {
      throw const LanFileException(
        LanFileErrorCode.notFound,
        '当前设备没有 Windows 客户端安装包',
      );
    }
    final stamp = await app.stat();
    final file = File(
      p.join(
        cache.path,
        '${stamp.modified.millisecondsSinceEpoch}-${stamp.size}.zip',
      ),
    );
    if (await file.exists()) return file;
    await cache.create(recursive: true);
    final runtimePath = runtime.absolute.path;
    final outputPath = '${file.absolute.path}.tmp';
    await Isolate.run(() async {
      final encoder = ZipFileEncoder()..create(outputPath);
      try {
        final entries = await Directory(runtimePath)
            .list(recursive: true, followLinks: false)
            .toList();
        for (final entry in entries.whereType<File>()) {
          final relative = p.relative(entry.path, from: runtimePath);
          final parts = p.split(relative);
          final extension = p.extension(relative).toLowerCase();
          if (parts.first == 'data' ||
              (parts.length == 1 &&
                  (extension == '.dll' || extension == '.exe'))) {
            await encoder.addFile(entry, relative.replaceAll(r'\', '/'));
          }
        }
      } finally {
        await encoder.close();
      }
    });
    await File(outputPath).rename(file.path);
    return file;
  }
}

void registerClientDownloadRoutes(
  Router router,
  Future<File> Function() package,
) {
  router.get('/client/download/windows', (request) async {
    try {
      final file = await package();
      final response = request.response;
      response.headers.contentType = ContentType('application', 'zip');
      response.headers.set(
        'content-disposition',
        'attachment; filename="lan-simple-file-windows.zip"',
      );
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      response.contentLength = await file.length();
      if (request.method != 'HEAD') await response.addStream(file.openRead());
      await response.close();
    } on LanFileException catch (error) {
      await errorResponse(request.response, error);
    }
  });
}
