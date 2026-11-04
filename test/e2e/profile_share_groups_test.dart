// SPDX-License-Identifier: GPL-3.0-only

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/assembly.dart';
import 'package:lan_simple_file/core/contacts/peer_groups.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/discovery/announce_codec.dart';
import 'package:lan_simple_file/core/discovery/announce_service_impl.dart';
import 'package:lan_simple_file/core/groups/http_group_transport.dart';
import 'package:lan_simple_file/core/server/api/store_share_source.dart';
import 'package:lan_simple_file/core/files/local_ref_factory.dart';

final Uint8List avatarPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGM4sdDoPwAGawKb0aSw4gAAAABJRU5ErkJggg==',
);

Future<({int status, Uint8List body, String? mime})> request(
  AppServices services,
  String path, {
  Object? json,
}) async {
  final HttpClient client = HttpClient();
  try {
    final Uri uri = Uri.parse('http://127.0.0.1:${services.port}$path');
    final HttpClientRequest req = json == null
        ? await client.getUrl(uri)
        : await client.postUrl(uri);
    if (json != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(json));
    }
    final HttpClientResponse res = await req.close();
    final BytesBuilder bytes = BytesBuilder(copy: false);
    await for (final List<int> chunk in res) {
      bytes.add(chunk);
    }
    return (
      status: res.statusCode,
      body: bytes.takeBytes(),
      mime: res.headers.contentType?.mimeType,
    );
  } finally {
    client.close(force: true);
  }
}

Future<AnnouncePacket> packetOf(AppServices services, {String? name}) async {
  final AnnouncePacket packet = AnnouncePacket(
    version: LanFileConstants.protocolVersion,
    peerId: services.identity.peerId,
    name: name ?? services.profile.name,
    avatarHash: services.profile.avatarHash,
    port: services.port,
    ip: '127.0.0.1',
    shareCount: 0,
    capabilities: const <String>{},
    mode: 'idle',
    timestamp: DateTime.now().millisecondsSinceEpoch,
    signature: '',
  );
  return packet.withSignature(
    base64Url.encode(
      await services.identity.sign(Uint8List.fromList(packet.signableBytes())),
    ),
  );
}

