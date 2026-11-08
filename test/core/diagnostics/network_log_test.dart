// SPDX-License-Identifier: GPL-3.0-only
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/network_diagnostics.dart';
import 'package:lan_simple_file/core/diagnostics/network_log.dart';
import 'package:lan_simple_file/core/discovery/announce_service_impl.dart';
import 'package:lan_simple_file/core/discovery/udp_channel.dart';
import 'package:lan_simple_file/core/server/http_server_host.dart';
import 'package:lan_simple_file/core/server/router.dart';

void main() {
  late Directory temp;
  late NetworkLog log;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lan-diagnostics-test-');
    log = NetworkLog(Directory('${temp.path}/logs'));
    NetworkLog.active = log;
  });
  tearDown(() async {
    NetworkLog.active = null;
    await log.close();
    await temp.delete(recursive: true);
  });
  Future<String> exported() async =>
      (await log.export(Directory('${temp.path}/export'))).readAsString();

  test(
    'redacts secrets while retaining socket errno and actual target',
    () async {
      log.add('udp.send_error', {
        'target': '239.255.77.77',
        'token': 'secret-token',
        'nested': {
          'Authorization': 'secret-header',
          'filePath': '/private/file',
        },
        ...NetworkLog.errorFields(
          const SocketException(
            'Send failed',
            osError: OSError('Operation not permitted', 1),
          ),
        ),
      });
      log.add('other', {
        'url': 'http://host/s/x?k=cap-secret',
        'detail': 'token=abc123 Bearer xyz987',
      });
      final text = await exported();
      for (final secret in [
        'secret-token',
        'secret-header',
        '/private/file',
        'cap-secret',
        'abc123',
        'xyz987',
      ]) {
        expect(text, isNot(contains(secret)));
      }
      expect(text, contains('239.255.77.77'));
      expect(text, contains('"errno":1'));
      expect(text, contains('Operation not permitted'));
    },
  );

  test('rotation bounds storage and retains evidence across restart', () async {
    await log.close();
    log = NetworkLog(Directory('${temp.path}/logs'), maxBytes: 600);
    for (var i = 0; i < 35; i++) {
      log.add('sample', {'sequence': i, 'padding': 'x' * 100});
    }
    await log.close();
    final files = await log.directory
        .list()
        .where((f) => f is File)
        .cast<File>()
        .toList();
    expect(files.length, 3);
    for (final file in files) {
      expect(await file.length(), lessThanOrEqualTo(600));
      for (final line in await file.readAsLines()) {
        expect(jsonDecode(line), isMap);
      }
    }
    log = NetworkLog(Directory('${temp.path}/logs'), maxBytes: 600);
    log.add('restart');
    final text = await exported();
    expect(text, contains('"sequence":34'));
    expect(text, contains('restart'));
    expect(text, isNot(contains('"sequence":0,')));
  });

  test('packet storm cannot grow the pending buffer without bound', () async {
    for (var i = 0; i < 10000; i++) {
      log.add('storm', {'i': i});
    }
    final text = await exported();
    expect('"event":"storm"'.allMatches(text).length, NetworkLog.maxPending);
    expect(text, contains('"count":9872'));
  });

  test('export reports a journal write failure', () async {
    await log.close();
    final blocker = File('${temp.path}/blocker');
    await blocker.writeAsString('file');
    log = NetworkLog(Directory(blocker.path));
    log.add('cannot_write');
    await expectLater(exported(), throwsA(isA<FileSystemException>()));
  });

  test('unwritable export destination reports failure without breaking later export', () async {
    log.add('before-export');
    final blocked = Directory('${temp.path}/blocked');
    await Directory('${blocked.path}/lan-network-diagnostics.txt')
        .create(recursive: true);
    await expectLater(log.export(blocked), throwsA(isA<FileSystemException>()));
    log.add('after-export-failure');
    final text = await exported();
    expect(text, contains('before-export'));
    expect(text, contains('after-export-failure'));
  });

  test('transport failures are separate from malformed packet totals', () {
    final counter = MutableRejectedCounter();
    for (var i = 0; i < 30; i++) {
      counter.recordTransportError(StateError('socket closed'));
    }
    expect(counter.malformed, 0);
    expect(counter.totalRejected, 0);
    expect(counter.recentReasons, isEmpty);
    expect(counter.transportErrors, 30);
    expect(counter.transportReasons.length, MutableRejectedCounter.maxReasons);
    counter.recordMalformed('invalid JSON');
    expect(counter.malformed, 1);
    counter.reset();
    expect(counter.transportErrors, 0);
    expect(counter.transportReasons, isEmpty);
  });

  test(
    'real UDP logs destination and receive metadata without contents',
    () async {
      final receiver = UdpChannel(port: 0, onError: (_, _) {});
      final sender = UdpChannel(port: 0, onError: (_, _) {});
      try {
        await receiver.bind();
        await sender.bind();
        sender.sendTo(
          Uint8List.fromList(utf8.encode('private-message-content')),
          InternetAddress.loopbackIPv4,
          receiver.boundPort!,
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));
        final text = await exported();
        expect(text, contains('udp.unicast'));
        expect(text, contains('udp.receive'));
        expect(text, contains('127.0.0.1'));
        expect(text, isNot(contains('private-message-content')));
      } finally {
        await sender.close();
        await receiver.close();
      }
    },
  );

  test(
    'real HTTP checks record status without response bodies or private URLs',
    () async {
      final router = Router()
        ..get('/', (request) async {
          request.response.write('private-share-list');
          await request.response.close();
        });
      final server = HttpServerHost(router: router, preferredPort: 0);
      final port = await server.start();
      try {
        await NetworkDiagnostics(log).checkHttp('127.0.0.1', port);
        final client = HttpClient();
        try {
          final request = await client.getUrl(
            Uri.parse('http://127.0.0.1:$port/private-path?k=private-token'),
          );
          await (await request.close()).drain<void>();
        } finally {
          client.close(force: true);
        }
        final text = await exported();
        expect(text, contains('http.self_check'));
        expect(text, contains('"status":200'));
        expect(text, contains('http.request'));
        for (final secret in [
          'private-share-list',
          'private-path',
          'private-token',
        ]) {
          expect(text, isNot(contains(secret)));
        }
      } finally {
        await server.stop();
      }
    },
  );
}
