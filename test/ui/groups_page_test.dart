// SPDX-License-Identifier: GPL-3.0-only

/// 群组页面：只收 kind=group、未读数、已解散标记、空态、null services。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/theme/tokens.dart';
import 'package:lan_simple_file/ui/pages/groups_page.dart';

import 'support/ui_fakes.dart';

void main() {
  group('空状态', () {
    testWidgets('没有群时显示空态文案', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithTheme(GroupsPage(source: FakeGroupsSource())),
      );
      await tester.pumpAndSettle();
      expect(find.text('还没有群组'), findsOneWidget);
      expect(find.textContaining('群文件历史'), findsOneWidget);
      expect(find.byType(GroupRowView), findsNothing);
    });
  });

  group('有数据', () {
    testWidgets('渲染群名与未读数', (WidgetTester tester) async {
      final FakeGroupsSource source = FakeGroupsSource()
        ..threads = <dynamic>[
          groupThread(groupId: 'g1', title: '家庭群', unread: 5),
          groupThread(groupId: 'g2', title: '工作群', unread: 0),
        ].cast()
        ..groups = <String, dynamic>{
          'g1': groupRecord(groupId: 'g1', name: '家庭群'),
          'g2': groupRecord(groupId: 'g2', name: '工作群'),
        }.cast();
      await tester.pumpWidget(wrapWithTheme(GroupsPage(source: source)));
      await tester.pumpAndSettle();

      expect(find.text('家庭群'), findsOneWidget);
      expect(find.text('工作群'), findsOneWidget);
      expect(find.textContaining('共 2 个'), findsOneWidget);
      expect(find.byType(GroupRowView), findsNWidgets(2));

      // 未读 5 显示徽标；未读 0 完全不占位。
      expect(find.text('5'), findsOneWidget);
      expect(find.byType(UnreadBadge), findsNWidgets(2));
    });

    testWidgets('未读超过 99 显示 99+', (WidgetTester tester) async {
      final FakeGroupsSource source = FakeGroupsSource()
        ..threads = <dynamic>[
          groupThread(groupId: 'g1', title: '大群', unread: 1234),
        ].cast()
        ..groups = <String, dynamic>{
          'g1': groupRecord(groupId: 'g1'),
        }.cast();
      await tester.pumpWidget(wrapWithTheme(GroupsPage(source: source)));
      await tester.pumpAndSettle();
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('单聊线程不会被当成群组', (WidgetTester tester) async {
      final FakeGroupsSource source = FakeGroupsSource()
        ..threads = <dynamic>[
          groupThread(groupId: 'g1', title: '真群'),
          directThread(id: 'd_abc', title: '这是单聊'),
        ].cast()
        ..groups = <String, dynamic>{
          'g1': groupRecord(groupId: 'g1'),
        }.cast();
      await tester.pumpWidget(wrapWithTheme(GroupsPage(source: source)));
      await tester.pumpAndSettle();

      expect(find.text('真群'), findsOneWidget);
      expect(find.text('这是单聊'), findsNothing);
      expect(find.byType(GroupRowView), findsOneWidget);
    });

    testWidgets('已解散的群仍列出但标注「已解散」', (WidgetTester tester) async {
      final FakeGroupsSource source = FakeGroupsSource()
        ..threads = <dynamic>[
          groupThread(groupId: 'g1', title: '解散了的群'),
        ].cast()
        ..groups = <String, dynamic>{
          'g1': groupRecord(groupId: 'g1', name: '解散了的群', archived: true),
        }.cast();
      await tester.pumpWidget(wrapWithTheme(GroupsPage(source: source)));
      await tester.pumpAndSettle();

      expect(find.text('解散了的群'), findsOneWidget);
      expect(find.text('已解散'), findsOneWidget);
      // 不物理删：仍然在列表里。
      expect(find.byType(GroupRowView), findsOneWidget);
    });

    testWidgets('没有预览时显示「还没有消息」', (WidgetTester tester) async {
      final FakeGroupsSource source = FakeGroupsSource()
        ..threads = <dynamic>[
          groupThread(groupId: 'g1', title: '新群'),
        ].cast()
        ..groups = <String, dynamic>{
          'g1': groupRecord(groupId: 'g1'),
        }.cast();
      await tester.pumpWidget(wrapWithTheme(GroupsPage(source: source)));
      await tester.pumpAndSettle();
      expect(find.text('还没有消息'), findsOneWidget);
    });

    testWidgets('按未读数降序排列', (WidgetTester tester) async {
      final FakeGroupsSource source = FakeGroupsSource()
        ..threads = <dynamic>[
          groupThread(groupId: 'g1', title: '少未读', unread: 1),
          groupThread(groupId: 'g2', title: '多未读', unread: 9),
        ].cast()
        ..groups = <String, dynamic>{
          'g1': groupRecord(groupId: 'g1'),
          'g2': groupRecord(groupId: 'g2'),
        }.cast();
      await tester.pumpWidget(wrapWithTheme(GroupsPage(source: source)));
      await tester.pumpAndSettle();

      final List<GroupRowView> rows =
          tester.widgetList<GroupRowView>(find.byType(GroupRowView)).toList();
      expect(rows.first.row.thread.title, '多未读');
    });
  });

  group('服务未连接', () {
    testWidgets('services 为 null 时显示「未连接服务」', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapWithTheme(const GroupsPage(services: null)),
      );
      await tester.pumpAndSettle();
      expect(find.text('未连接服务'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('主题 token', () {
    testWidgets('明暗两套下未读徽标底色用 accent', (WidgetTester tester) async {
      for (final Brightness brightness in Brightness.values) {
        final FakeGroupsSource source = FakeGroupsSource()
          ..threads = <dynamic>[
            groupThread(groupId: 'g1', title: '群', unread: 3),
          ].cast()
          ..groups = <String, dynamic>{
            'g1': groupRecord(groupId: 'g1'),
          }.cast();
        await tester.pumpWidget(
          wrapWithTheme(GroupsPage(source: source), brightness: brightness),
        );
        await tester.pumpAndSettle();

        final LanFileTokens tokens = tokensAt(tester);
        expect(
          tokens.accent,
          brightness == Brightness.dark
              ? LanFilePalette.dark.accent
              : LanFilePalette.light.accent,
        );
        final Container badge = tester.widget<Container>(
          find.descendant(
            of: find.byType(UnreadBadge),
            matching: find.byType(Container),
          ),
        );
        expect((badge.decoration! as BoxDecoration).color, tokens.accent);
      }
    });
  });
}
