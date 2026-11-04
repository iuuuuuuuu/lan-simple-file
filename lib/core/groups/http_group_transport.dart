// SPDX-License-Identifier: GPL-3.0-only

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../contracts/contracts.dart';
import '../identity/ed25519_signer.dart';
import '../net/lan_address_guard.dart';
import '../server/api/profile_api.dart';
import '../server/response.dart';
import 'group_member_sync.dart';
import 'group_service_impl.dart';

typedef GroupEndpointReader = Future<({String host, int port})?> Function(
  PeerId peer,
);

/// 群邀请先持久化，再通过局域网 HTTP 发送；离线成员上线后重试。
final class HttpGroupTransport implements GroupBroadcaster {
  HttpGroupTransport({
    required this.store,
    required this.identity,
    required this.endpointFor,
    required this.nameReader,
    required this.avatarHashReader,
  });
  final LanFileStore store;
  final DeviceIdentity identity;
  final GroupEndpointReader endpointFor;
  final String Function() nameReader;
  final String Function() avatarHashReader;
  final Map<String, Map<String, dynamic>> _outbox =
      <String, Map<String, dynamic>>{};
  Future<void> _writes = Future<void>.value();
  bool _flushing = false;
  bool _disposed = false;
  Future<void>? _flushTask;
  final Set<HttpClient> _clients = <HttpClient>{};
  static const String _outboxKey = 'groups.outbox';
  static const String path = '/api/v1/group-events';

  Future<void> load() async {
    final String? raw = await store.getSetting(_outboxKey);
    if (raw == null || raw.isEmpty) return;
    final Map<String, dynamic> saved = jsonDecode(raw) as Map<String, dynamic>;
    for (final entry in saved.entries) {
      _outbox[entry.key] = Map<String, dynamic>.from(entry.value as Map);
    }
  }

  Future<void> _write(void Function() change) {
    final Future<void> task = _writes.then((_) async {
      change();
      await store.setSetting(_outboxKey, jsonEncode(_outbox));
    });
    _writes = task.catchError((Object _) {});
    return task;
  }

  @override
  Future<void> broadcast(GroupEvent event) async {
    final List<GroupMemberRecord> members = await store.listGroupMembers(
      event.groupId,
    );
    final String payload = jsonEncode(<String, Object?>{
      'event': event.toJson(),
      'name': nameReader(),
      'avatarHash': avatarHashReader(),
      'members': <String>[for (final member in members) member.peerId.value],
    });
    final Map<String, Object?> envelope = <String, Object?>{
      'payload': payload,
      'publicKey': base64Url.encode(identity.publicKey),
      'signature': base64Url.encode(await identity.sign(_signable(payload))),
    };
    final Set<PeerId> recipients = event.kind == GroupEventKind.invite
        ? <PeerId>{if (event.subject != null) event.subject!}
        : <PeerId>{
            for (final member in members) member.peerId,
            if (event.subject != null) event.subject!,
          };
    recipients.remove(identity.peerId);
    await _write(() {
      for (final PeerId peer in recipients) {
        final String id = '${groupEventKey(event)}:${peer.value}';
        _outbox[id] = <String, dynamic>{
          'peer': peer.value,
          'envelope': envelope,
        };
      }
    });
    unawaited(flush());
  }

  Future<void> flush() {
    if (_flushing || _disposed) return _flushTask ?? Future<void>.value();
    _flushing = true;
    return _flushTask = _flush().whenComplete(() => _flushing = false);
  }

