// SPDX-License-Identifier: GPL-3.0-only
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/files/saf_bridge.dart';
import 'package:lan_simple_file/core/files/saf_ref_factory.dart';
import 'package:lan_simple_file/core/server/api/share_api.dart';
import 'package:lan_simple_file/core/server/api/tree_api.dart';
import 'package:lan_simple_file/core/server/api/zip_api.dart';
import 'package:lan_simple_file/core/server/http_server_host.dart';
import 'package:lan_simple_file/core/server/router.dart';
import 'package:lan_simple_file/core/server/static/static_handler.dart';

import '../files/saf_ref_test.dart' show FakeSafChannel, installChannel, item;

class _HttpBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _HttpBinding();
  late FakeSafChannel fake;
  late ShareTarget target;
  late HttpServerHost host;
  late HttpClient client;
  const root = 'primary:1';
  final documents = {
    root: item(documentId: root, name: '1', isDirectory: true),
    '$root/photos': item(
      documentId: '$root/photos',
      name: 'photos',
      isDirectory: true,
    ),
    '$root/photos/a.txt': item(
      documentId: '$root/photos/a.txt',
      name: 'a.txt',
      size: 5,
    ),
  };
  setUp(() async {
    fake = FakeSafChannel();
    installChannel(fake);
    fake.on('statItem', (args) => documents[args['documentId']]!);
    fake.on('exists', (args) => documents.containsKey(args['documentId']));
    fake.on('listChildren', (args) {
      final prefix = '${args['documentId']}/';
      final rows = documents.entries
          .where(
            (e) =>
                e.key.startsWith(prefix) &&
                !e.key.substring(prefix.length).contains('/'),
          )
          .map((e) => e.value)
          .toList();
      return args['cursor'] == null ? rows : [];
    });
    var read = false;
    fake.on('openRead', (_) {
      read = false;
      return 'saf-read';
    });
    fake.on('readChunk', (_) {
      if (read) return null;
      read = true;
      return Uint8List.fromList(utf8.encode('hello'));
    });
    fake.on('closeRead', (_) => null);
    target = ShareTarget(
      id: ShareId.parse('saf_test'),
      displayName: 'phone',
      root: await SafRefFactory(const SafBridge()).openRoot(
        'content://com.android.externalstorage.documents/tree/primary%3A1',
      ),
    );
    final source = MapShareSource({'saf_test': target});
    final router = Router();
    registerShareRoutes(router, source, templates: MemoryStaticAssetSource({}));
    registerTreeRoutes(router, source);
    registerZipRoutes(router, source);
    host = HttpServerHost(
      router: router,
      bindAddress: InternetAddress.loopbackIPv4,
      preferredPort: 0,
    );
    await host.start();
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await host.stop();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(kSafChannelName), null);
  });
  Future<HttpClientResponse> get(String path) async => (await client.getUrl(
    Uri.parse('http://127.0.0.1:${host.port}/s/saf_test/$path'),
  )).close();

  test('HTTP empty and dot paths list the primary:1 root', () async {
    for (final suffix in ['tree', 'tree?path=', 'tree?path=.']) {
      final response = await get(suffix);
      final body = await response.transform(utf8.decoder).join();
      expect(response.statusCode, 200, reason: body);
      final data = jsonDecode(body);
      expect(data['rootKey'], root);
      expect(data['entries'].single['key'], '$root/photos');
    }
    expect(fake.callsOf('listChildren').length, 3);
  });

  test(
    'SAF child listing, paging and exact file bytes retain document IDs',
    () async {
      final page = await listSharePage(
        target,
        ItemKey.parse('$root/photos'),
        limit: 10,
      );
      expect(page.entries.single.itemKey.value, '$root/photos/a.txt');
      final next = await listSharePage(
        target,
        ItemKey.parse('$root/photos'),
        cursor: page.entries.single.itemKey.value,
        limit: 10,
      );
      expect(next.entries, isEmpty);
      final file = await resolveShareItem(target, page.entries.single.itemKey);
      expect(
        utf8.decode((await file.openRead().toList()).expand((x) => x).toList()),
        'hello',
      );
    },
  );

  test(
    'HTTP root zip includes nested SAF file with relative name and bytes',
    () async {
      final response = await get('zip');
      final bytes = (await response.toList()).expand((x) => x).toList();
      expect(response.statusCode, 200);
      final zip = ZipDecoder().decodeBytes(bytes);
      expect(zip.files.single.name, 'photos/a.txt');
      expect(utf8.decode(zip.files.single.content), 'hello');
    },
  );

  test('sibling SAF IDs and encoded traversal are still denied before provider access', () async {
    for (final key in [
      'primary:10',
      'primary:10/private',
      'primary:2/photos',
    ]) {
      await expectLater(
        resolveShareItem(target, ItemKey.parse(key)),
        throwsA(
          isA<LanFileException>().having(
            (e) => e.code,
            'code',
            LanFileErrorCode.accessDenied,
          ),
        ),
      );
    }
    for (final suffix in [
      'tree?path=..%2Fprivate',
      'zip?path=%2Fprivate',
      'f/..%2Fsecret',
    ]) {
      final response = await get(suffix);
      expect(response.statusCode, 403);
      await response.drain<void>();
    }
    expect(fake.callsOf('listChildren'), isEmpty);
    expect(fake.callsOf('openRead'), isEmpty);
    expect(fake.callsOf('statItem').length, 1);
  });
}
