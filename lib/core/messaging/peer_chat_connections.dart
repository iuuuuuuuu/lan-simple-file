// SPDX-License-Identifier: GPL-3.0-only
import 'dart:async';

import '../contracts/contracts.dart';
import '../net/lan_address_guard.dart';
import 'messaging_service_impl.dart';
import 'ws_client_endpoint.dart';

/// 发现设备后静默建链；使用固定方向，避免双方同时重连互相替换。
final class PeerChatConnections {
  PeerChatConnections({
    required this.self,
    required this.messaging,
    required this.endpointFor,
    required this.nameReader,
    required this.avatarReader,
    required this.headersFor,
  });
  final PeerId self;
  final MessagingServiceImpl messaging;
  final Future<({String host, int port})?> Function(PeerId) endpointFor;
  final String Function() nameReader;
  final String Function() avatarReader;
  final Future<Map<String, String>> Function(PeerId) headersFor;
  final Map<PeerId, WsClientEndpoint> _clients = {};
  final Map<PeerId, Future<void>> _connecting = {};
  bool _disposed = false;
  StreamSubscription<List<PeerView>>? _subscription;

  void start(Stream<List<PeerView>> peers) {
    _subscription = peers.listen((views) {
      for (final peer in views) {
        if (peer.online && self.value.compareTo(peer.peerId.value) < 0) {
          unawaited(connect(peer.peerId).catchError((Object _) {}));
        }
      }
    });
  }

  Future<void> connect(PeerId peer) {
    if (_disposed || peer == self || messaging.isPeerOnline(peer)) {
      return Future.value();
    }
    return _connecting.putIfAbsent(peer, () {
      final task = _connect(peer);
      unawaited(
        task.then<void>(
          (_) {
            _connecting.remove(peer);
          },
          onError: (Object _, StackTrace _) {
            _connecting.remove(peer);
          },
        ),
      );
      return task;
    });
  }

  Future<void> _connect(PeerId peer) async {
    final endpoint = await endpointFor(peer);
    if (_disposed || endpoint == null) return;
    LanAddressGuard.requireCleartextAllowed(endpoint.host);
    var client = _clients[peer];
    if (client != null &&
        (client.host != endpoint.host || client.port != endpoint.port)) {
      await client.dispose();
      client = null;
    }
    client ??= WsClientEndpoint(
      host: endpoint.host,
      port: endpoint.port,
      localPeerId: self,
      localName: nameReader(),
      localAvatarHash: avatarReader(),
      localCapabilities: WsFrame.all,
      connectTimeout: const Duration(seconds: 2),
      headersReader: () => headersFor(peer),
      onLinkUp: (link) async {
        final remote = await link.handshake;
        if (_disposed || remote.peerId != peer) {
          await link.close(reason: 'unexpected peer');
          return;
        }
        await messaging.adoptOutboundLink(peer, link);
      },
    );
    _clients[peer] = client;
    await client.connect();
  }

  Future<void> dispose() async {
    _disposed = true;
    await _subscription?.cancel();
    for (final client in _clients.values.toList()) {
      await client.dispose();
    }
    await Future.wait(
      _connecting.values.map((task) => task.catchError((Object _) {})),
    );
    _clients.clear();
  }
}