void main() {
  late Directory temporary;
  final List<AppServices> running = <AppServices>[];
  String? oldFallback;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('lsf_requested_features_');
    oldFallback = webAssetsFallbackDir;
    webAssetsFallbackDir = 'assets/web';
  });
  tearDown(() async {
    for (final AppServices services in running.reversed) {
      await services.stop();
    }
    running.clear();
    webAssetsFallbackDir = oldFallback;
    if (temporary.existsSync()) temporary.deleteSync(recursive: true);
  });
  Future<AppServices> boot(String suffix, {bool discovery = false}) async {
    int udpPort = 0;
    if (discovery) {
      final RawDatagramSocket reserve = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
      );
      udpPort = reserve.port;
      reserve.close();
    }
    final AppServices services = await AppAssembler.assemble(
      dataDir: Directory('${temporary.path}/$suffix'),
      httpPortOverride: 0,
      udpPortOverride: udpPort,
      enableDiscovery: discovery,
      name: '测试$suffix',
    );
    running.add(services);
    return services;
  }

  Future<void> restartStop(AppServices services) async {
    running.remove(services);
    await services.stop();
  }

  test('单文件改名保持真实路径和内容，只暴露这一个文件，重启后仍可下载', () async {
    final File file = File('${temporary.path}/照片.jpg')
      ..writeAsBytesSync(<int>[1, 2, 3, 4, 5]);
    File('${temporary.path}/private.txt').writeAsStringSync('不应分享');
    AppServices services = await boot('single');
    final ShareRecord share = await services.sharePath(file.path);
    await services.shares.rename(share.id, '旅行照片');
    ShareRecord saved = (await services.store.findShare(share.id))!;
    expect(saved.rootUri, file.path.replaceAll('/', Platform.pathSeparator));
    expect(saved.displayName, '旅行照片');
    expect(saved.id, share.id);
    final page = await services.shares.browse(share.id);
    expect(page.entries.single.name, '照片.jpg');
    expect(page.entries.single.isDirectory, isFalse);

    final tree = await request(services, '/s/${share.id.value}/tree');
    expect(tree.status, 200);
    final Map<String, dynamic> body = jsonDecode(utf8.decode(tree.body));
    expect((body['entries'] as List).single['name'], '照片.jpg');
    final downloaded = await request(
      services,
      '/s/${share.id.value}/f/${Uri.encodeComponent('照片.jpg')}',
    );
    expect(downloaded.status, 200);
    expect(downloaded.body, <int>[1, 2, 3, 4, 5]);
    expect(
      (await request(services, '/s/${share.id.value}/f/private.txt')).status,
      403,
    );
    final zip = await request(services, '/s/${share.id.value}/zip');
    expect(zip.status, 200);
    final Archive archive = ZipDecoder().decodeBytes(zip.body);
    expect(archive.files.single.name, '照片.jpg');
    expect(archive.files.single.content, <int>[1, 2, 3, 4, 5]);

    await restartStop(services);
    services = await boot('single');
    saved = (await services.store.findShare(share.id))!;
    expect(saved.displayName, '旅行照片');
    expect(saved.rootUri, file.path.replaceAll('/', Platform.pathSeparator));
    expect((await request(services, '/s/${share.id.value}/f/')).body, <int>[
      1,
      2,
      3,
      4,
      5,
    ]);
    expect(await file.exists(), isTrue);
  });

  test('旧版父目录形式迁移为完整路径；异常目录不能作为单文件泄漏', () async {
    final File file = File('${temporary.path}/old.txt')
      ..writeAsStringSync('old');
    AppServices services = await boot('legacy');
    final ShareRecord share = await services.sharePath(file.path);
    await services.store.upsertShare(share.copyWith(rootUri: temporary.path));
    final StoreShareSource source = StoreShareSource(
      store: services.store,
      localFactory: const LocalRefFactory(),
    );
    expect(await source.find(share.id), isNull);
    await services.store.setSetting('shares.fileRootVersion', '0');
    await restartStop(services);
    services = await boot('legacy');
    expect(
      (await services.store.findShare(share.id))!.rootUri,
      file.path.replaceAll('/', Platform.pathSeparator),
    );
    expect((await request(services, '/s/${share.id.value}/f/')).status, 200);
  });

  test('头像/昵称持久化，并出现在公告、网页和真实头像接口中', () async {
    AppServices services = await boot('profile');
    final File file = File('${temporary.path}/document.txt')
      ..writeAsStringSync('hello');
    final ShareRecord share = await services.sharePath(file.path);
    await services.renameSelf('张三 <&"🙂');
    await services.changeAvatar(avatarPng);
    final String hash = services.profile.avatarHash;
    expect(hash, startsWith('sha256:'));
    expect(services.announce.buildPacket().name, '张三 <&"🙂');
    expect(services.announce.buildPacket().avatarHash, hash);
    expect(
      (await services.store.findDevice(services.identity.peerId))!.avatarHash,
      hash,
    );
    final avatar = await request(
      services,
      '/api/v1/avatar/${services.identity.peerId.value}',
    );
    expect(avatar.status, 200);
    expect(avatar.mime, 'image/png');
    expect(avatar.body, orderedEquals(avatarPng));
    final String html = utf8.decode(
      (await request(services, '/s/${share.id.value}')).body,
    );
    expect(html, contains('张三 &lt;&amp;&quot;🙂'));
    expect(html, contains('/api/v1/avatar/${services.identity.peerId.value}'));
    expect(html, isNot(contains('__LSF_SHARE_OWNER')));
    expect(html, isNot(contains('张三 <&"🙂')));
    await restartStop(services);
    services = await boot('profile');
    expect(services.profile.name, '张三 <&"🙂');
    expect(services.profile.avatarHash, hash);
    expect(services.avatars!.selfBytes, orderedEquals(avatarPng));
    await services.changeAvatar(null);
    expect(services.avatars!.selfBytes, isNull);
    expect(services.announce.buildPacket().avatarHash, '');
    expect(
      (await request(
        services,
        '/api/v1/avatar/${services.identity.peerId.value}',
      )).mime,
      'image/svg+xml',
    );
  });

  test('其他节点可按公告哈希获取头像，联系人分组重启后保留', () async {
    final AppServices owner = await boot('avatar-owner');
    AppServices reader = await boot('avatar-reader');
    await owner.changeAvatar(avatarPng);
    final AnnouncePacket packet = await packetOf(owner);
    reader.tracker.touch(packet);
    final Uint8List? avatar = await reader.avatarFor(
      PeerView(
        peerId: owner.identity.peerId,
        name: owner.profile.name,
        avatarHash: owner.profile.avatarHash,
        online: true,
        shareCount: 0,
        lastSeen: DateTime.now(),
      ),
    );
    expect(avatar, orderedEquals(avatarPng));
    await StorePeerGroupsSource(reader.store).save(
      PeerGroups(
        names: const <String, String>{'team': '同事'},
        assignments: <String, String>{owner.identity.peerId.value: 'team'},
      ),
    );
    await restartStop(reader);
    reader = await boot('avatar-reader');
    final PeerGroups groups = await StorePeerGroupsSource(reader.store).load();
    expect(groups.names['team'], '同事');
    expect(groups.groupOf(owner.identity.peerId), 'team');
    expect(
      await reader.avatars!.read(owner.profile.avatarHash),
      orderedEquals(avatarPng),
    );
  });

  test('真实群创建会投递成员名单，离线邀请跨重启重试，篡改签名会被拒绝', () async {
    AppServices owner = await boot('group-owner');
    final AppServices member = await boot('group-member');
    final AppServices offline = await boot('group-offline');
    owner.tracker.touch(await packetOf(member));
    final String id = await owner.messaging.createGroup('项目组', <PeerId>[
      member.identity.peerId,
      offline.identity.peerId,
    ]);
    await owner.groupTransport!.flush();
    await owner.groupTransport!.flush();
    expect((await owner.store.findGroup(id))!.name, '项目组');
    expect((await member.store.findGroup(id))!.name, '项目组');
    expect((await member.store.listGroupMembers(id)).length, 3);
    expect((await member.store.listThreads()).single.id, 'g_$id');
    final Map<String, dynamic> pending = jsonDecode(
      (await owner.store.getSetting('groups.outbox'))!,
    );
    expect(pending, hasLength(1));
    final Map<String, dynamic> envelope = Map<String, dynamic>.from(
      pending.values.single['envelope'] as Map,
    );
    final Map<String, dynamic> payload = jsonDecode(
      envelope['payload'] as String,
    );
    (payload['event'] as Map)['name'] = '伪造群名';
    envelope['payload'] = jsonEncode(payload);
    expect(
      (await request(offline, HttpGroupTransport.path, json: envelope)).status,
      403,
    );
    expect(await offline.store.findGroup(id), isNull);

    await restartStop(owner);
    owner = await boot('group-owner');
    owner.tracker.touch(await packetOf(offline));
    await owner.groupTransport!.flush();
    expect((await offline.store.findGroup(id))!.name, '项目组');
    expect((await offline.store.listGroupMembers(id)).length, 3);
    expect(
      jsonDecode((await owner.store.getSetting('groups.outbox'))!),
      isEmpty,
    );
  });

  test('全新设备通过真实 UDP 公告查询公钥、验签入库，并自动更新昵称', () async {
    final AppServices sender = await boot('discovery-sender', discovery: true);
    final AppServices receiver = await boot(
      'discovery-receiver',
      discovery: true,
    );
    final AnnounceServiceImpl tx = sender.announce as AnnounceServiceImpl;
    final AnnounceServiceImpl rx = receiver.announce as AnnounceServiceImpl;
    Future<void> sendAndWait(String name) async {
      final AnnouncePacket packet = await packetOf(sender, name: name);
      expect(tx.debugSendTo(encodeAnnounceFrame(packet), rx.port), isTrue);
      final DateTime deadline = DateTime.now().add(const Duration(seconds: 4));
      while (DateTime.now().isBefore(deadline)) {
        if (receiver.discovery.currentPeers.any(
          (PeerView peer) =>
              peer.peerId == sender.identity.peerId && peer.name == name,
        )) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      fail('自动发现未更新，丢包原因：${rx.rejected.recentReasons}');
    }

    await sendAndWait('初次出现的陌生人');
    expect(
      (await receiver.store.findDevice(sender.identity.peerId))!.publicKey,
      orderedEquals(sender.identity.publicKey),
    );
    expect(receiver.tracker[sender.identity.peerId], isNotNull);
    await sendAndWait('修改后的昵称');
    final Map<String, Object?> tampered = (await packetOf(
      sender,
      name: '原名',
    )).toJson();
    tampered['name'] = '未验签的名字';
    final int before = rx.rejected.badSignature;
    tx.debugSendTo(
      encodeAnnounceFrame(AnnouncePacket.fromJson(tampered)),
      rx.port,
    );
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 2));
    while (rx.rejected.badSignature == before &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    expect(rx.rejected.badSignature, greaterThan(before));
    expect(
      receiver.discovery.currentPeers
          .firstWhere((PeerView peer) => peer.peerId == sender.identity.peerId)
          .name,
      '修改后的昵称',
    );
  });
}
