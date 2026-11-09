// SPDX-License-Identifier: GPL-3.0-only
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/messaging/chat_search.dart';
import 'package:lan_simple_file/core/messaging/messaging_service_impl.dart';
import 'package:lan_simple_file/ui/shell/qq_shell.dart';
import 'package:lan_simple_file/ui/widgets/chat_pane.dart';
import 'package:lan_simple_file/ui/widgets/chat_search_dialog.dart';

import '../core/messaging/chat_search_test.dart'
    show searchThread, searchMessage, searchPeer;
import 'chat_workspace_test.dart' show ChatTestService;
import 'qq_shell_test.dart' show wrapShell, setViewport, FakeSessionSource;
import 'support/miuix_test_support.dart';

class TestChatSearch implements ChatSearchSource {
  final calls = <({String query, ChatSearchKind kind, String? thread})>[];
  Future<List<ChatSearchHit>> Function(String)? respond;
  @override
  Future<List<ChatSearchHit>> search(
    String query, {
    ChatSearchKind kind = ChatSearchKind.all,
    String? threadId,
  }) {
    calls.add((query: query, kind: kind, thread: threadId));
    return respond?.call(query) ?? Future.value([]);
  }
}

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'global result opens an old message and thread search at $width',
      (tester) async {
        await setViewport(tester, Size(width, 844));
        final thread = directThreadId(
          PeerId.parse('p_localdevice00'),
          searchPeer,
        );
        final messaging = ChatTestService();
        addTearDown(messaging.updates.close);
        messaging.messages[thread] = List.generate(
          100,
          (i) => searchMessage(
            'm$i',
            thread: thread,
            body: i == 10 ? 'Target report' : 'Message $i',
            time: i,
          ),
        );
        final hit = ChatSearchHit(
          searchThread(thread),
          messaging.messages[thread]![10],
        );
        final search = TestChatSearch()..respond = (_) async => [hit];
        await tester.pumpWidget(
          wrapShell(
            QqShell(
              sessionSource: FakeSessionSource(),
              messaging: messaging,
              chatSearchSource: search,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('chat-history-search-button')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('chat-history-search')),
          'report',
        );
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('search-message-m10')));
        await tester.pumpAndSettle();
        expect(
          tester.widget<ChatPane>(find.byType(ChatPane)).focusMessageId,
          'm10',
        );
        expect(find.text('Target report').hitTestable(), findsOneWidget);
        expect(find.text('Message 99').hitTestable(), findsNothing);
        await tester.tap(findAppTooltip('搜索当前聊天'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('文件').last);
        await tester.pumpAndSettle();
        expect(search.calls.last.thread, thread);
        expect(search.calls.last.kind, ChatSearchKind.files);
        await tester.tap(find.widgetWithText(AppButton, '关闭'));
        await tester.pumpAndSettle();
        await tester.tap(findAppTooltip('返回最新消息'));
        await tester.pumpAndSettle();
        expect(find.text('Message 99').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('out-of-order results do not replace the latest search', (
    tester,
  ) async {
    final first = Completer<List<ChatSearchHit>>();
    final search = TestChatSearch()
      ..respond = (query) => query == 'old'
          ? first.future
          : Future.value([
              ChatSearchHit(
                searchThread('one'),
                searchMessage('new', body: 'Newest'),
              ),
            ]);
    await tester.pumpWidget(
      wrapShell(AppScaffold(body: ChatSearchDialog(source: search))),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('chat-history-search')),
      'old',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(
      find.byKey(const ValueKey('chat-history-search')),
      'new',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    first.complete([
      ChatSearchHit(searchThread('one'), searchMessage('old', body: 'Stale')),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Newest'), findsOneWidget);
    expect(find.text('Stale'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
