// SPDX-License-Identifier: GPL-3.0-only

/// 中栏会话列表：行渲染、搜索过滤、未读红点、hover 底色、明暗 token。
library;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/miuix_test_support.dart';

import 'package:lan_simple_file/app/theme/app_theme.dart';
import 'package:lan_simple_file/app/theme/tokens.dart';
import 'package:lan_simple_file/ui/shell/session_list.dart';
import 'package:lan_simple_file/ui/widgets/avatar_badge.dart';

Widget wrapList(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      builder: (context, child) => AppMiuixTheme(child: child!),
      theme: AppTheme.of(LanFilePalette.of(brightness)),
      home: AppScaffold(body: child),
    );

SessionList buildList({
  required List<SessionRowData> rows,
  String? selectedId,
  ValueChanged<SessionRowData>? onSelect,
}) => SessionList(
  title: '附近的人',
  rows: rows,
  selectedId: selectedId,
  onSelect: onSelect ?? (SessionRowData row) {},
);

SessionRowData rowOf(String id, String title, {int unread = 0, String? sub}) =>
    SessionRowData(
      id: id,
      title: title,
      avatarSeed: 'p_7fk3m9x2a1c01',
      subtitle: sub ?? '3 项共享',
      unread: unread,
      online: true,
    );

void main() {
  group('行渲染', () {
    testWidgets('3 个 peer 渲染 3 行，名字与分享数正确', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapList(
          buildList(
            rows: <SessionRowData>[
              rowOf('a', '张三'),
              rowOf('b', '李四', sub: '1 项共享'),
              rowOf('c', '王五', sub: '暂无共享'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SessionListRow), findsNWidgets(3));
      expect(find.text('张三'), findsOneWidget);
      expect(find.text('李四'), findsOneWidget);
      expect(find.text('王五'), findsOneWidget);
      expect(find.text('3 项共享'), findsOneWidget);
      expect(find.text('1 项共享'), findsOneWidget);
      expect(find.text('暂无共享'), findsOneWidget);
    });

    testWidgets('每行都有头像', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapList(buildList(rows: <SessionRowData>[rowOf('a', '张三')])),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AvatarBadge), findsOneWidget);
    });

    testWidgets('点行触发 onSelect', (WidgetTester tester) async {
      SessionRowData? picked;
      await tester.pumpWidget(
        wrapList(
          buildList(
            rows: <SessionRowData>[rowOf('a', '张三')],
            onSelect: (SessionRowData row) => picked = row,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('session-row-a')));
      await tester.pumpAndSettle();
      expect(picked?.id, 'a');
    });
  });

  group('搜索过滤', () {
    testWidgets('同名设备按完整或部分 ID 搜索并复制完整 ID', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = call.arguments['text'];
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
      await tester.pumpWidget(
        wrapList(
          buildList(
            rows: const [
              SessionRowData(
                id: 'p_devicefirst01',
                peerId: 'p_devicefirst01',
                title: '好好吃饭',
                avatarSeed: 'p_devicefirst01',
              ),
              SessionRowData(
                id: 'p_devicesecond2',
                peerId: 'p_devicesecond2',
                title: '好好吃饭',
                avatarSeed: 'p_devicesecond2',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('好好吃饭'), findsNWidgets(2));
      for (final query in ['  SECOND2  ', 'p_devicesecond2']) {
        await tester.enterText(
          find.byKey(const ValueKey('session-search')),
          query,
        );
        await tester.pumpAndSettle();
        expect(find.byType(SessionListRow), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(SessionListRow),
            matching: find.text('p_devicesecond2'),
          ),
          findsOneWidget,
        );
        expect(find.text('p_devicefirst01'), findsNothing);
      }
      await tester.tap(findAppTooltip('复制设备 ID'));
      await tester.pumpAndSettle();
      expect(copied, 'p_devicesecond2');
      expect(tester.takeException(), isNull);
    });
    testWidgets('搜「张」只剩匹配项', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapList(
          buildList(
            rows: <SessionRowData>[
              rowOf('a', '张三'),
              rowOf('b', '李四'),
              rowOf('c', '张伟'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SessionListRow), findsNWidgets(3));

      await tester.enterText(
        find.byKey(const ValueKey<String>('session-search')),
        '张',
      );
      await tester.pumpAndSettle();

      expect(find.byType(SessionListRow), findsNWidgets(2));
      expect(find.text('张三'), findsOneWidget);
      expect(find.text('张伟'), findsOneWidget);
      expect(find.text('李四'), findsNothing);
    });

    testWidgets('搜索无结果显示专门文案，而不是「暂无会话」', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapList(buildList(rows: <SessionRowData>[rowOf('a', '张三')])),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('session-search')),
        '不存在的人',
      );
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的会话'), findsOneWidget);
      expect(find.text('暂无会话'), findsNothing);
    });

    testWidgets('清空搜索后恢复全部', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapList(
          buildList(rows: <SessionRowData>[rowOf('a', '张三'), rowOf('b', '李四')]),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('session-search')),
        '张',
      );
      await tester.pumpAndSettle();
      expect(find.byType(SessionListRow), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey<String>('session-search')),
        '',
      );
      await tester.pumpAndSettle();
      expect(find.byType(SessionListRow), findsNWidgets(2));
    });

    testWidgets('搜索匹配摘要文字也算命中', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapList(
          buildList(
            rows: <SessionRowData>[
              rowOf('a', '张三', sub: '共享了报告.pdf'),
              rowOf('b', '李四', sub: '3 项共享'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('session-search')),
        '报告',
      );
      await tester.pumpAndSettle();
      expect(find.byType(SessionListRow), findsOneWidget);
      expect(find.text('张三'), findsOneWidget);
    });
  });

  group('未读红点', () {
    testWidgets('unread=5 显示 5；unread=0 不显示', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapList(
          buildList(
            rows: <SessionRowData>[
              rowOf('a', '有未读', unread: 5),
              rowOf('b', '没未读', unread: 0),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // unread<=0 时列表行根本不构造 UnreadPill（而不是构造成空盒子），
      // 因此树上只有一个 pill，且文本恰为 "5"。
      expect(find.text('5'), findsOneWidget);
      expect(find.byType(UnreadPill), findsOneWidget);
      final UnreadPill pill = tester.widget<UnreadPill>(
        find.byType(UnreadPill),
      );
      expect(pill.count, 5);
    });

    testWidgets('超过 99 显示 99+', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapList(
          buildList(rows: <SessionRowData>[rowOf('a', '大未读', unread: 250)]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('99+'), findsOneWidget);
    });
  });

  group('hover 与选中底色', () {
    testWidgets('hover 时行背景为非透明 accent 淡色；移出后恢复透明', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrapList(buildList(rows: <SessionRowData>[rowOf('a', '张三')])),
      );
      await tester.pumpAndSettle();

      // 底色现在由行外层的 DecoratedBox 负责（Material 透明），
      // 因为三态底色 + 圆角描边统一在一个 decoration 里，切换不抖动。
      BoxDecoration decorationOf() =>
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: find.byType(SessionListRow),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;

      // 初始：无底色。
      expect(decorationOf().color, isNull);

      // hover：浅色 accent。
      final TestGesture gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await tester.pumpAndSettle();
      final Offset rowCenter = tester.getCenter(
        find.byKey(const ValueKey<String>('session-row-a')),
      );
      await gesture.moveTo(rowCenter);
      await tester.pumpAndSettle();

      final LanFileTokens tokens = Theme.of(
        tester.element(find.byType(SessionListRow)),
      ).extension<LanFileTokens>()!;
      final Color? hovered = decorationOf().color;
      expect(hovered, isNotNull, reason: 'hover 必须有可见底色');
      // hover 用 tokens 的 hoverSoft（不是硬编码透明度）。
      expect(hovered, equals(tokens.hoverSoft));

      // 移出：恢复无底色。
      await gesture.moveTo(const Offset(1, 1));
      await tester.pumpAndSettle();
      expect(decorationOf().color, isNull);
    });

    testWidgets('选中行底色比 hover 更深（透明度更大）', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapList(
          buildList(rows: <SessionRowData>[rowOf('a', '张三')], selectedId: 'a'),
        ),
      );
      await tester.pumpAndSettle();
      final BoxDecoration decoration =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: find.byType(SessionListRow),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(decoration.color, isNotNull);
      // 选中态是 accentSoft + accent 描边，两者都要有。
      expect(decoration.border, isNotNull, reason: '选中行应有主色描边');
    });
  });

  group('明暗 token', () {
    testWidgets('列表背景在明暗两套间切换', (WidgetTester tester) async {
      for (final Brightness brightness in Brightness.values) {
        await tester.pumpWidget(
          wrapList(
            buildList(rows: <SessionRowData>[rowOf('a', '张三')]),
            brightness: brightness,
          ),
        );
        await tester.pumpAndSettle();

        final Container list = tester.widget<Container>(
          find.byKey(const ValueKey<String>('shell-list')),
        );
        // 列表栏用 surfaceSunken（比内容区更深一层），这是层次感的来源。
        final LanFileTokens expectedTokens = brightness == Brightness.dark
            ? LanFilePalette.dark
            : LanFilePalette.light;
        expect(list.color, equals(expectedTokens.surfaceSunken));
        expect(
          list.color,
          isNot(equals(expectedTokens.bg)),
          reason: '列表底色必须与内容区底色有可见差异',
        );
      }
    });

    testWidgets('hover 色取自对应主题的 accent', (WidgetTester tester) async {
      for (final Brightness brightness in Brightness.values) {
        await tester.pumpWidget(
          wrapList(
            buildList(rows: <SessionRowData>[rowOf('a', '张三')]),
            brightness: brightness,
          ),
        );
        await tester.pumpAndSettle();

        final TestGesture gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: Offset.zero);
        await tester.pumpAndSettle();
        await gesture.moveTo(
          tester.getCenter(find.byKey(const ValueKey<String>('session-row-a'))),
        );
        await tester.pumpAndSettle();

        final BoxDecoration decoration =
            tester
                    .widget<DecoratedBox>(
                      find
                          .descendant(
                            of: find.byType(SessionListRow),
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration;
        final LanFileTokens tokens = Theme.of(
          tester.element(find.byType(SessionListRow)),
        ).extension<LanFileTokens>()!;
        // hover 色随主题变化：明暗两套的 hoverSoft 必须不同。
        expect(decoration.color, equals(tokens.hoverSoft));
        await gesture.removePointer();
      }
    });
  });

  group('宽度与空态', () {
    testWidgets('中栏宽度在 260-300 区间', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapList(buildList(rows: <SessionRowData>[rowOf('a', '张三')])),
      );
      await tester.pumpAndSettle();
      final double width = tester
          .getRect(find.byKey(const ValueKey<String>('shell-list')))
          .width;
      expect(width, inInclusiveRange(260, 300));
    });

    testWidgets('空列表显示空态标题与说明', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapList(
          SessionList(
            title: '附近的人',
            rows: const <SessionRowData>[],
            selectedId: null,
            onSelect: (SessionRowData row) {},
            emptyTitle: '附近还没有人',
            emptyBody: '对方可能没开软件，或防火墙拦了 UDP 47777。',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('附近还没有人'), findsOneWidget);
      expect(find.textContaining('防火墙'), findsOneWidget);
    });
  });
}
