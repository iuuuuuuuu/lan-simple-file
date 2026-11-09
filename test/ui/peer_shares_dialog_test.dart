// SPDX-License-Identifier: GPL-3.0-only
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/net/peer_share_catalog.dart';
import 'package:lan_simple_file/ui/widgets/chat_pane.dart';
import 'package:lan_simple_file/ui/widgets/peer_shares_dialog.dart';
import 'package:lan_simple_file/ui/widgets/avatar_badge.dart';

import 'chat_workspace_test.dart' show ChatTestService;
import 'requested_features_test.dart' show png;
import 'support/miuix_test_support.dart';
import 'support/ui_fakes.dart' show wrapWithTheme;

final sharesPeer = PeerId.parse('p_aaaaaaaaaaaaa');
final sharesId = ShareId.parse('share_test');
final sharesCatalog = PeerShareCatalog(
  name: '好好吃饭',
  shares: [
    PeerShareEntry(
      name: '旅行照片',
      isDirectory: true,
      access: 'browse',
      id: sharesId,
    ),
    const PeerShareEntry(name: '工作资料', isDirectory: true, access: 'password'),
  ],
);

PeerSharesDialog sharesDialog({
  Uint8List? avatar,
  Future<PeerShareCatalog> Function()? load,
  Future<FileEntryPage> Function(ShareId, {ItemKey? path, String? cursor})?
  browse,
  Future<void> Function(Uri)? open,
  Future<void> Function(ShareId, FileEntry)? record,
}) => PeerSharesDialog(
  peer: sharesPeer,
  name: '好好吃饭',
  avatarBytes: avatar,
  loadCatalog: load ?? () async => sharesCatalog,
  browse:
      browse ?? (id, {path, cursor}) async => const FileEntryPage(entries: []),
  homeLink: () async => Uri.parse('http://phone.local/'),
  shareLink: (id) async => Uri.parse('http://phone.local/s/${id.value}'),
  openLink: open ?? (_) async {},
  onFileOpened: record,
);

