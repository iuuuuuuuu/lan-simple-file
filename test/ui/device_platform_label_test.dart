// SPDX-License-Identifier: GPL-3.0-only
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/theme/app_theme.dart';
import 'package:lan_simple_file/app/theme/tokens.dart';
import 'package:lan_simple_file/app/widgets/identicon.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/ui/shell/qq_shell.dart';
import 'package:lan_simple_file/ui/shell/session_list.dart';
import 'package:lan_simple_file/ui/shell/session_rail.dart';
import 'package:lan_simple_file/ui/widgets/device_platform_label.dart';
import 'package:lan_simple_file/ui/widgets/peer_card.dart';

import 'support/golden_fonts.dart';

const labels = {
  'windows': 'Windows',
  'android': 'Android',
  'macos': 'macOS',
  'ios': 'iOS',
  'linux': 'Linux',
};

final class PlatformSource implements ShellSessionSource {
  @override
  String titleFor(ShellSection section) => '附近的人';

  @override
  Future<List<SessionRowData>> rowsFor(ShellSection section) async =>
      section != ShellSection.nearby
      ? []
      : [
          for (final entry in labels.entries)
            SessionRowData(
              id: entry.key,
              title: entry.key == 'android'
                  ? 'V2344A'
                  : '${entry.value} device',
              subtitle: entry.key == 'macos' ? '离线 · 0 项共享' : '3 项共享',
              avatarSeed: entry.key,
              os: entry.key,
              online: entry.key != 'macos',
              timeLabel: '11:07',
            ),
        ];
}

Future<void> savePreview(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  if (!const bool.fromEnvironment('WRITE_PLATFORM_PREVIEWS')) return;
  await tester.runAsync(() async {
    final context = key.currentContext!;
    for (final widget in tester.widgetList<Image>(find.byType(Image))) {
      await precacheImage(widget.image, context);
    }
  });
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final raster = await boundary.toImage(pixelRatio: 1);
    final bytes = await raster.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/verification/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    raster.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (const bool.fromEnvironment('WRITE_PLATFORM_PREVIEWS')) {
      await loadGoldenFonts();
    }
    for (final seed in [
      ...labels.keys,
      'local',
      'p_nyhnu4iiynhqs',
      'peer-two',
      'peer-three',
      'peer-four',
    ]) {
      await buildIdenticonPng(seed);
    }
  });

  for (final width in [320.0, 390.0, 1280.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'platform labels fit nearby rows at $width in ${brightness.name}',
        (tester) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final key = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: const bool.fromEnvironment('WRITE_PLATFORM_PREVIEWS')
                  ? withCjkFont(AppTheme.of(LanFilePalette.of(brightness)))
                  : AppTheme.of(LanFilePalette.of(brightness)),
              home: RepaintBoundary(
                key: key,
                child: QqShell(
                  sessionSource: PlatformSource(),
                  enableDragDrop: false,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(DevicePlatformLabel), findsNWidgets(5));
          for (final label in labels.values) {
            expect(find.text(label), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          await savePreview(
            tester,
            key,
            'platform_${width.toInt()}_${brightness.name}',
          );
        },
      );
    }
  }

  testWidgets(
    'platforms remain visible without a timestamp and at larger text scale',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.of(LanFilePalette.light),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 844),
              textScaler: TextScaler.linear(1.5),
            ),
            child: Scaffold(
              body: SessionList(
                title: 'Nearby',
                selectedId: null,
                rows: [
                  for (final os in labels.keys)
                    SessionRowData(
                      id: os,
                      title: 'A very long device nickname',
                      avatarSeed: os,
                      os: os,
                      subtitle: '3 shares',
                    ),
                ],
                onSelect: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DevicePlatformLabel), findsNWidgets(5));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'peer cards show normalized platform labels without duplicating metadata',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.of(LanFilePalette.light),
          home: Scaffold(
            body: SizedBox(
              width: 280,
              child: PeerCard(
                peer: PeerView(
                  peerId: PeerId.parse('p_nyhnu4iiynhqs'),
                  name: 'A long Android nickname',
                  avatarHash: '',
                  online: true,
                  shareCount: 3,
                  lastSeen: DateTime.now(),
                  os: 'android',
                ),
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Android'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('package avatar contact sheet renders nonblank images', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            body: Center(
              child: Wrap(
                spacing: 20,
                runSpacing: 20,
                children: [
                  for (final seed in [
                    'windows',
                    'android',
                    'macos',
                    'linux',
                    'p_nyhnu4iiynhqs',
                    'peer-two',
                    'peer-three',
                    'peer-four',
                  ])
                    Identicon(peerId: seed, size: 112, radius: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNWidgets(8));
    expect(tester.takeException(), isNull);
    await savePreview(tester, key, 'identicons_package');
  });
}
