// SPDX-License-Identifier: GPL-3.0-only

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/assembly.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/shares/share_service_impl.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory sandbox;
  late Directory folder;
  late AppServices services;
  late HttpClient client;

  Uri url(String path) =>
      Uri(scheme: 'http', host: '127.0.0.1', port: services.port, path: path);

  Future<Map<String, dynamic>> catalog() async {
    final response = await (await client.getUrl(url('/api/v1/shared-roots')))
        .close();
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
      expect(
        entries.map((entry) => entry['name']),
        unorderedEquals(['folder-token', 'file-lan']),
      );
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
}
