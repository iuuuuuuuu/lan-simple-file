// SPDX-License-Identifier: GPL-3.0-only
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/net/peer_local_domain.dart';
import 'package:lan_simple_file/core/platform/browser_link_policy.dart';
import 'package:lan_simple_file/core/platform/peer_browser_links.dart';

void main() {
  final self = PeerId.parse('p_selfdevice001');
  final other = PeerId.parse('p_otherdevice01');
  PeerView view(PeerId id, {String name = 'Phone', bool online = true}) =>
      PeerView(
        peerId: id,
        name: name,
        avatarHash: '',
        online: online,
        shareCount: 0,
        lastSeen: DateTime(2026),
      );

  late StreamController<List<PeerView>> peers;
  late PeerBrowserLinks links;
  late DateTime now;
  late List<String> repaired;
  var calls = 0;
  PeerLocalDomain? result;
  setUp(() {
    now = DateTime(2026);
    repaired = [];
    calls = 0;
    result = (host: 'phone.local', port: 47778);
    peers = StreamController<List<PeerView>>.broadcast(sync: true);
    links = PeerBrowserLinks(
      self: self,
      clock: () => now,
      domainForPeer: (_) async {
        calls++;
        return result;
      },
      policy: BrowserLinkPolicy(
        proxyQuery: () async => const WindowsBrowserProxy(
          enabled: true,
          server: 'proxy',
          bypass: '10.*;<local>',
        ),
        proxyRepair: (domain) async {
          repaired.add(domain);
          return WindowsBrowserProxy(
            enabled: true,
            server: 'proxy',
            bypass: '10.*;<local>;$domain',
          );
        },
      ),
    )..start(peers.stream);
  });
  tearDown(() async {
    await links.dispose();
    await peers.close();
  });

  test('discovery repairs exact peer domains, deduplicates, and skips self/offline', () async {
    peers.add([
      view(self),
      view(other),
      view(PeerId.parse('p_offlinedevice'), online: false),
    ]);
    await links.refresh();
    expect(repaired, ['phone.local']);
    peers.add([view(self), view(other)]);
    await links.refresh();
    expect(calls, 1);
  });
  test(
    'rename refreshes immediately and periodic checks repair changed proxies',
    () async {
      peers.add([view(other)]);
      await links.refresh();
      result = (host: 'renamed.local', port: 47778);
      peers.add([view(other, name: 'Renamed')]);
      await links.refresh();
      expect(repaired, ['phone.local', 'renamed.local']);
      now = now.add(const Duration(minutes: 3));
      await links.refresh();
      expect(repaired.last, 'renamed.local');
      expect(calls, 3);
    },
  );
  test(
    'failed metadata is retried; reconnect is checked immediately',
    () async {
      result = null;
      peers.add([view(other)]);
      await links.refresh();
      expect(repaired, isEmpty);
      result = (host: 'phone.local', port: 47778);
      now = now.add(const Duration(seconds: 31));
      await links.refresh();
      expect(repaired, ['phone.local']);
      peers.add([view(other, online: false)]);
      await links.refresh();
      peers.add([view(other)]);
      await links.refresh();
      expect(calls, 3);
    },
  );
  test(
    'shutdown waits for pending metadata and prevents proxy mutation',
    () async {
      await links.dispose();
      final pending = Completer<PeerLocalDomain?>();
      links = PeerBrowserLinks(
        self: self,
        domainForPeer: (_) => pending.future,
        policy: links.policy,
      )..start(peers.stream);
      peers.add([view(other)]);
      final stopping = links.dispose();
      pending.complete((host: 'phone.local', port: 80));
      await stopping;
      expect(repaired, isEmpty);
    },
  );
}
