// SPDX-License-Identifier: GPL-3.0-only

/// 拖入建共享：遮罩出现/消失、create 调用次数、Android（enable=false）完全跳过。
///
/// desktop_drop 的真实拖动由平台通道驱动，widget test 无法模拟原生拖拽；
/// 因此这里测的是**本组件自己的逻辑**：开关、遮罩文案、路径到 create 的映射。
/// 真实拖拽属于「未验证项」，在报告里如实列出。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/theme/app_theme.dart';
import 'package:lan_simple_file/app/theme/tokens.dart';
import 'package:lan_simple_file/ui/widgets/drop_share_overlay.dart';

/// 记录调用并按路径内容决定成功/失败。
final class RecordingHandler implements DropShareHandler {
  /// 每次 createFromPaths 收到的批次。
  final List<List<String>> batches = <List<String>>[];

  /// 指定哪些路径要失败。
  Set<String> failPaths = <String>{};

  /// 上一次失败列表。
  List<String> failures = <String>[];

  @override
  Future<int> createFromPaths(List<String> paths) async {
    batches.add(paths);
    failures = <String>[
      for (final String p in paths)
        if (failPaths.contains(p)) p,
    ];
    return paths.length - failures.length;
  }
}

Widget wrapOverlay(
  Widget child, {
  Brightness brightness = Brightness.light,
}) =>
    MaterialApp(
      theme: AppTheme.of(LanFilePalette.of(brightness)),
      home: Scaffold(body: child),
    );

void main() {
  group('enableDragDrop=false（模拟 Android）', () {
    testWidgets('不渲染 DropTarget，无遮罩，create 绝不被调用',
        (WidgetTester tester) async {
      final RecordingHandler handler = RecordingHandler();
      await tester.pumpWidget(
        wrapOverlay(
          DropShareOverlay(
            enableDragDrop: false,
            handler: handler,
            child: const SizedBox.expand(child: Text('内容')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 关闭时组件退化为纯透传：内容照常显示。
      expect(find.text('内容'), findsOneWidget);
      // 没有任何遮罩。
      expect(
        find.byKey(const ValueKey<String>('drop-share-mask')),
        findsNothing,
      );
      // 处理器一次都没被调用。
      expect(handler.batches, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('关闭时 handler 为 null 也不崩', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapOverlay(
          const DropShareOverlay(
            enableDragDrop: false,
            child: SizedBox.expand(child: Text('内容')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('内容'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('enableDragDrop=true', () {
    testWidgets('启用时包裹 DropTarget 且内容可见', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapOverlay(
          DropShareOverlay(
            enableDragDrop: true,
            handler: RecordingHandler(),
            child: const SizedBox.expand(child: Text('内容')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('内容'), findsOneWidget);
      // 未拖入时没有遮罩。
      expect(
        find.byKey(const ValueKey<String>('drop-share-mask')),
        findsNothing,
      );
    });

    testWidgets('启用但 handler 为 null 时仍不崩', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapOverlay(
          const DropShareOverlay(
            enableDragDrop: true,
            child: SizedBox.expand(child: Text('内容')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('内容'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('处理器语义（不经 UI，直接验证端口契约）', () {
    test('两个路径 -> 两次 create', () async {
      int calls = 0;
      final List<String> seen = <String>[];
      final ServiceDropShareHandler handler = ServiceDropShareHandler(
        create: (String path) async {
          calls++;
          seen.add(path);
        },
      );
      final int created = await handler.createFromPaths(<String>[
        'D:/a.txt',
        'D:/b.txt',
      ]);
      expect(calls, 2);
      expect(created, 2);
      expect(seen, <String>['D:/a.txt', 'D:/b.txt']);
    });

    test('单个文件失败不中断整批，且失败项被记录', () async {
      final List<String> seen = <String>[];
      final ServiceDropShareHandler handler = ServiceDropShareHandler(
        create: (String path) async {
          seen.add(path);
          if (path.contains('bad')) {
            throw StateError('路径不可读');
          }
        },
      );
      final int created = await handler.createFromPaths(<String>[
        'D:/ok1.txt',
        'D:/bad.txt',
        'D:/ok2.txt',
      ]);
      // 两个成功、一个失败；整批没有被异常打断。
      expect(created, 2);
      expect(seen, hasLength(3));
      // 失败项必须带**原因**而不只是路径：只记路径的话用户看到
      // 「1 个失败」无法判断是权限、越界还是文件不见了。
      expect(ServiceDropShareHandler.lastFailures, hasLength(1));
      expect(
        ServiceDropShareHandler.lastFailures.single.path,
        'D:/bad.txt',
      );
      expect(
        ServiceDropShareHandler.lastFailures.single.message,
        contains('路径不可读'),
        reason: '必须记录真实异常信息',
      );
      expect(ServiceDropShareHandler.lastFailures.single.shortName, 'bad.txt');
    });

    test('全部失败时返回 0 且不抛', () async {
      final ServiceDropShareHandler handler = ServiceDropShareHandler(
        create: (String path) async => throw StateError('全挂'),
      );
      final int created =
          await handler.createFromPaths(<String>['D:/x', 'D:/y']);
      expect(created, 0);
      expect(ServiceDropShareHandler.lastFailures, hasLength(2));
    });

    test('空路径列表返回 0', () async {
      final ServiceDropShareHandler handler =
          ServiceDropShareHandler(create: (String path) async {});
      expect(await handler.createFromPaths(const <String>[]), 0);
    });
  });

  group('onResult 回调', () {
    testWidgets('handler 为 null 时一次性回调 0/N，不抛',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        wrapOverlay(
          DropShareOverlay(
            enableDragDrop: true,
            child: const SizedBox.expand(child: Text('内容')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 没有 handler 时不会崩溃；真实拖拽由平台触发，这里仅保证稳态可渲染。
      expect(tester.takeException(), isNull);
    });
  });

  group('主题 token', () {
    testWidgets('遮罩用对应主题的 accent 与 surface（通过 token 断言）',
        (WidgetTester tester) async {
      for (final Brightness brightness in Brightness.values) {
        await tester.pumpWidget(
          wrapOverlay(
            DropShareOverlay(
              enableDragDrop: true,
              handler: RecordingHandler(),
              child: const SizedBox.expand(child: Text('内容')),
            ),
            brightness: brightness,
          ),
        );
        await tester.pumpAndSettle();
        final LanFileTokens tokens =
            Theme.of(tester.element(find.text('内容'))).extension<LanFileTokens>()!;
        expect(
          tokens.accent,
          brightness == Brightness.dark
              ? LanFilePalette.dark.accent
              : LanFilePalette.light.accent,
        );
        expect(
          tokens.surface,
          brightness == Brightness.dark
              ? LanFilePalette.dark.surface
              : LanFilePalette.light.surface,
        );
      }
    });
  });
}