Future<void> showShares(WidgetTester tester, PeerSharesDialog dialog) async {
  await tester.pumpWidget(
    wrapWithTheme(
      Builder(
        builder: (context) => AppButton(
          onPressed: () =>
              showAppDialog<void>(context: context, builder: (_) => dialog),
          child: const Text('show'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('show'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('only successful file launches record external handoff', (
    tester,
  ) async {
    var fail = false;
    final recorded = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await showShares(
      tester,
      sharesDialog(
        open: (_) async {
          if (fail) throw StateError('launch failed');
        },
        record: (share, file) async =>
            recorded.add('${share.value}/${file.name}'),
        browse: (_, {path, cursor}) async => const FileEntryPage(
          entries: [
            FileEntry(
              itemKey: ItemKey('report.pdf'),
              name: 'report.pdf',
              kind: EntryKind.file,
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.text('旅行照片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('report.pdf'));
    await tester.pumpAndSettle();
    expect(recorded, ['share_test/report.pdf']);
    fail = true;
    await tester.tap(find.text('report.pdf'));
    await tester.pumpAndSettle();
    expect(recorded, hasLength(1));
    expect(find.text('打开链接失败，请重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('drawer keeps the custom chat avatar and folders first', (
    tester,
  ) async {
    await showShares(
      tester,
      sharesDialog(
        avatar: png,
        load: () async => PeerShareCatalog(
          name: 'peer',
          shares: [
            PeerShareEntry(
              name: 'a.txt',
              isDirectory: false,
              access: 'browse',
              id: sharesId,
            ),
            const PeerShareEntry(
              name: 'z-folder',
              isDirectory: true,
              access: 'password',
            ),
          ],
        ),
      ),
    );
    final badge = tester.widget<AvatarBadge>(find.byType(AvatarBadge));
    expect(badge.avatarBytes, same(png));
    expect(badge.peerId, sharesPeer.value);
    expect(
      tester.getTopLeft(find.text('z-folder')).dy,
      lessThan(tester.getTopLeft(find.text('a.txt')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'catalog search, restrictions, nested navigation, paging and exact file link',
    (tester) async {
      final requests = <({ItemKey? path, String? cursor})>[];
      final opened = <Uri>[];
      await showShares(
        tester,
        sharesDialog(
          open: (uri) async => opened.add(uri),
          browse: (id, {path, cursor}) async {
            requests.add((path: path, cursor: cursor));
            expect(id, sharesId);
            if (path == null) {
              return const FileEntryPage(
                entries: [
                  FileEntry(
                    itemKey: ItemKey('primary:1/photos'),
                    name: '2026',
                    kind: EntryKind.directory,
                  ),
                ],
              );
            }
            return FileEntryPage(
              entries: [
                FileEntry(
                  itemKey: ItemKey(
                    'primary:1/photos/${cursor == null ? '100%20.txt' : 'b.txt'}',
                  ),
                  name: cursor == null ? '100%20.txt' : 'b.txt',
                  kind: EntryKind.file,
                  size: 12,
                ),
              ],
              nextCursor: cursor == null ? 'page2' : null,
            );
          },
        ),
      );
      expect(find.text('好好吃饭的分享'), findsOneWidget);
      expect(find.text('需要密码'), findsOneWidget);
      await tester.tap(find.text('工作资料'));
      expect(requests, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('peer-shares-search')),
        '不存在',
      );
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的分享'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('peer-shares-search')),
        '',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('旅行照片'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('100%20.txt'));
      await tester.pumpAndSettle();
      expect(opened.single.host, 'phone.local');
      expect(opened.single.pathSegments.last, '100%20.txt');
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(find.text('b.txt'), findsOneWidget);
      expect(requests.last.cursor, 'page2');
      await tester.tap(find.byKey(const ValueKey('peer-shares-back')));
      await tester.pumpAndSettle();
      expect(requests.last.path, isNull);
      await tester.tap(find.byKey(const ValueKey('peer-shares-back')));
      await tester.pumpAndSettle();
      expect(find.text('工作资料'), findsOneWidget);
      await tester.tap(findAppTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(PeerSharesDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('loading, failure, retry and empty state on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final pending = Completer<PeerShareCatalog>();
    var calls = 0;
    await tester.pumpWidget(
      wrapWithTheme(
        sharesDialog(
          load: () {
            calls++;
            return calls == 1
                ? pending.future
                : Future.value(
                    const PeerShareCatalog(name: '好好吃饭', shares: []),
                  );
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(MiuixCircularProgressIndicator), findsOneWidget);
    pending.completeError(
      const LanFileException(LanFileErrorCode.network, '连接失败'),
    );
    await tester.pumpAndSettle();
    expect(find.text('连接失败'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('暂无公开分享'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'single header and group message avatars use the correct peer IDs',
    (tester) async {
      final self = PeerId.parse('p_localdevice00');
      final other = PeerId.parse('p_bbbbbbbbbbbbb');
      final clicked = <PeerId>[];
      final messaging = ChatTestService();
      addTearDown(messaging.updates.close);
      messaging.messages['g_test'] = [
        for (final peer in [self, other])
          MessageRecord(
            id: peer.value,
            threadId: 'g_test',
            senderPeerId: peer,
            kind: MessageKind.text,
            hlc: Hlc(millis: 1, counter: 0, origin: peer.value),
            ts: DateTime(2026),
            body: 'hello',
            attachJson: '',
            sig: '',
          ),
      ];
      await tester.pumpWidget(
        wrapWithTheme(
          ChatPane(
            threadId: 'direct',
            title: 'peer',
            self: self,
            avatarSeed: sharesPeer.value,
            avatarBytes: png,
            peer: sharesPeer,
            onShowShares: clicked.add,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('chat-header-avatar')));
      expect(
        tester.widget<AvatarBadge>(find.byType(AvatarBadge)).avatarBytes,
        same(png),
      );
      expect(clicked, [sharesPeer]);
      await tester.pumpWidget(
        wrapWithTheme(
          ChatPane(
            key: const ValueKey('group'),
            threadId: 'g_test',
            title: 'group',
            self: self,
            avatarSeed: 'group',
            selfAvatarBytes: png,
            senderAvatars: {other.value: png},
            messaging: messaging,
            onShowShares: clicked.add,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-header-avatar')), findsNothing);
      for (final peer in [self, other]) {
        final avatar = find.descendant(
          of: find.byKey(ValueKey('chat-avatar-${peer.value}')),
          matching: find.byType(AvatarBadge),
        );
        expect(tester.widget<AvatarBadge>(avatar).avatarBytes, same(png));
        await tester.tap(find.byKey(ValueKey('chat-avatar-${peer.value}')));
      }
      expect(clicked, [sharesPeer, self, other]);
    },
  );
}
