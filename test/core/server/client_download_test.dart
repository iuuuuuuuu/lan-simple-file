// SPDX-License-Identifier: GPL-3.0-only

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/server/api/client_download_api.dart';
import 'package:lan_simple_file/core/server/http_server_host.dart';
import 'package:lan_simple_file/core/server/router.dart';

void main() {
  test('客户端下载为完整 ZIP，包含运行文件且排除本机资料，HEAD 不发送包体', () async {
    final temp = await Directory.systemTemp.createTemp('lsf_client_package_');
    addTearDown(() => temp.delete(recursive: true));
    final runtime = Directory('${temp.path}/runtime')..createSync();
    for (final name in [
      'lan_simple_file.exe',
      'flutter_windows.dll',
      'data/app.so',
      'data/flutter_assets/icon.png',
      'private.txt',
    ]) {
      final file = File('${runtime.path}/$name');
      await file.parent.create(recursive: true);
      await file.writeAsString(name);
    }
    final packages = ClientPackageSource(
      runtime: runtime,
      cache: Directory('${temp.path}/cache'),
    );
    final router = Router();
    registerClientDownloadRoutes(router, packages.package);
    final server = HttpServerHost(
      router: router,
      preferredPort: 0,
      bindAddress: InternetAddress.loopbackIPv4,
    );
    await server.start();
    addTearDown(server.stop);
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final url = Uri.parse(
      'http://127.0.0.1:${server.port}/client/download/windows',
    );
    final response = await (await client.getUrl(url)).close();
    expect(response.statusCode, 200);
    expect(
      response.headers.value('content-disposition'),
      contains('attachment'),
    );
    final bytes = await response.fold<List<int>>(
      [],
      (all, data) => all..addAll(data),
    );
    final archive = ZipDecoder().decodeBytes(bytes);
    expect(archive.map((f) => f.name).toSet(), {
      'lan_simple_file.exe',
      'flutter_windows.dll',
      'data/app.so',
      'data/flutter_assets/icon.png',
    });
    final head = await (await client.openUrl('HEAD', url)).close();
    expect(head.contentLength, bytes.length);
    expect(await head.fold<int>(0, (total, data) => total + data.length), 0);
    expect((await packages.package()).existsSync(), isTrue);
  });
}
