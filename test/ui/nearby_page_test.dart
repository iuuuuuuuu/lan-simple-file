// SPDX-License-Identifier: GPL-3.0-only

/// 附近的人页面：空态诊断、有数据渲染、null services 不崩、明暗 token。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/theme/tokens.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/ui/pages/nearby_page.dart';
import 'package:lan_simple_file/ui/widgets/peer_card.dart';

import 'support/ui_fakes.dart';

void main() {
  group('空状态', () {
    testWidgets('没有 peer 时显示可读诊断文案，不是空白', (WidgetTester tester) async {
      final FakeNearbySource source = FakeNearbySource();
      await tester.pumpWidget(wrapWithTheme(NearbyPage(source: source)));
      await tester.pumpAndSettle();

      expect(find.text('附近还没有人'), findsOneWidget);
      // 诊断必须说清可能原因，而不是只说「空」。
      expect(find.textContaining('防火墙'), findsOneWidget);
      expect(find.textContaining('UDP'), findsOneWidget);
      expect(find.text('重新搜索'), findsNothing);
      expect(find.byTooltip('刷新'), findsNothing);
      // 确认不是白屏：什么都没渲染才是失败。
      expect(find.byType(PeerCard), findsNothing);
    });

    testWidgets('后台发现更新会自动显示，且不需要手动刷新', (WidgetTester tester) async {
      final FakeNearbySource source = FakeNearbySource();
      final StreamController<List<PeerView>> updates =
          StreamController<List<PeerView>>.broadcast();
      addTearDown(updates.close);
      await tester.pumpWidget(
        wrapWithTheme(NearbyPage(source: source, peerUpdates: updates.stream)),
      );
      updates.add(const <PeerView>[]);
      await tester.pumpAndSettle();
      updates.add(<PeerView>[peerView(suffix: '01', name: '自动发现')]);
      await tester.pumpAndSettle();
      expect(find.text('自动发现'), findsOneWidget);
      expect(find.text('陌生人 (1)'), findsOneWidget);
      expect(source.refreshes, 0);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('有数据', () {
    testWidgets('渲染头像/名字/分享数/在线文案', (WidgetTester tester) async {
      final FakeNearbySource source = FakeNearbySource()
        ..peers = <dynamic>[
          peerView(suffix: '01', name: 'YG 的台式机', shareCount: 3, os: 'windows'),
          peerView(suffix: '02', name: '手机', online: false, shareCount: 0),
        ].cast();
      await tester.pumpWidget(wrapWithTheme(NearbyPage(source: source)));
      await tester.pumpAndSettle();

      expect(find.text('YG 的台式机'), findsOneWidget);
      expect(find.text('手机'), findsOneWidget);
      expect(find.textContaining('3 项共享'), findsOneWidget);
      expect(find.textContaining('暂无共享'), findsOneWidget);
      expect(find.text('在线'), findsOneWidget);
      expect(find.text('离线'), findsOneWidget);
      expect(find.textContaining('共 2 台设备'), findsOneWidget);
      // 有两个 PeerCard，说明真的渲染了条目而不是只渲染了页眉。
      expect(find.byType(PeerCard), findsNWidgets(2));
    });

    testWidgets('无名字时回落显示 peerId', (WidgetTester tester) async {
      final FakeNearbySource source = FakeNearbySource()
        ..peers = <dynamic>[peerView(suffix: '03', name: '')].cast();
      await tester.pumpWidget(wrapWithTheme(NearbyPage(source: source)));
      await tester.pumpAndSettle();
      // The fallback title and the copyable device ID both retain the identity.
      expect(find.text(peerOf('03').value), findsNWidgets(2));
      expect(find.byTooltip('复制设备 ID'), findsOneWidget);
    });

    testWidgets('同名设备可按 ID 搜索，搜索会展开已折叠分组', (tester) async {
      final source = FakeNearbySource()
        ..peers = [
          peerView(suffix: '01', name: '同名'),
          peerView(suffix: '02', name: '同名'),
        ];
      await tester.pumpWidget(wrapWithTheme(NearbyPage(source: source)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('peer-group-')));
      await tester.pumpAndSettle();
      expect(find.byType(PeerCard), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('nearby-search')),
        peerOf('02').value.toUpperCase(),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PeerCard), findsOneWidget);
      expect(
        find.byKey(ValueKey('nearby-peer-${peerOf('02').value}')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('点开某人能进入其分享列表', (WidgetTester tester) async {
      final FakeNearbySource source = FakeNearbySource()
        ..peers = <dynamic>[peerView(suffix: '01', name: '对方')].cast();
      source.sharesByPeer[peerOf('01')] = <SharedRootView>[
        SharedRootView(
          share: shareRecord(id: 'sh01', displayName: '共享的电影'),
          available: true,
        ),
      ];
      await tester.pumpWidget(wrapWithTheme(NearbyPage(source: source)));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PeerCard).first);
      await tester.pumpAndSettle();
      expect(find.text('共享的电影'), findsOneWidget);
      expect(find.text('可浏览'), findsOneWidget);
    });

    testWidgets('离线分享显示可读提示而不是「可浏览」', (WidgetTester tester) async {
      final FakeNearbySource source = FakeNearbySource()
        ..peers = <dynamic>[peerView(suffix: '01', name: '对方')].cast();
      source.sharesByPeer[peerOf('01')] = <SharedRootView>[
        SharedRootView(
          share: shareRecord(id: 'sh01', displayName: '旧共享'),
          available: false,
          offlineHint: '提供者已离线（最后在线 5 分钟前）',
        ),
      ];
      await tester.pumpWidget(wrapWithTheme(NearbyPage(source: source)));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PeerCard).first);
      await tester.pumpAndSettle();
      expect(find.text('提供者已离线（最后在线 5 分钟前）'), findsOneWidget);
      expect(find.text('可浏览'), findsNothing);
    });
  });

  group('服务未连接', () {
    testWidgets('services 为 null 时显示「未连接服务」而不是崩溃', (WidgetTester tester) async {
      await tester.pumpWidget(wrapWithTheme(const NearbyPage(services: null)));
      await tester.pumpAndSettle();
      expect(find.text('未连接服务'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('主题 token', () {
    testWidgets('明色下页眉用明色 token', (WidgetTester tester) async {
      final FakeNearbySource source = FakeNearbySource()
        ..peers = <dynamic>[peerView(suffix: '01')].cast();
      await tester.pumpWidget(
        wrapWithTheme(NearbyPage(source: source), brightness: Brightness.light),
      );
      await tester.pumpAndSettle();
      expect(tokensAt(tester).bg, LanFilePalette.light.bg);
      expect(tokensAt(tester).accent, LanFilePalette.light.accent);
    });

    testWidgets('切到暗色后取到的 token 变成暗色那套', (WidgetTester tester) async {
      final FakeNearbySource source = FakeNearbySource()
        ..peers = <dynamic>[peerView(suffix: '01')].cast();
      await tester.pumpWidget(
        wrapWithTheme(NearbyPage(source: source), brightness: Brightness.dark),
      );
      await tester.pumpAndSettle();
      expect(tokensAt(tester).bg, LanFilePalette.dark.bg);
      expect(tokensAt(tester).accent, LanFilePalette.dark.accent);
      expect(tokensAt(tester).fg, LanFilePalette.dark.fg);
    });

    testWidgets('在线点在明暗两套下都用 accent，且实心/空心按状态区分', (WidgetTester tester) async {
      for (final Brightness brightness in Brightness.values) {
        final FakeNearbySource source = FakeNearbySource()
          ..peers = <dynamic>[
            peerView(suffix: '01', online: true),
            peerView(suffix: '02', online: false),
          ].cast();
        await tester.pumpWidget(
          wrapWithTheme(NearbyPage(source: source), brightness: brightness),
        );
        await tester.pumpAndSettle();

        final LanFileTokens tokens = tokensAt(tester);
        final Iterable<DecoratedBox> dots = tester.widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(PeerStatusDot),
            matching: find.byType(DecoratedBox),
          ),
        );
        expect(dots.length, greaterThanOrEqualTo(2));
        final List<BoxDecoration> decorations = dots
            .map((DecoratedBox d) => d.decoration as BoxDecoration)
            .toList();

        // 在线：accent 实心、无描边。
        final BoxDecoration filled = decorations.firstWhere(
          (BoxDecoration d) => d.color != Colors.transparent,
        );
        expect(filled.color, tokens.accent);
        expect(filled.border, isNull);

        // 离线：透明填充 + accent 描边。
        final BoxDecoration hollow = decorations.firstWhere(
          (BoxDecoration d) => d.color == Colors.transparent,
        );
        expect((hollow.border! as Border).top.color, tokens.accent);
      }
    });
  });
}
