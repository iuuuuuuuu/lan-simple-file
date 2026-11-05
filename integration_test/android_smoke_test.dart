// SPDX-License-Identifier: GPL-3.0-only
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lan_simple_file/app/app.dart';
import 'package:lan_simple_file/app/branding/app_logo.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/app/assembly.dart';
import 'package:lan_simple_file/core/messaging/messaging_service_impl.dart';
import 'package:lan_simple_file/ui/widgets/chat_pane.dart';
import 'package:lan_simple_file/app/theme/app_theme.dart';
import 'package:lan_simple_file/platform/android/foreground_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('MuMu UI、下载、聊天撤回、重启持久化、前台服务', (tester) async {
    final temp = await Directory.systemTemp.createTemp('lsf_android_test_');
    AppServices? services;
    final client = HttpClient();
    try {
      services = await AppAssembler.assemble(
        dataDir: temp,
        httpPortOverride: 0,
        udpPortOverride: 0,
        enableDiscovery: false,
      );
      await services.renameSelf('MuMu测试设备');
      await tester.pumpWidget(
        ProviderScope(child: LanFileApp(services: services)),
      );
      await tester.pumpAndSettle();
      expect(find.text('附近的人'), findsWidgets);
      expect(find.byKey(const ValueKey('mobile-navigation')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mobile-nav-settings')));
      await tester.pumpAndSettle();
      final rectangles = AppLogo.values
          .map(
            (logo) => tester.getRect(
              find.byKey(ValueKey('logo-option-${logo.name}')),
            ),
          )
          .toList();
      expect(rectangles.map((r) => r.height).toSet().length, 1);
      for (final count in [5, 101, 0]) {
        await services.store.upsertThread(
          ThreadRecord(
            id: 'badge_test',
            kind: 'direct',
            title: '未读测试',
            avatarHash: '',
            unread: count,
            muted: false,
            pinned: false,
            createdAt: DateTime.now(),
          ),
        );
        await services.messaging.refreshThreads();
        await tester.pumpAndSettle();
        final badge = find.byKey(const ValueKey('mobile-chat-unread'));
        if (count == 0) {
          expect(badge, findsNothing);
        } else {
          expect(
            find.descendant(
              of: badge,
              matching: find.text(count > 99 ? '99+' : '$count'),
            ),
            findsOneWidget,
          );
        }
      }
      await tester.tap(find.byKey(const ValueKey('mobile-nav-nearby')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final file = File('${temp.path}/sample.txt');
      await file.writeAsString('安卓实际下载内容');
      final share = await services.sharePath(file.path);
      final response = await (await client.getUrl(
        Uri.parse('http://127.0.0.1:${services.port}/s/${share.id.value}/f/'),
      )).close();
      expect(response.statusCode, 200);
      expect(await response.transform(utf8.decoder).join(), '安卓实际下载内容');
      final thread = directThreadId(
        services.identity.peerId,
        services.identity.peerId,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ChatPane(
              threadId: thread,
              title: '本机',
              self: services.identity.peerId,
              avatarSeed: 'self',
              messaging: services.messaging,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('chat-input')),
        'MuMu消息',
      );
      await tester.tap(find.byKey(const ValueKey('chat-send')));
      await tester.pumpAndSettle();
      expect(find.text('MuMu消息'), findsOneWidget);
      await tester.tap(find.text('撤回'));
      await tester.pumpAndSettle();
      expect(find.text('消息已撤回'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final before = services.identity.peerId;
      await tester.pumpWidget(const SizedBox.shrink());
      await services.stop();
      services = null;
      services = await AppAssembler.assemble(
        dataDir: temp,
        httpPortOverride: 0,
        udpPortOverride: 0,
        enableDiscovery: false,
      );
      expect(services.identity.peerId, before);
      expect(services.profile.name, 'MuMu测试设备');
      expect((await services.store.findShare(share.id))!.rootUri, file.path);
      expect(
        (await services.store.listMessages(thread)).single.isRevoked,
        true,
      );
      final fg = const ForegroundServiceBridge();
      await fg.apply(
        const ForegroundServiceState(running: true, shareCount: 1),
      );
      expect(await fg.isRunning(), true);
      await fg.apply(ForegroundServiceState.stopped);
      expect(await fg.isRunning(), false);
    } finally {
      client.close(force: true);
      await tester.pumpWidget(const SizedBox.shrink());
      await services?.stop();
      await temp.delete(recursive: true);
    }
  });
}
