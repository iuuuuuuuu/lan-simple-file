// SPDX-License-Identifier: GPL-3.0-only

import 'dart:io';

import '../../contracts/contracts.dart';

typedef ShareDownloadObserver = Future<void> Function(ShareDownloadEvent event);

final class ShareDownloadEvent {
  const ShareDownloadEvent({
    required this.name,
    required this.share,
    required this.item,
    required this.status,
    required this.remoteAddress,
    this.bytes,
    this.localPath,
    this.archive = false,
  });
  final String name, status, remoteAddress;
  final ShareId share;
  final ItemKey item;
  final int? bytes;
  final String? localPath;
  final bool archive;
}

/// Observes completed server responses, not the receiver's download state.
Future<void> observeShareDownload(
  HttpRequest request, {
  required String name,
  required ShareId share,
  required ItemKey item,
  required Future<void> Function() send,
  ShareDownloadObserver? observer,
  String? localPath,
  bool archive = false,
}) async {
  final remote = request.connectionInfo?.remoteAddress.address ?? '';
  var succeeded = false;
  try {
    await send();
    succeeded = true;
  } finally {
    final response = request.response;
    if (observer != null &&
        request.method == 'GET' &&
        (response.statusCode == HttpStatus.ok ||
            response.statusCode == HttpStatus.partialContent)) {
      try {
        await observer(
          ShareDownloadEvent(
            name: name,
            share: share,
            item: item,
            remoteAddress: remote,
            status: !succeeded
                ? 'failed'
                : response.statusCode == HttpStatus.partialContent
                ? 'partial'
                : 'sent',
            bytes: succeeded && response.contentLength >= 0
                ? response.contentLength
                : null,
            localPath: localPath,
            archive: archive,
          ),
        );
      } on Object {
        // History storage failures must not interrupt the file response.
      }
    }
  }
}
