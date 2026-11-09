// SPDX-License-Identifier: GPL-3.0-only

import 'dart:convert';

import '../contracts/contracts.dart';

/// Presentation groups are independent of access-control groups on ShareRecord.
final class ShareOrganization {
  const ShareOrganization({
    this.names = const {},
    this.assignments = const {},
    this.order = const [],
    this.groupOrder = const [],
  });

  final Map<String, String> names;
  final Map<String, String> assignments;
  final List<String> order;
  final List<String> groupOrder;

  String groupOf(String share) {
    final group = assignments[share];
    return names.containsKey(group) ? group! : '';
  }

  List<String> get groups => <String>{
    ...groupOrder.where((id) => id.isEmpty || names.containsKey(id)),
    '',
    ...names.keys,
  }.toList();

  ShareOrganization copyWith({
    Map<String, String>? names,
    Map<String, String>? assignments,
    List<String>? order,
    List<String>? groupOrder,
  }) => ShareOrganization(
    names: names ?? this.names,
    assignments: assignments ?? this.assignments,
    order: order ?? this.order,
    groupOrder: groupOrder ?? this.groupOrder,
  );

  ShareOrganization removeGroup(String id) => copyWith(
    names: {...names}..remove(id),
    assignments: {
      for (final entry in assignments.entries)
        if (entry.value != id) entry.key: entry.value,
    },
    groupOrder: groupOrder.where((group) => group != id).toList(),
  );

  ShareOrganization move(Iterable<String> shares, String group) {
    if (group.isNotEmpty && !names.containsKey(group)) {
      throw const FormatException('Unknown share group');
    }
    return copyWith(
      assignments: {...assignments, for (final id in shares) id: group},
    );
  }

  ShareOrganization place(
    Iterable<ShareRecord> shares, {
    required String share,
    required String target,
    required bool after,
  }) {
    final ids = arrange(shares).map((item) => item.id.value).toList();
    if (share == target || !ids.contains(share) || !ids.contains(target)) {
      return this;
    }
    ids.remove(share);
    ids.insert(ids.indexOf(target) + (after ? 1 : 0), share);
    return move([share], groupOf(target)).copyWith(order: ids);
  }

  List<ShareRecord> arrange(Iterable<ShareRecord> shares, {String? group}) {
    final groupRanks = {for (final (i, id) in groups.indexed) id: i};
    final ranks = {for (final (i, id) in order.indexed) id: i};
    return shares
        .where((s) => group == null || groupOf(s.id.value) == group)
        .toList()
      ..sort((a, b) {
        final byGroup = groupRanks[groupOf(a.id.value)]!.compareTo(
          groupRanks[groupOf(b.id.value)]!,
        );
        if (byGroup != 0) return byGroup;
        final byOrder = (ranks[a.id.value] ?? order.length).compareTo(
          ranks[b.id.value] ?? order.length,
        );
        if (byOrder != 0) return byOrder;
        if ((a.kind == 'folder') != (b.kind == 'folder')) {
          return a.kind == 'folder' ? -1 : 1;
        }
        final byName = a.displayName.compareTo(b.displayName);
        return byName != 0 ? byName : a.id.compareTo(b.id);
      });
  }

  Map<String, Object> toJson() => {
    'names': names,
    'assignments': assignments,
    'order': order,
    'groupOrder': groupOrder,
  };

  factory ShareOrganization.fromJson(Map<String, dynamic> data) =>
      ShareOrganization(
        names: Map<String, String>.from(data['names'] as Map? ?? {}),
        assignments: Map<String, String>.from(
          data['assignments'] as Map? ?? {},
        ),
        order: List<String>.from(data['order'] as List? ?? []),
        groupOrder: List<String>.from(data['groupOrder'] as List? ?? []),
      );
}

abstract interface class ShareOrganizationSource {
  Future<ShareOrganization> load();
  Future<void> save(ShareOrganization organization);
}

final class StoreShareOrganizationSource implements ShareOrganizationSource {
  const StoreShareOrganizationSource(this.store);
  final LanFileStore store;

  @override
  Future<ShareOrganization> load() async {
    final raw = await store.getSetting('shares.organization');
    return raw == null
        ? const ShareOrganization()
        : ShareOrganization.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> save(ShareOrganization organization) => store.setSetting(
    'shares.organization',
    jsonEncode(organization.toJson()),
  );
}
