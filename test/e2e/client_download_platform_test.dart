// SPDX-License-Identifier: GPL-3.0-only

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/assembly.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/server/static/flutter_asset_source.dart';

void main() {
  for (final enabled in [false, true]) {
    test('Windows client download is platform-scoped: $enabled', () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'lsf_client_platform_',
      );
      final oldFallback = webAssetsFallbackDir;
      webAssetsFallbackDir = 'assets/web';
      addTearDown(() {
        webAssetsFallbackDir = oldFallback;
      });
      final services = await AppAssembler.assemble(
        dataDir: Directory('${sandbox.path}/data'),
        httpPortOverride: 0,
        udpPortOverride: 0,
        enableDiscovery: false,
        enableWindowsClientDownload: enabled,
      );
      final client = HttpClient();
      try {
        final root = await Directory('${sandbox.path}/shared').create();
        await File('${root.path}/report.txt')
            .writeAsString('download-original');
        final share = await services.shares.create(
          CreateShareRequest(
            rootKind: ShareRootKind.localPath,
            rootUri: root.path,
            displayName: 'Published files',
            mode: ShareMode.lan,
          ),
        );
        Uri url(String path) => Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: services.port,
          path: path,
        );
        for (final path in ['/', '/web/share.html', '/s/${share.id.value}']) {
          final response = await (await client.getUrl(url(path))).close();
          expect(response.statusCode, 200);
          final html = await response.transform(utf8.decoder).join();
          expect(html, isNot(contains(kClientDownloadPlaceholder)));
          expect(html.contains('id="download-client"'), enabled && path != '/');
          if (!enabled) {
            expect(html, isNot(contains('/client/download/windows')));
          }
        }
        final fragment = await (await client.getUrl(
          url('/web/$kWindowsClientDownloadAsset'),
        )).close();
        expect(fragment.statusCode, enabled ? 200 : 404);
        await fragment.drain<void>();

        final installer = await (await client.getUrl(
          url('/client/download/windows'),
        )).close();
        expect(installer.statusCode, 404);
        final error = await installer.transform(utf8.decoder).join();
        expect(error.contains('当前设备没有 Windows 安装程序'), enabled);

        final file = await (await client.getUrl(
          url('/s/${share.id.value}/f/report.txt'),
        )).close();
        expect(file.statusCode, 200);
        expect(await file.transform(utf8.decoder).join(), 'download-original');
      } finally {
        client.close(force: true);
        await services.stop();
        await sandbox.delete(recursive: true);
      }
    });
  }
}
