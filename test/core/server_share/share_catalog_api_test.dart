// SPDX-License-Identifier: GPL-3.0-only

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/assembly.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/shares/share_service_impl.dart';
import 'package:lan_simple_file/core/shares/share_organization.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory sandbox;
  late Directory folder;
  late AppServices services;
  late HttpClient client;

  Uri url(String path) =>
      Uri(scheme: 'http', host: '127.0.0.1', port: services.port, path: path);

  Future<Map<String, dynamic>> catalog({String? group}) async {
    final response = await (await client.getUrl(
      url('/api/v1/shared-roots')
          .replace(queryParameters: group == null ? null : {'group': group}),
    )).close();
    expect(response.statusCode, 200);
    expect(response.headers.value(HttpHeaders.cacheControlHeader), 'no-store');
    return jsonDecode(await response.transform(utf8.decoder).join())
        as Map<String, dynamic>;
  }

  ShareRecord record(
    String id, {
    ShareMode mode = ShareMode.token,
    PeerId? owner,
    String? rootUri,
    String? displayName,
    bool enabled = true,
    bool missing = false,
    bool ephemeral = false,
    DateTime? expiresAt,
    DateTime? revokedAt,
    String kind = 'folder',
  }) => ShareRecord(
    id: ShareId.parse(id),
    kind: kind,
    rootKind: 'localPath',
    rootUri: rootUri ?? folder.path,
    displayName: displayName ?? id,
    ownerPeerId: owner ?? services.identity.peerId,
    createdAt: DateTime.utc(2026, 1, 1),
    mode: mode,
    enabled: enabled,
    missing: missing,
    isEphemeral: ephemeral,
    expiresAt: expiresAt,
    revokedAt: revokedAt,
    passwordHash: mode == ShareMode.password ? 'private-password-hash' : null,
    groupId: mode == ShareMode.group ? 'hidden-group-id' : null,
  );

  setUp(() async {
    webAssetsFallbackDir = p.join('assets', 'web');
    sandbox = Directory.systemTemp.createTempSync('lsf_catalog_');
    folder = Directory(p.join(sandbox.path, 'files'))..createSync();
    File(p.join(folder.path, 'report.txt'))
        .writeAsStringSync('exact-file-bytes');
    services = await AppAssembler.assemble(
      dataDir: Directory(p.join(sandbox.path, 'data')),
      name: 'Catalog Owner',
      httpPortOverride: 0,
      udpPortOverride: 0,
      enableDiscovery: false,
    );
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await services.stop();
    expect(
      p.isWithin(Directory.systemTemp.absolute.path, sandbox.path),
      isTrue,
    );
    sandbox.deleteSync(recursive: true);
  });

  test(
    'root and legacy index serve the catalog, including an empty state',
    () async {
      for (final path in ['/', '/web/index.html']) {
        final response = await (await client.getUrl(url(path))).close();
        expect(response.statusCode, 200);
        expect(response.headers.contentType?.mimeType, 'text/html');
        final html = await response.transform(utf8.decoder).join();
        expect(html, contains('id="shared-roots"'));
        expect(html, contains('id="share-search"'));
      }
      final payload = await catalog();
      expect(payload['shares'], isEmpty);
      expect(payload['owner']['name'], 'Catalog Owner');
      expect(payload['owner']['peerId'], services.identity.peerId.value);
    },
  );

  test(
    'real HTTP responses record full, partial and ZIP sends but not probes',
    () async {
      await services.store.upsertShare(record('history', mode: ShareMode.lan));
      final file = url('/s/history/f/report.txt');
      Future<HttpClientResponse> get(
        Uri uri, {
        String method = 'GET',
        String? range,
        String? etag,
      }) async {
        final request = await client.openUrl(method, uri);
        if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
        if (etag != null) {
          request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
        }
        final response = await request.close();
        await response.drain<void>();
        return response;
      }

      expect((await get(file, method: 'HEAD')).statusCode, 200);
      final full = await get(file);
      expect(full.statusCode, 200);
      expect(
        (await get(
          file,
          etag: full.headers.value(HttpHeaders.etagHeader),
        )).statusCode,
        304,
      );
      expect((await get(file, range: 'bytes=2-5')).statusCode, 206);
      expect((await get(file, range: 'bytes=9999-')).statusCode, 416);
      expect(
        (await get(url('/s/history/zip'), method: 'HEAD')).statusCode,
        200,
      );
      expect((await get(url('/s/history/zip'))).statusCode, 200);
      final history = services.transferHistory!;
      for (
        var attempt = 0;
        attempt < 100 && (await history.list()).length < 3;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final entries = await history.list();
      expect(entries, hasLength(3));
      expect(
        entries.every((entry) => entry.direction == TransferDirection.upload),
        isTrue,
      );
      final sent = entries.singleWhere(
        (entry) => entry.status == 'sent' && !entry.archive,
      );
      expect(sent.name, 'report.txt');
      expect(await File(sent.localPath!).readAsString(), 'exact-file-bytes');
      expect(sent.bytes, 16);
      expect(
        entries.singleWhere((entry) => entry.status == 'partial').bytes,
        4,
      );
      final zip = entries.singleWhere((entry) => entry.archive);
      expect(zip.name, 'history.zip');
      expect(zip.localPath, isNull);
      expect(zip.bytes, isNull);
    },
  );

  test(
    'only live persistent local shares are published, without private paths',
    () async {
      for (final share in [
        record('folder-token'),
        record(
          'file-lan',
          mode: ShareMode.lan,
          kind: 'file',
          rootUri: p.join(folder.path, 'report.txt'),
        ),
        record('foreign', owner: PeerId.parse('p_remote1234567')),
        record('disabled', enabled: false),
        record('missing', missing: true),
        record('revoked', revokedAt: DateTime.utc(2020)),
        record('expired', expiresAt: DateTime.utc(2020)),
        record('ephemeral', ephemeral: true),
        record('offer', mode: ShareMode.offer),
        record('session', mode: ShareMode.session),
        record('gone', rootUri: p.join(sandbox.path, 'gone')),
      ]) {
        await services.store.upsertShare(share);
      }
      final payload = await catalog();
      final entries = (payload['shares'] as List).cast<Map<String, dynamic>>();
      expect(entries.map((entry) => entry['name']), [
        'folder-token',
        'file-lan',
      ]);
      expect(
        entries.map((entry) => entry['href']),
        containsAll(['/s/folder-token', '/s/file-lan']),
      );
      final encoded = jsonEncode(payload);
      for (final private in [
        'rootUri',
        'passwordHash',
        'groupId',
        'token',
        'sessionId',
      ]) {
        expect(entries.every((entry) => !entry.containsKey(private)), isTrue);
      }
      expect(encoded, isNot(contains(sandbox.path)));
    },
  );

  test(
    'restricted shares show a label but disclose neither id nor grant',
    () async {
      for (final mode in [
        ShareMode.password,
        ShareMode.people,
        ShareMode.group,
      ]) {
        await services.store.upsertShare(
          record(
            'private-${mode.name}',
            mode: mode,
            displayName: 'Locked ${mode.name}',
          ),
        );
      }
      final payload = await catalog();
      final entries = (payload['shares'] as List).cast<Map<String, dynamic>>();
      expect(entries, hasLength(3));
      expect(entries.every((entry) => entry['href'] == null), isTrue);
      expect(
        entries.map((entry) => entry['access']),
        unorderedEquals(['password', 'people', 'group']),
      );
      expect(entries.every((entry) => !entry.containsKey('id')), isTrue);
      expect(jsonEncode(payload), isNot(contains('private-password-hash')));
      expect(jsonEncode(payload), isNot(contains('hidden-group-id')));
      expect(jsonEncode(payload), isNot(contains('private-')));
    },
  );

  test(
    'catalog links browse folders and download single files unchanged',
    () async {
      await services.store.upsertShare(record('folder'));
      await services.store.upsertShare(
        record(
          'single',
          kind: 'file',
          rootUri: p.join(folder.path, 'report.txt'),
        ),
      );
      final entries = ((await catalog())['shares'] as List)
          .cast<Map<String, dynamic>>();
      for (final entry in entries) {
        final response = await (await client.getUrl(
          url(entry['href'] as String),
        )).close();
        expect(response.statusCode, 200);
        expect(
          await response.transform(utf8.decoder).join(),
          contains('href="/"'),
        );
      }
      final response = await (await client.getUrl(url('/s/single/f/'))).close();
      expect(response.statusCode, 200);
      expect(await response.transform(utf8.decoder).join(), 'exact-file-bytes');
    },
  );

  test(
    'app peer catalog uses the production HTTP catalog and tree routes',
    () async {
      final folderShare = await services.sharePath(folder.path);
      await services.store.upsertShare(
        record('private-app', mode: ShareMode.password),
      );
      final peerClient = services.peerShareClient(services.identity.peerId);
      addTearDown(peerClient.close);
      final result = await peerClient.catalog();
      expect(result.name, 'Catalog Owner');
      expect(result.shares.where((s) => s.id == folderShare.id).length, 1);
      expect(
        result.shares.firstWhere((s) => s.access == 'password').id,
        isNull,
      );
      final files = await peerClient.browse(folderShare.id);
      expect(files.entries.single.name, 'report.txt');
      final response = await (await client.getUrl(
        url(
          '/s/${folderShare.id.value}/f/${files.entries.single.itemKey.value}',
        ),
      )).close();
      expect(await response.transform(utf8.decoder).join(), 'exact-file-bytes');
    },
  );

  test(
    'stop, resume, rename and delete update the root without touching files',
    () async {
      final share = await services.sharePath(folder.path);
      expect((await catalog())['shares'], hasLength(1));
      await services.shares.stop(share.id);
      expect((await catalog())['shares'], isEmpty);
      await (services.shares as ShareResumable).resume(share.id);
      await services.shares.rename(share.id, '<script>renamed</script>');
      expect(
        (await catalog())['shares'][0]['name'],
        '<script>renamed</script>',
      );
      await (services.shares as ShareDeletable).delete(share.id);
      expect((await catalog())['shares'], isEmpty);
      expect(
        File(p.join(folder.path, 'report.txt')).readAsStringSync(),
        'exact-file-bytes',
      );
    },
  );

  test('public groups preserve manual order, filter links and exclude private transfers', () async {
    for (final share in [
      record('folder'),
      record('file', kind: 'file', rootUri: p.join(folder.path, 'report.txt')),
      record('other'),
      record('ephemeral', ephemeral: true),
    ]) {
      await services.store.upsertShare(share);
    }
    final layout = ShareOrganization(
      names: {'work': 'Work', 'hidden': 'Private transfer'},
      assignments: {'folder': 'work', 'file': 'work', 'ephemeral': 'hidden'},
      order: ['file', 'folder'],
      groupOrder: ['work', ''],
    );
    final source = StoreShareOrganizationSource(services.store);
    await source.save(layout);
    final all = await catalog();
    expect((all['shares'] as List).map((e) => e['name']), [
      'file',
      'folder',
      'other',
    ]);
    expect(all['groups'], [
      {'id': 'work', 'name': 'Work'},
      {'id': '', 'name': '未分组'},
    ]);
    expect(all['order'], 'owner');
    final grouped = await catalog(group: 'work');
    expect((grouped['shares'] as List).map((e) => e['name']), [
      'file',
      'folder',
    ]);
    expect((await catalog(group: ''))['shares'], hasLength(1));
    await source.save(layout.copyWith(names: {'work': 'Renamed'}));
    expect((await catalog(group: 'work'))['shares'], hasLength(2));
    await source.save(layout.removeGroup('work'));
    final response = await (await client.getUrl(
      url('/api/v1/shared-roots?unused').replace(
        path: '/api/v1/shared-roots',
        queryParameters: {'group': 'work'},
      ),
    )).close();
    expect(response.statusCode, 404);
    await response.drain<void>();
    expect((await catalog())['shares'], hasLength(3));
  });
}
