// SPDX-License-Identifier: GPL-3.0-only

import 'dart:convert';

import '../contracts/contracts.dart';

enum ChatSearchKind { all, text, files }

bool isFileMessage(MessageRecord message) => const {
  MessageKind.file,
  MessageKind.image,
  MessageKind.share,
}.contains(message.kind);

String messageSearchText(MessageRecord message) {
  if (!isFileMessage(message)) return message.body;
  try {
    final data = jsonDecode(message.attachJson);
    if (data is Map) {
      final names = <String>[
        if (data['name'] is String) data['name'] as String,
        if (data['fileName'] is String) data['fileName'] as String,
        if (data['files'] is List)
          for (final file in data['files'] as List)
            if (file is Map && file['name'] is String) file['name'] as String,
      ];
      if (names.isNotEmpty) return names.join(' · ');
      if (data['itemKey'] is String) {
        return (data['itemKey'] as String).split('/').last;
      }
    }
  } on FormatException {
    /* Old or unavailable attachments still have a body. */
  }
  return message.body.isNotEmpty ? message.body : '文件分享';
}

final class ChatSearchHit {
  const ChatSearchHit(this.thread, this.message);
  final ThreadRecord thread;
  final MessageRecord message;
  String get text => messageSearchText(message);
}

abstract interface class ChatSearchSource {
  Future<List<ChatSearchHit>> search(
    String query, {
    ChatSearchKind kind,
    String? threadId,
  });
}

final class StoreChatSearchSource implements ChatSearchSource {
  const StoreChatSearchSource(this.store);
  final LanFileStore store;

  @override
  Future<List<ChatSearchHit>> search(
    String query, {
    ChatSearchKind kind = ChatSearchKind.all,
    String? threadId,
  }) async {
    final words = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty && kind != ChatSearchKind.files) return [];
    final hits = <ChatSearchHit>[];
    for (final thread in await store.listThreads()) {
      if (thread.deletedAt != null ||
          (threadId != null && thread.id != threadId)) {
        continue;
      }
      for (final message in await store.listMessages(thread.id)) {
        if (message.isRevoked || message.revokeReason == 'deletedLocal') {
          continue;
        }
        final file = isFileMessage(message);
        if ((kind == ChatSearchKind.files && !file) ||
            (kind == ChatSearchKind.text && message.kind != MessageKind.text)) {
          continue;
        }
        final text = messageSearchText(message).toLowerCase();
        if (words.every(text.contains)) {
          hits.add(ChatSearchHit(thread, message));
        }
      }
    }
    hits.sort((a, b) => b.message.hlc.compareTo(a.message.hlc));
    return hits;
  }
}
