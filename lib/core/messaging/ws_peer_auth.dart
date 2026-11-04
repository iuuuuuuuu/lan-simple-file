// SPDX-License-Identifier: GPL-3.0-only
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../contracts/contracts.dart';

/// 升级前验证身份；hello 中的昵称和 ID 不能作为读聊天历史的凭证。
final class WsPeerAuth {
  WsPeerAuth({
    required this.identity,
    required this.keys,
    required this.verifier,
  });
  final DeviceIdentity identity;
  final PublicKeyLookup keys;
  final SignatureVerifier verifier;
  final Map<String, DateTime> _used = {};

  Uint8List _proof(
    PeerId from,
    PeerId to,
    String time,
    String nonce,
  ) => Uint8List.fromList(
    utf8.encode(
      'ws-connect\u0000${from.value}\u0000${to.value}\u0000$time\u0000$nonce',
    ),
  );

  Future<Map<String, String>> headers(PeerId target) async {
    final random = Random.secure();
    final nonce = base64Url.encode(
      List.generate(24, (_) => random.nextInt(256)),
    );
    final time = DateTime.now().toUtc().millisecondsSinceEpoch.toString();
    return {
      'x-lsf-peer': identity.peerId.value,
      'x-lsf-time': time,
      'x-lsf-nonce': nonce,
      'x-lsf-signature': base64Url.encode(
        await identity.sign(_proof(identity.peerId, target, time, nonce)),
      ),
    };
  }

  Future<PeerId?> authenticate(HttpRequest request) async {
    try {
      final peer = PeerId.tryParse(request.headers.value('x-lsf-peer') ?? '');
      final time = request.headers.value('x-lsf-time') ?? '';
      final nonce = request.headers.value('x-lsf-nonce') ?? '';
      final signature = request.headers.value('x-lsf-signature') ?? '';
      final milliseconds = int.tryParse(time);
      final now = DateTime.now().toUtc();
      _used.removeWhere((_, at) => now.difference(at).inMinutes >= 2);
      if (peer == null ||
          milliseconds == null ||
          nonce.length > 64 ||
          nonce.length < 24 ||
          signature.length > 128 ||
          (now.millisecondsSinceEpoch - milliseconds).abs() > 60000) {
        return null;
      }
      final receipt = '${peer.value}:$nonce';
      if (_used.containsKey(receipt) || _used.length >= 4096) return null;
      final key = await keys.findPublicKey(peer);
      if (key == null ||
          !await verifier.verify(
            _proof(peer, identity.peerId, time, nonce),
            base64Url.decode(signature),
            key,
          )) {
        return null;
      }
      if (_used.containsKey(receipt)) return null;
      _used[receipt] = now;
      return peer;
    } on Object {
      return null;
    }
  }
}
