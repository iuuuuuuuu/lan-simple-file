// SPDX-License-Identifier: GPL-3.0-only
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/miuix_test_support.dart';

import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/messaging/messaging_service_impl.dart';
import 'package:lan_simple_file/ui/shell/custom_title_bar.dart';
import 'package:lan_simple_file/ui/shell/qq_shell.dart';
import 'package:lan_simple_file/ui/shell/session_list.dart';
import 'package:lan_simple_file/ui/shell/session_rail.dart';
import 'package:lan_simple_file/ui/widgets/chat_pane.dart';
import 'package:lan_simple_file/ui/widgets/share_row.dart';
import 'package:lan_simple_file/ui/pages/shares_page.dart';

import 'qq_shell_test.dart' show FakeSessionSource, wrapShell, setViewport;
import 'requested_features_test.dart' show MemoryPeerGroups;
import 'support/ui_fakes.dart';

class ChatTestService implements MessagingService {
  final sent = <({String thread, String text})>[];
  final messages = <String, List<MessageRecord>>{};
  final updates = StreamController<List<MessageRecord>>.broadcast();
  String? _watching;
  bool failSend = false;
  int _sequence = 0;

  @override
  Stream<List<MessageRecord>> watchMessages(String threadId) async* {
    _watching = threadId;
    yield messages[threadId] ?? [];
    yield* updates.stream;
  }

  @override
  Future<void> sendText(String threadId, String text) async {
    if (failSend) throw StateError('网络错误');
    sent.add((thread: threadId, text: text));
    messages
        .putIfAbsent(threadId, () => [])
        .add(
          MessageRecord(
            id: 'p_localdevice00:${++_sequence}',
            threadId: threadId,
            senderPeerId: PeerId.parse('p_localdevice00'),
            kind: MessageKind.text,
            hlc: Hlc(millis: 1, counter: _sequence, origin: 'p_localdevice00'),
            ts: DateTime.now(),
            body: text,
            attachJson: '',
            sig: '',
          ),
        );
    if (_watching == threadId) updates.add(messages[threadId]!);
  }

  @override
  Stream<List<ThreadRecord>> watchThreads() => const Stream.empty();
  @override
  Future<void> sendFile(
    String threadId,
    ShareId share, {
    ItemKey? itemKey,
  }) async {}
  @override
  Future<void> revoke(String messageId, {String? reason}) async {}
  @override
  Future<void> deleteLocal(String messageId) async {}
  @override
  Future<void> deleteThread(String threadId) async {}
  @override
  Future<String> createGroup(String name, List<PeerId> members) async => 'test';
  @override
  Future<void> leaveGroup(String groupId) async {}
}

