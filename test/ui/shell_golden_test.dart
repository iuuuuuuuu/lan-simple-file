// SPDX-License-Identifier: GPL-3.0-only

/// 视觉证据：把三栏外壳真实光栅化成 PNG（明/暗两套 + hover 态）。
///
/// 生成方式（会写文件，不参与常规断言）：
///   flutter test test/ui/shell_golden_test.dart --update-goldens
/// 产物在 test/ui/goldens/ 下，可直接打开肉眼确认设计语言。
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/theme/app_theme.dart';
import 'package:lan_simple_file/app/theme/tokens.dart';
import 'package:lan_simple_file/ui/shell/qq_shell.dart';
import 'package:lan_simple_file/ui/shell/session_list.dart';
import 'package:lan_simple_file/ui/shell/session_rail.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';

import 'chat_workspace_test.dart' show ChatTestService;
import 'support/golden_fonts.dart';

/// 演示用会话来源：喂一组有代表性的数据（在线/离线/群/未读）。
final class DemoSource implements ShellSessionSource {
  @override
  Future<List<SessionRowData>> rowsFor(ShellSection section) async {
    switch (section) {
      case ShellSection.nearby:
        return <SessionRowData>[
          SessionRowData(
            id: 'p_aaaaaaaaaaaaa',
            peerId: 'p_aaaaaaaaaaaaa',
            title: 'YG 的台式机',
            avatarSeed: 'p_7fk3m9x2a1c01',
            subtitle: '7 项共享',
            os: 'windows',
            timeLabel: '14:23',
            online: true,
          ),
          SessionRowData(
            id: 'p2',
            peerId: 'p_7fk3m9x2a1c02',
            title: '小米手机',
            avatarSeed: 'p_7fk3m9x2a1c02',
            subtitle: '3 项共享',
            os: 'android',
            timeLabel: '13:07',
            unread: 5,
            online: true,
          ),
          SessionRowData(
            id: 'p3',
            peerId: 'p_7fk3m9x2a1c03',
            title: '客厅笔电',
            avatarSeed: 'p_7fk3m9x2a1c03',
            subtitle: '离线 · 暂无共享',
            timeLabel: '昨天',
            online: false,
            os: 'macos',
          ),
          SessionRowData(
            id: 'p4',
            peerId: 'p_7fk3m9x2a1c04',
            title: '开发机',
            avatarSeed: 'p_7fk3m9x2a1c04',
            subtitle: '12 项共享',
            timeLabel: '11/02',
            unread: 128,
            online: true,
            os: 'linux',
          ),
        ];
      case ShellSection.groups:
        return <SessionRowData>[
          SessionRowData(
            id: 'g_family',
            title: '家庭群',
            avatarSeed: 'g_family01',
            subtitle: '妈妈：晚上回来吃饭吗',
            timeLabel: '18:02',
            unread: 2,
            isGroup: true,
          ),
          SessionRowData(
            id: 'g2',
            title: '项目组',
            avatarSeed: 'g_project1',
            subtitle: '[文件] 设计稿v3.zip',
            timeLabel: '16:44',
            isGroup: true,
          ),
        ];
      default:
        return const <SessionRowData>[];
    }
  }

  @override
  String titleFor(ShellSection section) => switch (section) {
    ShellSection.nearby => '附近的人',
    ShellSection.shares => '我的分享',
    ShellSection.groups => '群组',
    ShellSection.transfers => '传输',
    ShellSection.settings => '设置',
  };
}

Future<void> pumpDemo(
  WidgetTester tester, {
  required Brightness brightness,
  ShellSection section = ShellSection.nearby,
  ChatTestService? messaging,
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => AppMiuixTheme(child: child!),
      theme: withCjkFont(AppTheme.of(LanFilePalette.of(brightness))),
      home: QqShell(
        sessionSource: DemoSource(),
        initialSection: section,
        enableDragDrop: false,
        messaging: messaging,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await settleGoldenImages(tester);
}

Future<void> pumpGroupChat(WidgetTester tester, Brightness brightness) async {
  final messaging = ChatTestService();
  addTearDown(messaging.updates.close);
  final self = PeerId.parse('p_localdevice00');
  final peer = PeerId.parse('p_aaaaaaaaaaaaa');
  messaging.messages['g_family'] = [
    for (final entry in [
      (peer, '周末的照片已经整理好了，稍后分享给大家。'),
      (self, '好呀，我把聚餐的安排也放在这里。'),
      (peer, '收到！'),
    ].indexed)
      MessageRecord(
        id: '${entry.$2.$1.value}:${entry.$1 + 1}',
        threadId: 'g_family',
        senderPeerId: entry.$2.$1,
        kind: MessageKind.text,
        hlc: Hlc(millis: 1, counter: entry.$1, origin: entry.$2.$1.value),
        ts: DateTime(2026, 11, 4, 14, 18 + entry.$1),
        body: entry.$2.$2,
        attachJson: '',
        sig: '',
      ),
  ];
  await pumpDemo(tester, brightness: brightness, messaging: messaging);
  await tester.tap(find.byKey(const ValueKey('session-row-g_family')));
  await tester.pumpAndSettle();
  await settleGoldenImages(tester);
}

void main() {
  setUpAll(() async {
    await loadGoldenFonts();
  });

  for (final brightness in Brightness.values) {
    testWidgets('手机 ID 列表 ${brightness.name}', (tester) async {
      await pumpDemo(
        tester,
        brightness: brightness,
        size: const Size(360, 800),
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(QqShell),
        matchesGoldenFile('goldens/nearby_mobile_${brightness.name}.png'),
      );
    });
  }

  testWidgets('演示数据里的未读数确实渲染为 5 与 99+（防止截图误读）', (WidgetTester tester) async {
    await pumpDemo(tester, brightness: Brightness.light);
    // 视觉上徽标很小，容易被 OCR 误认；这里用真实文本断言锁定。
    expect(find.text('5'), findsOneWidget);
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('明色三栏', (WidgetTester tester) async {
    await pumpDemo(tester, brightness: Brightness.light);
    await expectLater(
      find.byType(QqShell),
      matchesGoldenFile('goldens/shell_light.png'),
    );
  });

  testWidgets('暗色三栏', (WidgetTester tester) async {
    await pumpDemo(tester, brightness: Brightness.dark);
    await expectLater(
      find.byType(QqShell),
      matchesGoldenFile('goldens/shell_dark.png'),
    );
  });

  testWidgets('明色分组与群聊天', (WidgetTester tester) async {
    await pumpGroupChat(tester, Brightness.light);
    await expectLater(
      find.byType(QqShell),
      matchesGoldenFile('goldens/shell_groups_light.png'),
    );
  });

  testWidgets('暗色分组与群聊天', (WidgetTester tester) async {
    await pumpGroupChat(tester, Brightness.dark);
    await expectLater(
      find.byType(QqShell),
      matchesGoldenFile('goldens/shell_groups_dark.png'),
    );
  });
}
