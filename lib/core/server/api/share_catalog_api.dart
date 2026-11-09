// SPDX-License-Identifier: GPL-3.0-only

import 'dart:io';

import '../../contracts/contracts.dart';
import '../../shares/share_organization.dart';
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
  ShareOrganizationSource? organization,
  DateTime Function()? now,
}) {
  router.get('/api/v1/shared-roots', (request) async {
    final time = (now ?? DateTime.now)();
    final layout = await organization?.load() ?? const ShareOrganization();
    final selectedGroup = request.uri.queryParameters['group'];
    if (selectedGroup != null &&
        selectedGroup.isNotEmpty &&
        !layout.names.containsKey(selectedGroup)) {
      await jsonResponse(request.response, HttpStatus.notFound, {
        'error': '分享分组不存在或已删除',
      });
      return;
    }
    final entries = <Map<String, Object?>>[];
    for (final share in layout.arrange(await listMine())) {
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
        'collectionId': layout.groupOf(share.id.value),
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
      'groups': [
        for (final group in layout.groups)
          if (entries.any((entry) => entry['collectionId'] == group) ||
              group == selectedGroup)
            {'id': group, 'name': layout.names[group] ?? '未分组'},
      ],
      'order': 'owner',
      'selectedGroup': selectedGroup,
      'shares': selectedGroup == null
          ? entries
          : entries
                .where((entry) => entry['collectionId'] == selectedGroup)
                .toList(),
    });
  });
}