void main() {
  final peer = PeerId.parse('p_aaaaaaaaaaaaa');
  FakeSessionSource source() => FakeSessionSource()
    ..rows = {
      ShellSection.nearby: [
        SessionRowData(
          id: peer.value,
          title: '小明',
          avatarSeed: peer.value,
          online: true,
        ),
      ],
      ShellSection.groups: [
        const SessionRowData(
          id: 'g_family',
          title: '家人群',
          avatarSeed: 'family',
          isGroup: true,
        ),
      ],
    };

  testWidgets('联系人和群在左侧分组，右侧为聊天，切换不会串消息', (tester) async {
    await setViewport(tester, const Size(1280, 800));
    final messaging = ChatTestService();
    addTearDown(messaging.updates.close);
    await tester.pumpWidget(
      wrapShell(QqShell(sessionSource: source(), messaging: messaging)),
    );
    await tester.pumpAndSettle();
    expect(find.text('陌生人 (1)'), findsOneWidget);
    expect(find.text('群聊 (1)'), findsOneWidget);
    expect(find.byKey(const ValueKey('rail-groups')), findsNothing);
    expect(find.text('选择联系人或群聊'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('session-row-${peer.value}')));
    await tester.pumpAndSettle();
    expect(find.byType(ChatPane), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('shell-list'))).right,
      lessThan(tester.getRect(find.byType(ChatPane)).left),
    );
    await tester.enterText(find.byKey(const ValueKey('chat-input')), '给小明的消息');
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pumpAndSettle();
    expect(
      messaging.sent.single.thread,
      directThreadId(PeerId.parse('p_localdevice00'), peer),
    );
    expect(find.text('给小明的消息'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('session-row-g_family')));
    await tester.pumpAndSettle();
    expect(find.text('给小明的消息'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('chat-input')), '群里的消息');
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pumpAndSettle();
    expect(messaging.sent.last.thread, 'g_family');
    expect(find.text('群里的消息'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('session-row-${peer.value}')));
    await tester.pumpAndSettle();
    expect(find.text('给小明的消息'), findsOneWidget);
    expect(find.text('群里的消息'), findsNothing);
  });

  testWidgets('联系人与群聊都能移入同一分组，关闭页面后仍保留', (tester) async {
    await setViewport(tester, const Size(1280, 800));
    final groups = MemoryPeerGroups();
    final widget = QqShell(sessionSource: source(), groupsSource: groups);
    await tester.pumpWidget(wrapShell(widget));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('session-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建分组'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('session-group-name-field')),
      '朋友',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final id = groups.value.names.keys.single;
    for (final rowId in [peer.value, 'g_family']) {
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.down(
        tester.getCenter(find.byKey(ValueKey('session-row-$rowId'))),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('移到 朋友'));
      await tester.pumpAndSettle();
    }
    expect(groups.value.assignments[peer.value], id);
    expect(groups.value.assignments['g_family'], id);
    expect(find.text('朋友 (2)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(wrapShell(widget));
    await tester.pumpAndSettle();
    expect(find.text('朋友 (2)'), findsOneWidget);
    expect(find.byKey(const ValueKey('shell-open-drawer')), findsNothing);
  });

  testWidgets('分享备注作标题、路径作副标题，卡片右键菜单可执行', (tester) async {
    final record = shareRecord(id: 'share_test', displayName: '工作资料');
    final source = FakeMySharesSource()
      ..shares = [record]
      ..webLink = Uri.parse('http://10.0.0.1/s/share_test');
    await tester.pumpWidget(wrapWithTheme(SharesPage(source: source)));
    await tester.pumpAndSettle();
    final title = tester.widget<Text>(find.text('工作资料'));
    final path = tester.widget<Text>(find.text(shareLocationLabel(record)));
    expect(title.style!.fontWeight, FontWeight.w500);
    expect(path.style!.fontSize, lessThan(title.style!.fontSize!));
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.down(tester.getCenter(find.byType(ShareRow)));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('设置分享名称'), findsOneWidget);
    expect(find.text('复制网页链接'), findsOneWidget);
    await tester.tap(find.text('设置分享名称'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('share-name-field')), findsOneWidget);
  });

  testWidgets('标题栏关闭键悬浮使用淡底色，选中主题按钮主色一致', (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        wrapShell(
          Row(
            children: [
              CaptionButton(
                tooltip: '关闭',
                icon: LucideIcons.x,
                danger: true,
                onTap: () async {},
              ),
              CaptionButton(
                tooltip: '主题',
                icon: LucideIcons.moon,
                selected: true,
                onTap: () async {},
              ),
            ],
          ),
          brightness: brightness,
        ),
      );
      await tester.pumpAndSettle();
      final colors = MiuixThemeData.of(brightness).colors;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(
        location: tester.getCenter(find.byKey(const ValueKey('caption-关闭'))),
      );
      await tester.pumpAndSettle();
      final close = find.byKey(const ValueKey('caption-关闭'));
      final hover = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.descendant(
            of: close,
            matching: find.byType(MiuixIconButton),
          ),
          matching: find.byType(DecoratedBox),
        ),
      );
      final hoverColor = (hover.decoration as BoxDecoration).color!;
      expect(hoverColor.a, closeTo(.06, .001));
      expect(
        hoverColor.withValues(alpha: 1),
        colors.onBackground.withValues(alpha: 1),
      );
      final theme = tester.widget<MiuixIconButton>(
        find.descendant(
          of: find.byKey(const ValueKey('caption-主题')),
          matching: find.byType(MiuixIconButton),
        ),
      );
      expect(theme.backgroundColor, colors.secondaryContainer);
      expect(
        IconTheme.of(tester.element(find.byIcon(LucideIcons.moon))).color,
        colors.primary,
      );
      await mouse.removePointer();
    }
  });

  testWidgets('发送失败保留草稿，空白消息不发送', (tester) async {
    final messaging = ChatTestService()..failSend = true;
    addTearDown(messaging.updates.close);
    await tester.pumpWidget(
      wrapShell(
        AppScaffold(
          body: ChatPane(
            threadId: 'g_test',
            title: '群',
            self: PeerId.parse('p_localdevice00'),
            avatarSeed: 'test',
            messaging: messaging,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('chat-input')), '草稿');
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pumpAndSettle();
    expect(find.textContaining('发送失败'), findsOneWidget);
    expect(
      tester
          .widget<AppTextField>(find.byKey(const ValueKey('chat-input')))
          .controller!
          .text,
      '草稿',
    );
    await tester.enterText(find.byKey(const ValueKey('chat-input')), '  ');
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pumpAndSettle();
    expect(messaging.sent, isEmpty);
  });

  testWidgets('Enter 发送，Shift+Enter 保留编辑而不发送', (tester) async {
    final messaging = ChatTestService();
    addTearDown(messaging.updates.close);
    await tester.pumpWidget(
      wrapShell(
        AppScaffold(
          body: ChatPane(
            threadId: 'g_test',
            title: '群',
            self: PeerId.parse('p_localdevice00'),
            avatarSeed: 'test',
            messaging: messaging,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('chat-input'));
    await tester.enterText(input, '第一行');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(messaging.sent, isEmpty);
    expect(
      tester.widget<AppTextField>(input).controller!.text,
      contains('第一行'),
    );
    await tester.enterText(input, '第一行\n第二行');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(messaging.sent.single.text, '第一行\n第二行');
    expect(tester.widget<AppTextField>(input).controller!.text, isEmpty);
  });

  testWidgets('手机从分组列表进入聊天并返回，不需要会话抽屉', (tester) async {
    await setViewport(tester, const Size(390, 844));
    final messaging = ChatTestService();
    addTearDown(messaging.updates.close);
    await tester.pumpWidget(
      wrapShell(QqShell(sessionSource: source(), messaging: messaging)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shell-list')), findsOneWidget);
    expect(find.byType(ChatPane), findsNothing);
    await tester.tap(find.byKey(ValueKey('session-row-${peer.value}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shell-list')), findsNothing);
    expect(find.byType(ChatPane), findsOneWidget);
    await tester.tap(findAppTooltip('返回联系人'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shell-list')), findsOneWidget);
    expect(find.byType(ChatPane), findsNothing);
    expect(find.byKey(const ValueKey('shell-open-drawer')), findsNothing);
  });
}
