// SPDX-License-Identifier: GPL-3.0-only

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../contracts/contracts.dart';
import '../response.dart';
import '../router.dart';

/// Serves the installer distributed alongside the running client.
class ClientPackageSource {
  ClientPackageSource({required this.runtime});
  final Directory runtime;
  Future<File> package() async {
    final file = File(
      p.join(runtime.path, 'installers', 'lan-simple-file-setup.exe'),
    );
    if (!await file.exists()) {
      throw const LanFileException(
        LanFileErrorCode.notFound,
        '当前设备没有 Windows 安装程序，请从 GitHub Releases 下载',
      );
    }
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
      response.headers.contentType = ContentType('application', 'octet-stream');
      response.headers.set(
        'content-disposition',
        'attachment; filename="lan-simple-file-setup.exe"',
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
