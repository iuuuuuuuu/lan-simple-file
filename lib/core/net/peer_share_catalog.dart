// SPDX-License-Identifier: GPL-3.0-only
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../contracts/contracts.dart';
import 'lan_address_guard.dart';

final class PeerShareEntry {
  const PeerShareEntry({
    required this.name,
    required this.isDirectory,
    required this.access,
    this.id,
  });

  final String name;
  final bool isDirectory;
  final String access;
  final ShareId? id;
}

final class PeerShareCatalog {
  const PeerShareCatalog({required this.name, required this.shares});
  final String name;
  final List<PeerShareEntry> shares;
}

/// Uses the same public catalog and access controls as the peer's home page.
final class PeerShareClient {
  PeerShareClient({required this.peer, required this.endpointFor});

  final PeerId peer;
  final Future<({String host, int port})?> Function() endpointFor;
  final Set<HttpClient> _requests = {};
  bool _closed = false;

  void close() {
    _closed = true;
    for (final client in _requests) {
      client.close(force: true);
    }
  }

  Future<PeerShareCatalog> catalog() async {
    final data = await _get('/api/v1/shared-roots');
    if (data['owner'] is! Map || data['owner']['peerId'] != peer.value) {
      throw const LanFileException(
        LanFileErrorCode.conflict,
        '设备 ID 不匹配，请刷新附近的人后重试',
      );
    }
    final shares = <PeerShareEntry>[];
    for (final raw in data['shares'] as List) {
      final row = raw as Map<String, dynamic>;
      ShareId? id;
      if (row['access'] == 'browse' && row['href'] is String) {
        final href = row['href'] as String;
        final match = RegExp(r'^/s/([A-Za-z0-9_-]+)$').firstMatch(href);
        id = match == null ? null : ShareId.tryParse(match.group(1)!);
        if (id == null) {
          throw const LanFileException(
            LanFileErrorCode.network,
            '对方返回了无效的分享地址',
          );
        }
      }
      shares.add(
        PeerShareEntry(
          name: row['name'] as String,
          isDirectory: row['kind'] == 'folder',
          access: row['access'] as String,
          id: id,
        ),
      );
    }
    return PeerShareCatalog(
      name: data['owner']['name'] as String,
      shares: shares,
    );
  }

  Future<FileEntryPage> browse(
    ShareId share, {
    ItemKey? path,
    String? cursor,
  }) async {
    final data = await _get('/s/${share.value}/tree', {
      if (path != null) 'path': path.value,
      'cursor': ?cursor,
      'limit': '100',
    });
    return FileEntryPage(
      entries: [
        for (final row in data['entries'] as List)
          FileEntry(
            itemKey: ItemKey.parse(row['key'] as String),
            name: row['name'] as String,
            kind: row['isDir'] == true ? EntryKind.directory : EntryKind.file,
            size: row['size'] as int?,
            modifiedAt: row['modifiedAt'] == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(row['modifiedAt'] as int),
            mime: row['mime'] as String?,
          ),
      ],
      nextCursor: data['nextCursor'] as String?,
    );
  }

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String>? query,
  ]) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3)
      ..findProxy = (_) => 'DIRECT';
    _requests.add(client);
    Future<Map<String, dynamic>> read() async {
      final endpoint = await endpointFor();
      if (_closed) {
        throw const LanFileException(LanFileErrorCode.cancelled, '已关闭');
      }
      if (endpoint == null || !LanAddressGuard.allowsCleartext(endpoint.host)) {
        throw const LanFileException(
          LanFileErrorCode.providerOffline,
          '对方已离线，请稍后重试',
        );
      }
      final request = await client.getUrl(
        Uri(
          scheme: 'http',
          host: endpoint.host,
          port: endpoint.port,
          path: path,
          queryParameters: query,
        ),
      );
      request.followRedirects = false;
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw LanFileException(
          LanFileErrorCode.accessDenied,
          switch (response.statusCode) {
            401 || 403 => '该分享需要访问授权',
            404 || 410 => '分享已停止或对方版本暂不支持，请刷新后重试',
            _ => '读取分享失败（HTTP ${response.statusCode}）',
          },
        );
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        if (bytes.length + chunk.length > 2 * 1024 * 1024) {
          throw const LanFileException(LanFileErrorCode.network, '分享列表过大');
        }
        bytes.add(chunk);
      }
      return jsonDecode(utf8.decode(bytes.takeBytes())) as Map<String, dynamic>;
    }

    try {
      return await read().timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw const LanFileException(LanFileErrorCode.network, '连接超时，请刷新重试');
    } on SocketException {
      throw const LanFileException(
        LanFileErrorCode.network,
        '无法连接对方，请确认应用仍在运行',
      );
    } finally {
      _requests.remove(client);
      client.close(force: true);
    }
  }
}
