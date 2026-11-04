// SPDX-License-Identifier: GPL-3.0-only

library;

import 'dart:convert';

import '../contracts/contracts.dart';

/// 联系人分组独立于群聊和对方广播的资料。
final class PeerGroups {
  const PeerGroups({
    this.names = const <String, String>{},
    this.assignments = const <String, String>{},
  });
  final Map<String, String> names;
  final Map<String, String> assignments;

  String groupOf(PeerId peer) {
    return groupOfSession(peer.value);
  }

  String groupOfSession(String sessionId) {
    final String? id = assignments[sessionId];
    return names.containsKey(id) ? id! : '';
  }
}

abstract interface class PeerGroupsSource {
  Future<PeerGroups> load();
  Future<void> save(PeerGroups groups);
}

final class StorePeerGroupsSource implements PeerGroupsSource {
  const StorePeerGroupsSource(this.store);
  final LanFileStore store;

  @override
  Future<PeerGroups> load() async {
    final String? raw = await store.getSetting('people.groups');
    if (raw == null || raw.isEmpty) return const PeerGroups();
    final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
    return PeerGroups(
      names: Map<String, String>.from(data['names'] as Map),
      assignments: Map<String, String>.from(data['assignments'] as Map),
    );
  }

  @override
  Future<void> save(PeerGroups groups) => store.setSetting(
    'people.groups',
    jsonEncode(<String, Object>{
      'names': groups.names,
      'assignments': groups.assignments,
    }),
  );
}