  Future<void> _flush() async {
    for (final entry in List<MapEntry<String, Map<String, dynamic>>>.of(
      _outbox.entries,
    )) {
      if (_disposed) return;
      final PeerId peer = PeerId.parse(entry.value['peer'] as String);
      try {
        final ({String host, int port})? endpoint = await endpointFor(peer);
        if (endpoint == null) continue;
        LanAddressGuard.requireCleartextAllowed(endpoint.host);
        final HttpClient client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 2);
        _clients.add(client);
        try {
          final HttpClientRequest request = await client.postUrl(
            Uri(
              scheme: 'http',
              host: endpoint.host,
              port: endpoint.port,
              path: path,
            ),
          );
          request.followRedirects = false;
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(entry.value['envelope']));
          final HttpClientResponse response = await request.close().timeout(
            const Duration(seconds: 2),
          );
          final bool delivered = response.statusCode == HttpStatus.ok;
          await response.drain<void>().timeout(const Duration(seconds: 2));
          if (delivered) await _write(() => _outbox.remove(entry.key));
        } finally {
          _clients.remove(client);
          client.close(force: true);
        }
      } on Object {
        // 保留已落库的邀请，下一轮发现更新时重试。
      }
    }
  }

  Future<void> receive(
    HttpRequest request,
    GroupService groups,
    Future<void> Function() onChanged,
  ) async {
    final Map<String, Object?> envelope = await readJsonObject(
      request,
      maxBytes: 256 * 1024,
    );
    try {
      final String payload = envelope['payload'] as String;
      final Uint8List key = base64Url.decode(envelope['publicKey'] as String);
      final Uint8List signature = base64Url.decode(
        envelope['signature'] as String,
      );
      if (key.length != kEd25519PublicKeyBytes ||
          !await Ed25519Signer().verify(_signable(payload), signature, key)) {
        throw const LanFileException(LanFileErrorCode.accessDenied, '群事件签名无效');
      }
      final Map<String, dynamic> data =
          jsonDecode(payload) as Map<String, dynamic>;
      final GroupEvent event = GroupEvent.fromJson(
        Map<String, Object?>.from(data['event'] as Map),
      );
      if (derivePeerId(key) != event.actor ||
          !RegExp(r'^[a-z0-9_-]{1,64}$').hasMatch(event.groupId) ||
          event.ts.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
        throw const LanFileException(
          LanFileErrorCode.accessDenied,
          '群事件来源或标识无效',
        );
      }
      final String receipt =
          'groups.received.${sha256.convert(utf8.encode(groupEventKey(event)))}';
      if (await store.getSetting(receipt) != null) {
        await jsonResponse(request.response, HttpStatus.ok, <String, Object?>{
          'ok': true,
        });
        return;
      }
      final Set<PeerId> members = <PeerId>{
        for (final Object? raw in data['members'] as List)
          PeerId.parse(raw as String),
      };
      final GroupRecord? existing = await store.findGroup(event.groupId);
      final String name = normalizeProfileName(data['name'] as String);
      final String avatar = normalizeAvatarHash(data['avatarHash'] as String);
      if (event.kind == GroupEventKind.invite &&
          (members.length > 200 ||
              !members.contains(identity.peerId) ||
              !members.contains(event.actor))) {
        throw const LanFileException(
          LanFileErrorCode.accessDenied,
          '邀请的成员名单无效',
        );
      }
      if (!await groups.applyRemoteEvent(event)) {
        throw const LanFileException(
          LanFileErrorCode.accessDenied,
          '没有管理这个群的权限',
        );
      }
      if (event.kind == GroupEventKind.invite && existing == null) {
        for (final PeerId member in members) {
          await store.putGroupMember(
            GroupMemberRecord(
              groupId: event.groupId,
              peerId: member,
              role: member == event.actor ? kGroupRoleOwner : kGroupRoleMember,
              joinedAt: event.ts,
            ),
          );
        }
      }
      final DeviceRecord? old = await store.findDevice(event.actor);
      await store.upsertDevice(
        DeviceRecord(
          peerId: event.actor,
          publicKey: key,
          name: name,
          avatarHash: avatar,
          os: old?.os ?? '',
          firstSeen: old?.firstSeen ?? DateTime.now().toUtc(),
          lastSeen: old?.lastSeen ?? DateTime.now().toUtc(),
          online: old?.online ?? true,
          isSelf: false,
          isGuest: false,
          note: old?.note ?? '',
        ),
      );
      await store.setSetting(receipt, '1');
      await onChanged();
      await jsonResponse(request.response, HttpStatus.ok, <String, Object?>{
        'ok': true,
      });
    } on LanFileException {
      rethrow;
    } on Object catch (error) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '群事件格式无效',
        cause: error,
      );
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final HttpClient client in _clients) {
      client.close(force: true);
    }
    await _flushTask;
    await _writes;
  }
}

Uint8List _signable(String payload) =>
    Uint8List.fromList(utf8.encode('group-event\u0000$payload'));
