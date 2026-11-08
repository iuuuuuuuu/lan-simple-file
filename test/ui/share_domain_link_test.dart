// SPDX-License-Identifier: GPL-3.0-only

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/miuix_test_support.dart';

import 'package:lan_simple_file/app/assembly.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/net/local_domain.dart';
import 'package:lan_simple_file/core/platform/browser_link_policy.dart';
import 'package:lan_simple_file/ui/pages/shares_page.dart';
import 'package:lan_simple_file/ui/widgets/app_toast.dart';
import 'package:lan_simple_file/ui/widgets/qr_panel.dart';

import 'support/ui_fakes.dart' show wrapWithTheme;

AppServices _withDomain(
  AppServices base,
  LocalDomainService domain,
  BrowserLinkPolicy policy,
) => AppServices(
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
  port: 80,
  localDomain: domain,
  browserLinkPolicy: policy,
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
  final policies = <String, BrowserLinkPolicy>{
    'unknown proxy': BrowserLinkPolicy(proxyQuery: () async => null),
    'query failure': BrowserLinkPolicy(
      proxyQuery: () async =>
          throw const ProcessException('powershell.exe', []),
    ),
    'repair failure': BrowserLinkPolicy(
      proxyQuery: () async =>
          const WindowsBrowserProxy(enabled: true, server: 'proxy', bypass: ''),
      proxyRepair: (_) async =>
          throw const ProcessException('powershell.exe', []),
    ),
    'PAC': BrowserLinkPolicy(
      proxyQuery: () async => const WindowsBrowserProxy(
        enabled: true,
        server: 'proxy',
        bypass: '',
        autoConfigUrl: 'http://proxy/pac',
      ),
      proxyRepair: (_) async => throw StateError('PAC must not be changed'),
    ),
  };

  for (final entry in policies.entries) {
    testWidgets('owned domain survives ${entry.key} in display, copy and QR', (
      tester,
    ) async {
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
            ..ready = true;
      final services = _withDomain(base, domain, entry.value);
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
      expect(find.text('http://alice.local/'), findsOneWidget);
      expect(find.textContaining('10.1.2.3'), findsNothing);
      await tester.tap(findAppTooltip('复制我的分享地址'));
      await tester.pump();
      expect(copied, ['http://alice.local/']);
      await tester.tap(findAppTooltip('我的分享二维码'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<QrPanel>(find.byType(QrPanel)).linkText,
        'http://alice.local/',
      );
      await tester.tap(findAppTooltip('关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('share-actions-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制网页链接').last);
      await _settleIo(tester);
      expect(copied.last, 'http://alice.local/s/${share.id.value}');
      final tokenLink = await services.buildWebLink(share.id, token: 'signed');
      expect(tokenLink.host, 'alice.local');
      expect(tokenLink.queryParameters['k'], 'signed');

      domain
        ..ready = false
        ..error = 'Domain registration pending';
      await expectLater(
        services.buildWebHomeLink(),
        throwsA(
          isA<LanFileException>().having(
            (error) => error.code,
            'code',
            LanFileErrorCode.providerOffline,
          ),
        ),
      );
      domain.ready = true;
      final changingServices = _withDomain(
        base,
        domain,
        BrowserLinkPolicy(
          proxyQuery: () async {
            domain.ready = false;
            return null;
          },
        ),
      );
      await expectLater(
        changingServices.buildWebHomeLink(),
        throwsA(isA<LanFileException>()),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
