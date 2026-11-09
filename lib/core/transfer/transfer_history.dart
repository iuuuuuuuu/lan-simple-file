// SPDX-License-Identifier: GPL-3.0-only

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../contracts/contracts.dart';

final class TransferHistoryEntry {
  const TransferHistoryEntry({
    required this.id,
    required this.name,
    required this.direction,
    required this.status,
    required this.createdAt,
    this.peerLabel = '',
    this.peer,
    this.share,
    this.item,
    this.bytes,
    this.localPath,
    this.archive = false,
  });
  final String id, name, status, peerLabel;
  final TransferDirection direction;
  final DateTime createdAt;
  final PeerId? peer;
  final ShareId? share;
  final ItemKey? item;
  final int? bytes;
  final String? localPath;
  final bool archive;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'direction': direction.name,
    'status': status,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'peerLabel': peerLabel,
    'peer': peer?.value,
    'share': share?.value,
    'item': item?.value,
    'bytes': bytes,
    'localPath': localPath,
    'archive': archive,
  };

  factory TransferHistoryEntry.fromJson(
    Map<String, dynamic> data,
  ) => TransferHistoryEntry(
    id: data['id'] as String,
    name: data['name'] as String,
    direction: TransferDirection.values.byName(data['direction'] as String),
    status: data['status'] as String,
    createdAt: DateTime.parse(data['createdAt'] as String),
    peerLabel: data['peerLabel'] as String? ?? '',
    peer: data['peer'] == null ? null : PeerId.parse(data['peer'] as String),
    share: data['share'] == null
        ? null
        : ShareId.parse(data['share'] as String),
    item: data['item'] == null ? null : ItemKey.parse(data['item'] as String),
    bytes: data['bytes'] as int?,
    localPath: data['localPath'] as String?,
    archive: data['archive'] == true,
  );
}

abstract interface class TransferHistorySource {
  Future<List<TransferHistoryEntry>> list();
  Future<void> remove(Set<String> ids);
  Stream<void> get changes;
}

/// Keeps history independently of active tasks and never deletes source files.
final class StoreTransferHistory implements TransferHistorySource {
  StoreTransferHistory(this.store);
  final LanFileStore store;
  final _changes = StreamController<void>.broadcast();
  Future<void> _pending = Future.value();

  @override
  Stream<void> get changes => _changes.stream;

  Future<Map<String, dynamic>> _read() async {
    final raw = await store.getSetting('transfers.history');
    return raw == null
        ? {'entries': <dynamic>[], 'hidden': <dynamic>[]}
        : jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> _edit(void Function(Map<String, dynamic>) edit) {
    final result = _pending.then((_) async {
      final data = await _read();
      edit(data);
      await store.setSetting('transfers.history', jsonEncode(data));
      if (!_changes.isClosed) _changes.add(null);
    });
    _pending = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> record({
    required String name,
    required TransferDirection direction,
    required String status,
    String peerLabel = '',
    PeerId? peer,
    ShareId? share,
    ItemKey? item,
    int? bytes,
    String? localPath,
    bool archive = false,
  }) {
    final now = DateTime.now().toUtc();
    final entry = TransferHistoryEntry(
      id: 'web-${now.microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
      name: name,
      direction: direction,
      status: status,
      createdAt: now,
      peerLabel: peerLabel,
      peer: peer,
      share: share,
      item: item,
      bytes: bytes,
      localPath: localPath,
      archive: archive,
    );
    return _edit((data) => (data['entries'] as List).add(entry.toJson()));
  }

  @override
  Future<List<TransferHistoryEntry>> list() async {
    await _pending;
    final data = await _read();
    final hidden = (data['hidden'] as List).cast<String>().toSet();
    final entries = [
      for (final row in data['entries'] as List)
        TransferHistoryEntry.fromJson(row as Map<String, dynamic>),
      for (final transfer in await store.listTransfers())
        if (!hidden.contains('native-${transfer.id}'))
          TransferHistoryEntry(
            id: 'native-${transfer.id}',
            name: transfer.itemKey.value.split('/').last,
            direction: transfer.direction,
            status: transfer.status.name,
            createdAt: transfer.createdAt,
            peer: transfer.peerId,
            peerLabel: transfer.peerId.value,
            share: transfer.shareId,
            item: transfer.itemKey,
            bytes: transfer.bytesDone,
          ),
    ];
    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return entries;
  }

  @override
  Future<void> remove(Set<String> ids) => _edit((data) {
    (data['entries'] as List).removeWhere(
      (entry) => ids.contains((entry as Map)['id']),
    );
    data['hidden'] = <String>{
      ...(data['hidden'] as List).cast<String>(),
      ...ids.where((id) => id.startsWith('native-')),
    }.toList();
  });

  Future<void> dispose() async {
    await _pending;
    await _changes.close();
  }
}
