// SPDX-License-Identifier: GPL-3.0-only

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/branding/app_logo.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/ui/pages/settings_page.dart';
import 'package:lan_simple_file/ui/pages/shares_page.dart';
import 'package:lan_simple_file/ui/widgets/chat_pane.dart';
import 'package:lan_simple_file/ui/widgets/share_picker_dialog.dart';
import 'package:lan_simple_file/ui/widgets/share_row.dart';

import 'chat_workspace_test.dart' show ChatTestService;
import 'qq_shell_test.dart' show wrapShell, setViewport;
import 'support/ui_fakes.dart';

class RequestMessaging extends ChatTestService {
  final files = <({String thread, ShareId share})>[];
  final revoked = <String>[];
  @override
  Future<void> sendFile(
    String threadId,
    ShareId share, {
    ItemKey? itemKey,
  }) async {
    files.add((thread: threadId, share: share));
  }

  @override
  Future<void> revoke(String messageId, {String? reason}) async {
    revoked.add(messageId);
    for (final entry in messages.entries) {
      entry.value.replaceRange(
        0,
        entry.value.length,
        entry.value
            .map(
              (m) => m.id != messageId
                  ? m
                  : MessageRecord(
                      id: m.id,
                      threadId: m.threadId,
                      senderPeerId: m.senderPeerId,
                      kind: m.kind,
                      hlc: m.hlc,
                      ts: m.ts,
                      body: m.body,
                      attachJson: m.attachJson,
                      sig: m.sig,
                      revokedAt: DateTime.now(),
                    ),
            )
            .toList(),
      );
      updates.add(entry.value);
    }
  }
}

void main() {
  testWidgets('默认 C，设置切换 Logo 并保存，重新加载后恢复选择', (tester) async {
    String? saved;
    final applied = <AppLogo>[];
    LogoController create() => LogoController(
      read: () async => saved,
      write: (value) async => saved = value,
      apply: (value) async => applied.add(value),
    );
    final controller = create();
    addTearDown(controller.dispose);
    await controller.hydrate();
    expect(controller.value, AppLogo.chatFolder);
    await tester.pumpWidget(
      wrapShell(
        Scaffold(
          body: LogoScope(
            controller: controller,
            child: const SettingsPage(currentUserName: '测试用户'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final option = find.byKey(const ValueKey('logo-option-folderLink'));
    await tester.ensureVisible(option);
    await tester.tap(option);
    await tester.pumpAndSettle();
    expect(controller.value, AppLogo.folderLink);
    expect(saved, AppLogo.folderLink.name);
    expect(applied.last, AppLogo.folderLink);
    final restored = create();
    addTearDown(restored.dispose);
    await restored.hydrate();
    expect(restored.value, AppLogo.folderLink);
  });

  testWidgets('我的分享为响应式栅格，可按备注和完整位置搜索', (tester) async {
    await setViewport(tester, const Size(1100, 800));
    final source = FakeMySharesSource()
      ..shares = [
        shareRecord(
          id: 'docs001',
          displayName: '项目资料',
          rootUri: r'D:\work\notes',
        ),
        shareRecord(
          id: 'photos01',
          displayName: '旅行照片',
          rootUri: r'D:\Photos\2026',
        ),
        shareRecord(id: 'music01', displayName: '音乐'),
      ]
      ..webLink = Uri.parse('http://10.0.0.1/s/test');
    await tester.pumpWidget(wrapWithTheme(SharesPage(source: source)));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);
    final first = tester.getRect(find.text('项目资料'));
    final second = tester.getRect(find.text('旅行照片'));
    expect(first.top, second.top);
    expect(first.left, lessThan(second.left));
    final search = find.byKey(const ValueKey('my-shares-search'));
    await tester.enterText(search, '资料');
    await tester.pumpAndSettle();
    expect(find.byType(ShareRow), findsOneWidget);
    expect(find.text('项目资料'), findsOneWidget);
    await tester.enterText(search, 'photos');
    await tester.pumpAndSettle();
    expect(find.text('旅行照片'), findsOneWidget);
    await tester.enterText(search, '不存在');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的分享'), findsOneWidget);
  });

  testWidgets('发送分享对话框可搜索，并返回匹配分享的真实 ID', (tester) async {
    ShareId? picked;
    await tester.pumpWidget(
      wrapShell(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => picked = await showDialog<ShareId>(
                context: context,
                builder: (_) => SharePickerDialog(
                  shares: [
                    shareRecord(id: 'docs001', displayName: '项目资料'),
                    shareRecord(
                      id: 'photos01',
                      displayName: '旅行照片',
                      rootUri: r'D:\Photos\2026',
                    ),
                  ],
                ),
              ),
              child: const Text('选择分享'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('选择分享'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('share-picker-search')),
      'photos',
    );
    await tester.pumpAndSettle();
    expect(find.text('项目资料'), findsNothing);
    await tester.tap(find.text('旅行照片'));
    await tester.pumpAndSettle();
    expect(picked, ShareId.parse('photos01'));
  });

  testWidgets('聊天拖文件创建分享并发送到当前会话，坏文件不阻断其余文件', (tester) async {
    final messaging = RequestMessaging();
    addTearDown(messaging.updates.close);
    final paths = <String>[];
    await tester.pumpWidget(
      wrapShell(
        Scaffold(
          body: ChatPane(
            threadId: 'g_family',
            title: '家人群',
            self: PeerId.parse('p_localdevice00'),
            avatarSeed: 'family',
            messaging: messaging,
            enableDragDrop: true,
            shareCreator: (path) async {
              paths.add(path);
              if (path.contains('bad')) throw StateError('文件不可读');
              return ShareId.parse(
                path.endsWith('a.txt') ? 'share_a' : 'share_b',
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final target = tester.widget<DropTarget>(find.byType(DropTarget));
    target.onDragDone!(
      DropDoneDetails(
        files: [
          DropItemFile('D:/a.txt'),
          DropItemFile('D:/bad.txt'),
          DropItemFile('D:/b.txt'),
        ],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester.pumpAndSettle();
    expect(paths, hasLength(3));
    expect(messaging.files.map((f) => f.thread), ['g_family', 'g_family']);
    expect(messaging.files.map((f) => f.share.value), ['share_a', 'share_b']);
    expect(find.textContaining('已发送 2/3 项'), findsOneWidget);
  });

  testWidgets('自己的消息显示撤回按钮，执行后展示已撤回占位', (tester) async {
    final messaging = RequestMessaging();
    addTearDown(messaging.updates.close);
    await tester.pumpWidget(
      wrapShell(
        Scaffold(
          body: ChatPane(
            threadId: 'g_family',
            title: '家人群',
            self: PeerId.parse('p_localdevice00'),
            avatarSeed: 'family',
            messaging: messaging,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('chat-input')), '可以撤回的文字');
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pumpAndSettle();
    expect(find.text('撤回'), findsOneWidget);
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.down(
      tester.getRect(find.text('可以撤回的文字')).topLeft + const Offset(4, -5),
    );
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.text('撤回消息'), findsOneWidget);
    await tester.tap(find.text('撤回消息'));
    await tester.pumpAndSettle();
    expect(messaging.revoked, hasLength(1));
    expect(find.text('消息已撤回'), findsOneWidget);
    expect(find.text('可以撤回的文字'), findsNothing);
    expect(find.text('撤回'), findsNothing);
  });
}
