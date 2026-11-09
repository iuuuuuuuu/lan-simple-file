// SPDX-License-Identifier: GPL-3.0-only
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/messaging/chat_search.dart';
import 'package:lan_simple_file/core/store/store_impl.dart';

final searchPeer = PeerId.parse('p_aaaaaaaaaaaaa');
ThreadRecord searchThread(String id, {bool deleted = false}) => ThreadRecord(
  id: id,
  kind: 'direct',
  title: id,
  avatarHash: '',
  unread: 0,
  muted: false,
  pinned: false,
  createdAt: DateTime.utc(2026),
  peerId: searchPeer,
  deletedAt: deleted ? DateTime.utc(2026) : null,
);
MessageRecord searchMessage(
  String id, {
  String thread = 'one',
  String body = '',
  String attach = '',
  MessageKind kind = MessageKind.text,
  bool revoked = false,
  String? reason,
  int time = 1,
}) => MessageRecord(
  id: id,
  threadId: thread,
  senderPeerId: searchPeer,
  kind: kind,
  hlc: Hlc(millis: time, counter: 0, origin: searchPeer.value),
  ts: DateTime.utc(2026),
  body: body,
  attachJson: attach,
  sig: '',
  revokedAt: revoked ? DateTime.utc(2026) : null,
  revokeReason: reason,
);

void main() {
  test(
    'persistent global/thread search filters files and hides deleted messages',
    () async {
      final directory = await Directory.systemTemp.createTemp('chat-search-');
      final db = File('${directory.path}/search.sqlite');
      var store = await LanFileStoreImpl.open(dbFile: db);
      addTearDown(() async {
        await store.close();
        await directory.delete(recursive: true);
      });
      for (final thread in [
        searchThread('one'),
        searchThread('two'),
        searchThread('gone', deleted: true),
      ]) {
        await store.upsertThread(thread);
      }
      for (final message in [
        searchMessage('text', body: '项目 REPORT ready', time: 1),
        searchMessage(
          'file',
          kind: MessageKind.file,
          attach: '{"name":"项目 Report.pdf","token":"secret"}',
          time: 2,
        ),
        searchMessage(
          'photo',
          kind: MessageKind.image,
          thread: 'two',
          attach: '{"itemKey":"photos/旅行.png"}',
          time: 3,
        ),
        searchMessage('revoked', body: '项目 Report', revoked: true),
        searchMessage('local', body: '项目 Report', reason: 'deletedLocal'),
        searchMessage('deleted-thread', body: '项目 Report', thread: 'gone'),
      ]) {
        await store.putMessage(message);
      }
      await store.close();
      store = await LanFileStoreImpl.open(dbFile: db);
      final search = StoreChatSearchSource(store);
      expect((await search.search('REPORT 项目')).map((h) => h.message.id), [
        'file',
        'text',
      ]);
      expect(
        (await search.search(
          'report',
          kind: ChatSearchKind.text,
        )).single.message.id,
        'text',
      );
      expect(
        (await search.search(
          '',
          kind: ChatSearchKind.files,
        )).map((h) => h.message.id),
        ['photo', 'file'],
      );
      expect(
        (await search.search(
          '',
          kind: ChatSearchKind.files,
          threadId: 'one',
        )).single.message.id,
        'file',
      );
      expect(await search.search('旅行', threadId: 'one'), isEmpty);
      expect(await search.search('secret'), isEmpty);
      expect(await search.search(''), isEmpty);
      expect(
        messageSearchText(
          searchMessage(
            'bad',
            kind: MessageKind.file,
            body: 'old.txt',
            attach: 'broken',
          ),
        ),
        'old.txt',
      );
    },
  );
}
