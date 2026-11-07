// SPDX-License-Identifier: GPL-3.0-only

import 'dart:io';

import '../../contracts/contracts.dart';
import '../response.dart';
import '../router.dart';
import 'share_api.dart';

void registerShareCatalogRoutes(
  Router router, {
  required ShareSource source,
  required Future<List<ShareRecord>> Function() listMine,
  required PeerId owner,
  required String Function() nameReader,
  required String Function() avatarReader,
  DateTime Function()? now,
}) {
  router.get('/api/v1/shared-roots', (request) async {
    final time = (now ?? DateTime.now)();
    final entries = <Map<String, Object?>>[];
    for (final share in await listMine()) {
      if (share.ownerPeerId != owner ||
          !share.enabled ||
          share.missing ||
          share.isRevoked ||
          share.isEphemeral ||
          share.mode == ShareMode.offer ||
          share.mode == ShareMode.session ||
          (share.expiresAt != null && !share.expiresAt!.isAfter(time))) {
        continue;
      }
      if (await source.find(share.id) == null) continue;
      final browsable =
          share.mode == ShareMode.lan || share.mode == ShareMode.token;
      // Restricted shares expose neither their identifier nor credentials.
      // File-system roots and private transfer/session shares never leave here.
      entries.add({
        'name': share.displayName,
        'kind': share.kind,
        'createdAt': share.createdAt.toUtc().millisecondsSinceEpoch,
        'access': browsable ? 'browse' : share.mode.name,
        'href': browsable ? '/s/${Uri.encodeComponent(share.id.value)}' : null,
      });
    }
    await jsonResponse(request.response, HttpStatus.ok, {
      'owner': {
        'name': nameReader(),
        'peerId': owner.value,
        'avatar':
            '/api/v1/avatar/${owner.value}'
            '?v=${Uri.encodeQueryComponent(avatarReader())}',
      },
      'shares': entries,
    });
  });
}
