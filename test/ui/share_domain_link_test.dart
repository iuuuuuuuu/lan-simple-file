// SPDX-License-Identifier: GPL-3.0-only

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/miuix_test_support.dart';

import 'package:lan_simple_file/app/assembly.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/net/local_domain.dart';
import 'package:lan_simple_file/ui/pages/shares_page.dart';
import 'package:lan_simple_file/ui/widgets/app_toast.dart';
import 'package:lan_simple_file/ui/widgets/qr_panel.dart';

import 'support/ui_fakes.dart' show wrapWithTheme;

AppServices _withDomain(
  AppServices base,
  LocalDomainService domain, {
  int port = 47779,
}) => AppServices(
  identity: base.identity,
  store: base.store,
  codec: base.codec,
  keys: base.keys,
  revocation: base.revocation,
  profile: base.profile,
  lanHost: '10.1.2.3',
  announce: base.announce,
  discovery: base.discovery,
  shares: base.shares,
  remoteFiles: base.remoteFiles,
  offers: base.offers,
  messaging: base.messaging,
  webShare: base.webShare,
  server: base.server,
  tracker: base.tracker,
  port: port,
  localDomain: domain,
);

Future<void> _settleIo(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  final mdnsStates = <String, ({bool ready, String? error})>{
    'ready': (ready: true, error: null),
    'pending': (ready: false, error: 'Domain registration pending'),
    'failed': (ready: false, error: 'Multicast unavailable'),
  };

  for (final entry in mdnsStates.entries) {
    testWidgets(
      'IP links work with mDNS ${entry.key} in display, copy and QR',
      (tester) async {
        final sandbox = Directory.systemTemp.createTempSync('lsf_domain_ui_');
        final base = (await tester.runAsync(
          () => AppAssembler.assemble(
            dataDir: Directory('${sandbox.path}/data'),
            httpPortOverride: 0,
            udpPortOverride: 0,
            enableDiscovery: false,
          ),
        ))!;
        final domain =
            LocalDomainService(
                username: () => 'Alice',
                deviceId: base.identity.peerId.value,
                address: () async => '10.1.2.3',
                multicast: false,
              )
              ..host = 'alice.local'
              ..ip = '10.1.2.3'
              ..ready = entry.value.ready
              ..error = entry.value.error;
        final services = _withDomain(base, domain);
        addTearDown(() async {
          AppToast.dismiss();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() async {
            await domain.stop();
            await base.stop();
          });
          sandbox.deleteSync(recursive: true);
        });
        final file = File('${sandbox.path}/report.txt')
          ..writeAsStringSync('original');
        final share = (await tester.runAsync(() => base.sharePath(file.path)))!;
        final copied = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied.add((call.arguments as Map)['text'] as String);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );

        await tester.pumpWidget(wrapWithTheme(SharesPage(services: services)));
        await _settleIo(tester);
        expect(find.text('http://10.1.2.3:47779/'), findsOneWidget);
        expect(find.textContaining('alice.local'), findsNothing);
        await tester.tap(findAppTooltip('复制我的分享地址'));
        await tester.pump();
        expect(copied, ['http://10.1.2.3:47779/']);
        await tester.tap(findAppTooltip('我的分享二维码'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<QrPanel>(find.byType(QrPanel)).linkText,
          'http://10.1.2.3:47779/',
        );
        await tester.tap(findAppTooltip('关闭'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('share-actions-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('复制网页链接').last);
        await _settleIo(tester);
        expect(copied.last, 'http://10.1.2.3:47779/s/${share.id.value}');
        final tokenLink = await services.buildWebLink(
          share.id,
          token: 'signed',
        );
        expect(tokenLink.host, '10.1.2.3');
        expect(tokenLink.port, 47779);
        expect(tokenLink.path, '/s/${share.id.value}');
        expect(tokenLink.queryParameters['k'], 'signed');

        final peer = PeerId.parse('p_otherdevice01');
        services.tracker.touch(
          AnnouncePacket(
            version: LanFileConstants.protocolVersion,
            peerId: peer,
            name: 'Other device',
            avatarHash: '',
            port: 47780,
            ip: '10.1.2.5',
            shareCount: 1,
            capabilities: const {'chat'},
            mode: 'serving',
            timestamp: DateTime.now().millisecondsSinceEpoch,
            signature: 'test-signature',
          ),
        );
        expect(
          (await services.buildPeerWebHomeLink(peer)).toString(),
          'http://10.1.2.5:47780/',
        );
        expect(
          (await services.buildPeerWebLink(peer, share.id)).toString(),
          'http://10.1.2.5:47780/s/${share.id.value}',
        );
        expect(
          await services.buildPeerWebHomeLink(services.identity.peerId),
          await services.buildWebHomeLink(),
        );
        expect(
          await services.buildPeerWebLink(services.identity.peerId, share.id),
          await services.buildWebLink(share.id),
        );
        await expectLater(
          services.buildPeerWebHomeLink(PeerId.parse('p_offlinedevice')),
          throwsA(isA<LanFileException>()),
        );

        domain
          ..ready = false
          ..ip = '10.1.2.4'
          ..error = 'Domain registration pending';
        await tester.tap(findAppTooltip('刷新'));
        await _settleIo(tester);
        expect(find.text('http://10.1.2.4:47779/'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('share-actions-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('复制网页链接').last);
        await _settleIo(tester);
        expect(copied.last, 'http://10.1.2.4:47779/s/${share.id.value}');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
