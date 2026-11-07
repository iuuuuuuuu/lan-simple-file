// SPDX-License-Identifier: GPL-3.0-only
import 'dart:async';

import '../contracts/contracts.dart';
import '../net/peer_local_domain.dart';
import 'browser_link_policy.dart';

/// Prepare browser access when a device is discovered, before a link is copied.
final class PeerBrowserLinks {
  PeerBrowserLinks({
    required this.self,
    required this.domainForPeer,
    this.policy = const BrowserLinkPolicy(),
    this.refreshInterval = const Duration(minutes: 2),
    this.clock = DateTime.now,
  });

  final PeerId self;
  final Future<PeerLocalDomain?> Function(PeerId) domainForPeer;
  final BrowserLinkPolicy policy;
  final Duration refreshInterval;
  final DateTime Function() clock;
  final Map<PeerId, ({String name, DateTime next})> _checked = {};
  List<PeerView> _peers = [];
  StreamSubscription<List<PeerView>>? _subscription;
  Timer? _timer;
  Future<void>? _pending;
  bool _requested = false, _disposed = false;

  void start(Stream<List<PeerView>> peers) {
    _subscription = peers.listen((views) {
      _peers = views.where((p) => p.online && p.peerId != self).toList();
      final ids = _peers.map((p) => p.peerId).toSet();
      _checked.removeWhere((id, _) => !ids.contains(id));
      unawaited(refresh());
    }, onError: (Object _) {});
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(refresh());
    });
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    _requested = true;
    return _pending ??= _drain().whenComplete(() => _pending = null);
  }

  Future<void> _drain() async {
    while (_requested && !_disposed) {
      _requested = false;
      for (final peer in _peers.toList()) {
        if (_disposed) return;
        final previous = _checked[peer.peerId];
        if (previous?.name == peer.name && clock().isBefore(previous!.next)) {
          continue;
        }
        var repaired = false;
        try {
          final domain = await domainForPeer(peer.peerId);
          if (_disposed) return;
          // A peer may have gone offline while its metadata request was pending.
          if (!_peers.any(
            (p) => p.peerId == peer.peerId && p.name == peer.name,
          )) {
            continue;
          }
          repaired =
              domain != null && await policy.domainFor(domain.host) != null;
        } on Object {
          // Discovery and direct file transfers remain available during failures.
        }
        if (_disposed) return;
        _checked[peer.peerId] = (
          name: peer.name,
          next: clock().add(
            repaired ? refreshInterval : const Duration(seconds: 30),
          ),
        );
      }
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    await _subscription?.cancel();
    await _pending;
    _checked.clear();
    _peers = [];
  }
}
