// SPDX-License-Identifier: GPL-3.0-only
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/server/api/client_download_api.dart';
import 'package:lan_simple_file/core/server/http_server_host.dart';
import 'package:lan_simple_file/core/server/router.dart';

void main() {
  test('网页返回实际安装程序；HEAD 无包体，缺失安装包返回404', () async {
    final temp = await Directory.systemTemp.createTemp('lsf_installer_');
    addTearDown(() => temp.delete(recursive: true));
    final installer = File('${temp.path}/installers/lan-simple-file-setup.exe');
    await installer.parent.create(recursive: true);
    await installer.writeAsBytes([77, 90, 1, 2, 3, 4]);
    final source = ClientPackageSource(runtime: temp);
    final router = Router();
    registerClientDownloadRoutes(router, source.package);
    final server = HttpServerHost(router: router, preferredPort: 0);
    await server.start();
    addTearDown(server.stop);
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final url = Uri.parse(
      'http://127.0.0.1:${server.port}/client/download/windows',
    );
    final response = await (await client.getUrl(url)).close();
    expect(response.statusCode, 200);
    expect(response.headers.contentType!.mimeType, 'application/octet-stream');
    expect(
      response.headers.value('content-disposition'),
      contains('setup.exe'),
    );
    expect(await response.fold<List<int>>([], (a, b) => a..addAll(b)), [
      77,
      90,
      1,
      2,
      3,
      4,
    ]);
    final head = await (await client.openUrl('HEAD', url)).close();
    expect(head.contentLength, 6);
    expect(await head.fold<int>(0, (a, b) => a + b.length), 0);
    await installer.delete();
    final missing = await (await client.getUrl(url)).close();
    expect(missing.statusCode, 404);
    await missing.drain<void>();
  });
}
