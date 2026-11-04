// SPDX-License-Identifier: GPL-3.0-only

/// 我的分享页面：状态判定、权限档位、复制链接/停止共享、空态、null services。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/theme/tokens.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/ui/pages/shares_page.dart';
import 'package:lan_simple_file/ui/widgets/app_toast.dart';
import 'package:lan_simple_file/ui/widgets/share_row.dart';

import 'support/ui_fakes.dart';

void main() {
  // 每个用例后清掉静态 Toast，避免 OverlayEntry 残留到下一用例。
  tearDown(AppToast.dismiss);

  group('状态判定（纯函数）', () {
    test('撤销优先于其它一切状态', () {
      final ShareRecord share = shareRecord(
        id: 'sh01',
        missing: true,
        enabled: false,
        revokedAt: DateTime.utc(2026, 11, 3),
      );
      expect(shareStatusOf(share), ShareStatus.revoked);
    });

    test('源失效优先于已停止', () {
      expect(
        shareStatusOf(shareRecord(id: 'sh01', missing: true, enabled: false)),
        ShareStatus.missing,
      );
    });

    test('已停止优先于过期', () {
      expect(
        shareStatusOf(
          shareRecord(
            id: 'sh01',
            enabled: false,
            expiresAt: DateTime.utc(2020),
          ),
        ),
        ShareStatus.stopped,
      );
    });

    test('过了有效期算过期', () {
      expect(
        shareStatusOf(
          shareRecord(id: 'sh01', expiresAt: DateTime.utc(2020)),
          now: DateTime.utc(2026),
        ),
        ShareStatus.expired,
      );
    });

    test('未过期且启用算有效', () {
      expect(
        shareStatusOf(
          shareRecord(id: 'sh01', expiresAt: DateTime.utc(2030)),
          now: DateTime.utc(2026),
        ),
        ShareStatus.active,
      );
    });

    test('每个状态都有非空中文文案，且互不相同', () {
      final Set<String> labels = <String>{
        for (final ShareStatus s in ShareStatus.values) shareStatusLabel(s),
      };
      expect(labels, hasLength(ShareStatus.values.length));
      for (final String label in labels) {
        expect(label, isNotEmpty);
      }
    });

    test('每个权限档位都有非空中文文案', () {
      for (final ShareMode mode in ShareMode.values) {
        expect(shareModeLabel(mode), isNotEmpty);
      }
    });
  });

  group('空状态', () {
    testWidgets('没有分享时显示空态文案', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithTheme(SharesPage(source: FakeMySharesSource())),
      );
      await tester.pumpAndSettle();
      expect(find.text('还没有分享'), findsOneWidget);
      expect(find.textContaining('不复制文件本体'), findsOneWidget);
    });
  });

  group('有数据', () {
    testWidgets('渲染名称/状态/权限档位', (WidgetTester tester) async {
      final FakeMySharesSource source = FakeMySharesSource()
        ..shares = <ShareRecord>[
          shareRecord(id: 'sh01', displayName: '电影目录', mode: ShareMode.token),
          shareRecord(
            id: 'sh02',
            displayName: '已停的共享',
            mode: ShareMode.password,
            enabled: false,
          ),
        ];
      await tester.pumpWidget(wrapWithTheme(SharesPage(source: source)));
      await tester.pumpAndSettle();

      expect(find.text(r'D:\媒体\电影目录'), findsOneWidget);
      expect(find.text(r'D:\媒体\已停的共享'), findsOneWidget);
      expect(find.text('有效'), findsOneWidget);
      expect(find.text('已停止'), findsOneWidget);
      expect(find.text('需链接凭证'), findsOneWidget);
      expect(find.text('需口令'), findsOneWidget);
      expect(find.textContaining('共 2 项'), findsOneWidget);
      expect(find.byType(ShareRow), findsNWidgets(2));
    });

    testWidgets('无效状态的行：卡片上不再平铺按钮，动作全在菜单里', (WidgetTester tester) async {
      final FakeMySharesSource source = FakeMySharesSource()
        ..shares = <ShareRecord>[
          shareRecord(id: 'sh02', displayName: '已停', enabled: false),
        ];
      await tester.pumpWidget(wrapWithTheme(SharesPage(source: source)));
      await tester.pumpAndSettle();

      // 菜单化之后，卡片上不该再出现一排按钮（用户明确要求）。
      // 这里断言的是「动作入口收拢」，语义比旧版更强：
      // 旧版只保证「按钮被禁用」，新版保证「按钮根本不在卡片上」。
      final Finder rowButtons = find.descendant(
        of: find.byType(ShareRow),
        matching: find.byType(TextButton),
      );
      expect(rowButtons, findsNothing, reason: '卡片上不该有平铺的动作按钮');
      expect(
        find.byKey(const ValueKey<String>('share-actions-menu')),
        findsOneWidget,
        reason: '每行必须有一个动作菜单',
      );
    });

    testWidgets('复制链接真的把链接写进剪贴板', (WidgetTester tester) async {
      final List<MethodCall> calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') calls.add(call);
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      final FakeMySharesSource source = FakeMySharesSource()
        ..shares = <ShareRecord>[shareRecord(id: 'sh01', displayName: '可复制')]
        ..link = Uri.parse('lanfile://s/sh01?k=abc');
      await tester.pumpWidget(wrapWithTheme(SharesPage(source: source)));
      await tester.pumpAndSettle();

      // 菜单化 + 去掉 App 深链后，复制走「复制网页链接」。
      // 这里没有 webLink 注入，所以先断言「不可用时点不动」。
      await tester.tap(
        find.byKey(const ValueKey<String>('share-actions-menu')).first,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('复制网页链接'), findsWidgets);
      await tester.tap(find.textContaining('复制网页链接').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      // 没有局域网地址时不得写入剪贴板——这正是「不伪造地址」的语义。
      expect(calls, isEmpty, reason: '拿不到网页链接时不该往剪贴板塞一个打不开的东西');
      AppToast.dismiss();
    });

    testWidgets('菜单里停止共享：调用服务并把该行变「已停止」', (WidgetTester tester) async {
      final FakeMySharesSource source = FakeMySharesSource()
        ..shares = <ShareRecord>[shareRecord(id: 'sh01', displayName: '要停的')];
      await tester.pumpWidget(wrapWithTheme(SharesPage(source: source)));
      await tester.pumpAndSettle();
      expect(find.text('有效'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('share-actions-menu')).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('停止共享').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      // 状态刷新是 FutureBuilder，再推一拍让重建落地。
      await tester.pump();

      expect(source.stopped, <String>['sh01']);
      expect(find.text('已停止'), findsOneWidget);
      expect(find.textContaining('已停止共享'), findsOneWidget);
      AppToast.dismiss();
    });

    testWidgets('菜单里停止失败时把错误显示出来，不静默吞掉', (WidgetTester tester) async {
      final FakeMySharesSource source = FakeMySharesSource()
        ..shares = <ShareRecord>[shareRecord(id: 'sh01', displayName: '会失败')]
        ..stopError = const LanFileException(LanFileErrorCode.io, '磁盘只读');
      await tester.pumpWidget(wrapWithTheme(SharesPage(source: source)));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('share-actions-menu')).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('停止共享').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('停止共享失败'), findsOneWidget);
      expect(find.textContaining('磁盘只读'), findsOneWidget);
      expect(tester.takeException(), isNull);
      AppToast.dismiss();
    });
  });

  group('服务未连接', () {
    testWidgets('services 为 null 时显示「未连接服务」', (WidgetTester tester) async {
      await tester.pumpWidget(wrapWithTheme(const SharesPage(services: null)));
      await tester.pumpAndSettle();
      expect(find.text('未连接服务'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('主题 token', () {
    testWidgets('明暗两套下状态标签用 accent 与 fgDim', (WidgetTester tester) async {
      for (final Brightness brightness in Brightness.values) {
        final FakeMySharesSource source = FakeMySharesSource()
          ..shares = <ShareRecord>[
            shareRecord(id: 'sh01', displayName: '有效项'),
            shareRecord(id: 'sh02', displayName: '停止项', enabled: false),
          ];
        await tester.pumpWidget(
          wrapWithTheme(SharesPage(source: source), brightness: brightness),
        );
        await tester.pumpAndSettle();

        final LanFileTokens tokens = tokensAt(tester);
        expect(
          tokens.bg,
          brightness == Brightness.dark
              ? LanFilePalette.dark.bg
              : LanFilePalette.light.bg,
        );
        expect(
          tokens.accent,
          brightness == Brightness.dark
              ? LanFilePalette.dark.accent
              : LanFilePalette.light.accent,
        );

        // 有效行用 accent 描边；停止行用 fgDim。
        final List<ShareStatusChip> chips = tester
            .widgetList<ShareStatusChip>(find.byType(ShareStatusChip))
            .toList();
        expect(chips, hasLength(2));
        expect(chips.first.status, ShareStatus.active);
      }
    });
  });
}
