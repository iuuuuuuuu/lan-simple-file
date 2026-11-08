// SPDX-License-Identifier: GPL-3.0-only

/// App 组装层：把各模块按契约拼成一个可运行的整体。
///
/// 这是唯一的『接线处』。各模块之间不互相 import，
/// 需要跨模块能力时在这里写适配器。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:lan_simple_file/app/widgets/identicon.dart';
import 'package:lan_simple_file/core/avatars/avatar_store.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/discovery/announce_service_impl.dart';
import 'package:lan_simple_file/core/discovery/discovery_service_impl.dart';
import 'package:lan_simple_file/core/discovery/http_peer_discovery.dart';
import 'package:lan_simple_file/core/discovery/peer_activity_tracker.dart';
import 'package:lan_simple_file/core/discovery/peer_key_bootstrap.dart';
import 'package:lan_simple_file/core/platform/browser_link_policy.dart';
import 'package:lan_simple_file/core/platform/peer_browser_links.dart';
import 'package:lan_simple_file/core/net/peer_local_domain.dart';
import 'package:lan_simple_file/core/net/peer_share_catalog.dart';
import 'package:lan_simple_file/core/files/local_ref_factory.dart';
import 'package:lan_simple_file/core/files/saf_bridge.dart';
import 'package:lan_simple_file/core/files/saf_ref_factory.dart';
import 'package:lan_simple_file/core/groups/group_file_history.dart' as groups;
import 'package:lan_simple_file/core/groups/group_service_impl.dart';
import 'package:lan_simple_file/core/groups/http_group_transport.dart';
import 'package:lan_simple_file/core/messaging/hlc_clock.dart';
import 'package:lan_simple_file/core/identity/capability_codec_impl.dart';
import 'package:lan_simple_file/core/identity/device_identity_impl.dart';
import 'package:lan_simple_file/core/identity/ed25519_signer.dart';
import 'package:lan_simple_file/core/identity/token_revocation_store.dart';
import 'package:lan_simple_file/core/messaging/messaging_service_impl.dart';
import 'package:lan_simple_file/core/messaging/peer_chat_connections.dart';
import 'package:lan_simple_file/core/messaging/ws_server_endpoint.dart';
import 'package:lan_simple_file/core/messaging/ws_peer_auth.dart';
import 'package:lan_simple_file/core/server/api/client_download_api.dart';
import 'package:lan_simple_file/core/net/lan_address.dart';
import 'package:lan_simple_file/core/net/local_domain.dart';
import 'package:lan_simple_file/core/net/lan_address_guard.dart';
import 'package:lan_simple_file/core/server/api/gateway_api.dart';
import 'package:lan_simple_file/core/offers/http_offer_transport.dart';
import 'package:lan_simple_file/core/offers/offer_service_impl.dart';
import 'package:lan_simple_file/core/server/api/guest_api.dart';
import 'package:lan_simple_file/core/server/api/offer_api.dart';
import 'package:lan_simple_file/core/server/api/ping_api.dart';
import 'package:lan_simple_file/core/server/api/profile_api.dart';
import 'package:lan_simple_file/core/server/api/share_api.dart';
import 'package:lan_simple_file/core/server/api/share_catalog_api.dart';
import 'package:lan_simple_file/core/server/api/store_share_source.dart';
import 'package:lan_simple_file/core/server/api/tree_api.dart';
import 'package:lan_simple_file/core/server/api/zip_api.dart';
import 'package:lan_simple_file/core/server/static/flutter_asset_source.dart';
import 'package:lan_simple_file/core/server/static/static_handler.dart';
import 'package:lan_simple_file/core/server/http_server_host.dart';
import 'package:lan_simple_file/core/server/router.dart';
import 'package:lan_simple_file/core/server/response.dart';
import 'package:lan_simple_file/core/shares/share_service_impl.dart' as shares;
import 'package:lan_simple_file/core/transfer/store_target_resolver.dart';
import 'package:lan_simple_file/core/transfer/transfer_service_impl.dart';
import 'package:lan_simple_file/core/webshare/guest_session_registry.dart';
import 'package:lan_simple_file/core/webshare/session_sweeper.dart';
import 'package:lan_simple_file/core/webshare/staging_area.dart';
import 'package:lan_simple_file/core/webshare/web_share_service_impl.dart';
import 'package:lan_simple_file/core/store/store_impl.dart';

/// 由 [LanFileStore] 支撑的公钥查表：凭证验证方靠它自证 issuer。
final class StorePublicKeyLookup implements PublicKeyLookup {
  const StorePublicKeyLookup(this._store);

  final LanFileStore _store;

  @override
  Future<Uint8List?> findPublicKey(PeerId peerId) async {
    final DeviceRecord? record = await _store.findDevice(peerId);
    if (record == null || record.publicKey.isEmpty) {
      return null;
    }
    return record.publicKey;
  }
}

/// 由 [LanFileStore] 支撑的公告落库口子。
///
/// 只接收已验签通过的包。公告里不含公钥，因此公钥沿用库里已存值
/// （由握手或 /api/v1/ping 补齐），避免用空公钥覆盖已有记录。
final class StorePeerUpsertSink implements PeerUpsertSink {
  const StorePeerUpsertSink(this._store, this._self, {this.keyFor});

  final LanFileStore _store;
  final PeerId _self;
  final Uint8List? Function(PeerId)? keyFor;

  @override
  Future<void> upsertVerifiedPeer(AnnouncePacket packet) async {
    if (packet.peerId == _self) {
      return;
    }
    final DeviceRecord? existing = await _store.findDevice(packet.peerId);
    final DateTime seenAt = DateTime.fromMillisecondsSinceEpoch(
      packet.timestamp,
    ).toUtc();
    await _store.upsertDevice(
      DeviceRecord(
        peerId: packet.peerId,
        publicKey: existing?.publicKey.isNotEmpty == true
            ? existing!.publicKey
            : keyFor?.call(packet.peerId) ?? Uint8List(0),
        name: packet.name,
        avatarHash: packet.avatarHash,
        os: packet.operatingSystem ?? existing?.os ?? '',
        firstSeen: existing?.firstSeen ?? seenAt,
        lastSeen: seenAt,
        online: true,
        isSelf: false,
        isGuest: false,
        note: existing?.note ?? '',
      ),
    );
  }
}

/// 把发现层的 peer 活动表适配成共享服务的在线探测。
///
/// 注意 [PeerOnlineProbe] 在 shares 与 groups 两个模块里**各有一份同名接口**，
/// 这是刻意的低耦合（互不 import）；组装层各给一个适配器即可。
final class DiscoveryOnlineProbe implements shares.PeerOnlineProbe {
  const DiscoveryOnlineProbe(this._tracker);

  final PeerActivityTracker _tracker;

  @override
  Future<bool> isOnline(PeerId peerId) async {
    final TrackedPeer? p = _tracker[peerId];
    return p != null && p.liveness == PeerLiveness.online;
  }

  @override
  Future<DateTime?> lastSeen(PeerId peerId) async => _tracker[peerId]?.lastSeen;
}

/// 同上的群组版本适配器。
final class DiscoveryGroupOnlineProbe implements groups.PeerOnlineProbe {
  const DiscoveryGroupOnlineProbe(this._tracker);

  final PeerActivityTracker _tracker;

  @override
  Future<bool> isOnline(PeerId peerId) async {
    final TrackedPeer? p = _tracker[peerId];
    return p != null && p.liveness == PeerLiveness.online;
  }

  @override
  Future<DateTime?> lastSeen(PeerId peerId) async => _tracker[peerId]?.lastSeen;
}

final class StoreGroupLifecycle implements GroupLifecycleDelegate {
  StoreGroupLifecycle(this.service)
    : clock = HlcClock(origin: service.self.value);
  final GroupService service;
  final HlcClock clock;

  @override
  Future<String> createGroup(String name, List<PeerId> members) async {
    final String normalized = normalizeProfileName(name);
    final GroupRecord group = await service.createGroup(
      normalized,
      members: members,
      hlc: clock.next(),
    );
    return group.id;
  }

  @override
  Future<void> leaveGroup(String groupId) =>
      service.leaveGroup(groupId, hlc: clock.next());
}

/// 内置网页的磁盘回退目录。
///
/// 默认 null（真机只走 asset bundle）。测试与开发可设成本地 assets/web 目录，
/// 因为 flutter test 没有 asset bundle —— 不设的话页面路由永远 404。
String? webAssetsFallbackDir;

/// 组装的产物：所有服务都已就绪并互相接通。
final class AppServices {
  const AppServices({
    required this.identity,
    required this.store,
    required this.codec,
    required this.keys,
    required this.revocation,
    required this.profile,
    required this.lanHost,
    required this.announce,
    required this.discovery,
    required this.shares,
    required this.remoteFiles,
    required this.offers,
    required this.messaging,
    required this.webShare,
    required this.server,
    required this.tracker,
    required this.port,
    this.avatars,
    this.groups,
    this.groupTransport,
    this.groupDiscoverySubscription,
    this.sweepTimer,
    this.chatConnections,
    this.localDomain,
    this.localDomainChanges,
    this.browserServer,
    this.browserServerError,
    this.httpDiscovery,
    this.peerBrowserLinks,
    this.browserLinkPolicy = const BrowserLinkPolicy(),
  });

  final DeviceIdentity identity;
  final LanFileStore store;
  final CapabilityCodec codec;
  final PublicKeyLookup keys;

  /// 凭证吊销表：设置页「立即失效所有链接」必须与 codec 同实例，否则点了不生效。
  final TokenRevocationStore revocation;

  /// 本机资料的唯一真相源；改名要写它，ping/profile 接口即时生效。
  final ProfileSource profile;
  final AvatarStore? avatars;
  final GroupService? groups;
  final HttpGroupTransport? groupTransport;
  final StreamSubscription<List<PeerView>>? groupDiscoverySubscription;
  final Timer? sweepTimer;
  final PeerChatConnections? chatConnections;
  final LocalDomainService? localDomain;
  final StreamSubscription<void>? localDomainChanges;
  final HttpServerHost? browserServer;
  final String? browserServerError;
  final HttpPeerDiscovery? httpDiscovery;
  final PeerBrowserLinks? peerBrowserLinks;
  final BrowserLinkPolicy browserLinkPolicy;
  int get browserPort => browserServer?.port ?? port;

  Stream<void> get profileChanges => profile is StoredProfileSource
      ? (profile as StoredProfileSource).changes
      : const Stream<void>.empty();

  Future<void> changeAvatar(Uint8List? bytes) async {
    final AvatarStore? cache = avatars;
    if (cache == null) {
      throw const LanFileException(LanFileErrorCode.unsupported, '头像存储未连接');
    }
    final String hash = bytes == null ? '' : await cache.put(bytes);
    await cache.loadSelf(hash);
    await profile.update(name: profile.name, avatarHash: hash);
  }

  Future<Uint8List?> avatarFor(PeerView peer) async {
    final AvatarStore? cache = avatars;
    if (cache == null || peer.avatarHash.isEmpty) return null;
    final Uint8List? stored = await cache.read(peer.avatarHash);
    if (stored != null) return stored;
    final ({String host, int port})? endpoint = await discovery.findEndpoint(
      peer.peerId,
    );
    if (endpoint == null || !LanAddressGuard.allowsCleartext(endpoint.host)) {
      return null;
    }
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 2);
    try {
      final HttpClientRequest request = await client.getUrl(
        Uri(
          scheme: 'http',
          host: endpoint.host,
          port: endpoint.port,
          path: '/api/v1/avatar/${peer.peerId.value}',
        ),
      );
      request.followRedirects = false;
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 2),
      );
      if (response.statusCode != HttpStatus.ok ||
          response.headers.contentType?.mimeType != 'image/png') {
        return null;
      }
      final BytesBuilder buffer = BytesBuilder(copy: false);
      await for (final List<int> chunk in response.timeout(
        const Duration(seconds: 2),
      )) {
        if (buffer.length + chunk.length > kMaxAvatarBytes) return null;
        buffer.add(chunk);
      }
      final Uint8List bytes = buffer.takeBytes();
      await cache.put(bytes, expectedHash: peer.avatarHash);
      return await cache.read(peer.avatarHash);
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 从本机路径建一条共享（拖入 / 选择文件都走它）。
  ///
  /// 这里必须处理两件真实情况，否则拖入必然失败：
  /// 1. 目录 -> kind=folder；普通文件 -> kind=file；
  /// 2. rootUri 保存源的完整路径，displayName 只用于展示与自定义命名。
  Future<ShareRecord> sharePath(String path) async {
    final FileSystemEntityType type = await FileSystemEntity.type(
      path,
      followLinks: true,
    );
    if (type == FileSystemEntityType.notFound) {
      throw LanFileException(LanFileErrorCode.notFound, '路径不存在：$path');
    }
    final bool isDir = type == FileSystemEntityType.directory;
    final String rootUri = p.normalize(p.absolute(path));
    return shares.create(
      CreateShareRequest(
        rootKind: ShareRootKind.localPath,
        rootUri: rootUri,
        displayName: isDir ? _baseName(path) : _baseName(path),
        mode: ShareMode.token,
        kind: isDir ? 'folder' : 'file',
      ),
    );
  }

  static String _baseName(String path) {
    final List<String> parts = path
        .split(RegExp(r'[\\/]'))
        .where((String s) => s.isNotEmpty)
        .toList();
    return parts.isEmpty ? path : parts.last;
  }

  /// 生成**浏览器可直接打开**的分享链接。
  ///
  /// 与 [ShareService.buildLink] 的 lsf 深链互补：
  /// 深链给装了 App 的设备；本方法给任何有浏览器的设备（手机扫码、发微信、粘浏览器）。
  /// 拿不到本机局域网地址时抛 providerOffline 并给可读原因，
  /// 不返回一个必然打不开的链接。
  Future<Uri> buildWebLink(ShareId id, {String? token}) async {
    final home = await buildWebHomeLink();
    return home.replace(
      path: '/s/${id.value}',
      queryParameters: token == null || token.isEmpty ? null : {'k': token},
    );
  }

  Future<Uri> buildWebHomeLink() async {
    final domain = localDomain;
    // The sender's proxy must not rewrite the address shared with recipients.
    // Keep attempting the local bypass repair without changing the owned domain.
    await browserLinkPolicy.domainFor(domain?.host);
    if (domain != null && !domain.ready) {
      throw LanFileException(
        LanFileErrorCode.providerOffline,
        domain.error ?? '正在注册本机局域网域名，请稍后重试',
      );
    }
    final String? host = domain?.ip ?? lanHost;
    if (host == null || host.isEmpty) {
      throw const LanFileException(
        LanFileErrorCode.providerOffline,
        '没有检测到局域网地址（可能未连网或只有回环网卡），无法生成网页链接',
      );
    }
    return buildWebHomeUrl(
      host: host,
      port: domain == null ? port : browserPort,
      localDomain: domain?.host,
      // The second listener serves the same routes on the default HTTP port.
    );
  }

  Future<Uri> buildPeerWebLink(PeerId owner, ShareId share) async {
    if (owner == identity.peerId) return buildWebLink(share);
    final endpoint = await discovery.findEndpoint(owner);
    if (endpoint == null) {
      throw const LanFileException(
        LanFileErrorCode.providerOffline,
        '文件提供者已离线',
      );
    }
    final domain = await fetchPeerLocalDomain(owner, endpoint);
    return buildWebShareUrl(
      host: endpoint.host,
      port: domain?.port ?? endpoint.port,
      shareId: share,
      localDomain: await browserLinkPolicy.domainFor(domain?.host),
    );
  }

  PeerShareClient peerShareClient(PeerId peer) => PeerShareClient(
    peer: peer,
    endpointFor: () async => peer == identity.peerId
        ? (host: '127.0.0.1', port: port)
        : await discovery.findEndpoint(peer),
  );

  Future<Uri> buildPeerWebHomeLink(PeerId peer) async {
    if (peer == identity.peerId) return buildWebHomeLink();
    final endpoint = await discovery.findEndpoint(peer);
    if (endpoint == null) {
      throw const LanFileException(LanFileErrorCode.providerOffline, '对方已离线');
    }
    final domain = await fetchPeerLocalDomain(
      peer,
      endpoint,
      requireIdentity: true,
    );
    return buildWebHomeUrl(
      host: endpoint.host,
      port: domain?.port ?? endpoint.port,
      localDomain: await browserLinkPolicy.domainFor(domain?.host),
    );
  }

  /// 改名：一次写三处，缺一处就会「本地改了、别人看到的还是旧名」。
  ///
  /// 三处分别是：store（持久化，重启后仍在）、profile（/api/v1/ping 与 profile 接口）、
  /// peers 表里的本机记录（「附近的人」列表里自己的名字）。
  Future<void> renameSelf(String newName) async {
    if (profile is StoredProfileSource) {
      await profile.update(name: newName, avatarHash: profile.avatarHash);
      return;
    }
    final String trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw const LanFileException(LanFileErrorCode.invalidArgument, '昵称不能为空');
    }
    await store.setSetting('profile.name', trimmed);
    await profile.update(name: trimmed, avatarHash: profile.avatarHash);
    final DeviceRecord? self = await store.findDevice(identity.peerId);
    if (self != null) {
      await store.upsertDevice(
        DeviceRecord(
          peerId: self.peerId,
          publicKey: self.publicKey,
          name: trimmed,
          avatarHash: self.avatarHash,
          os: self.os,
          firstSeen: self.firstSeen,
          lastSeen: DateTime.now().toUtc(),
          online: self.online,
          isSelf: self.isSelf,
          isGuest: self.isGuest,
          note: self.note,
        ),
      );
    }
  }

  /// 本机在局域网内的可达地址；null 表示没检测到（无网卡 / 只有回环）。
  ///
  /// 网页链接靠它拼 host：没有它就只能给 lsf 深链，
  /// 而用户要的是「浏览器能直接打开」的链接。
  final String? lanHost;

  final AnnounceService announce;
  final DiscoveryServiceImpl discovery;
  final ShareService shares;

  /// 远端取件：从别的节点按 shareId 下载（局域网内）。
  final TransferServiceImpl remoteFiles;

  /// 双向传输：别人主动发给我 / 我发给别人。
  final OfferServiceImpl offers;
  final MessagingServiceImpl messaging;
  final WebShareServiceImpl webShare;
  final HttpServerHost server;
  final PeerActivityTracker tracker;

  /// 实际监听端口（可能因占用而顺延）。
  final int port;

  Future<void> stop() async {
    await peerBrowserLinks?.dispose();
    await httpDiscovery?.dispose();
    await browserServer?.stop();
    await localDomainChanges?.cancel();
    await localDomain?.stop();
    sweepTimer?.cancel();
    await groupDiscoverySubscription?.cancel();
    await chatConnections?.dispose();
    await groupTransport?.dispose();
    await discovery.dispose();
    await announce.stop();
    await offers.dispose();
    await messaging.dispose();
    await webShare.dispose();
    await server.stop();
    if (profile is StoredProfileSource) {
      await (profile as StoredProfileSource).dispose();
    }
    await store.close();
  }
}

/// 组装入口。
final class AppAssembler {
  const AppAssembler._();

  static Future<AppServices> assemble({
    required Directory dataDir,
    int? udpPortOverride,
    int? httpPortOverride,
    String name = '本机',
    bool enableDiscovery = true,
    bool enableLocalDomains = false,
    int browserPort = 80,
    bool? enableWindowsClientDownload,
  }) async {
    // 1) 身份：首次启动生成，之后复用；损坏时抛错而不是静默重建。
    final DeviceIdentityImpl identity = await DeviceIdentityImpl.loadOrCreate(
      dataDir: dataDir,
    );

    // 2) 存储：真实文件，重启后数据仍在。
    final Directory storeDir = Directory(
      '${dataDir.path}${Platform.pathSeparator}db',
    )..createSync(recursive: true);
    final LanFileStoreImpl store = await LanFileStoreImpl.open(
      dbFile: File('${storeDir.path}${Platform.pathSeparator}app.sqlite'),
    );
    final DateTime now = DateTime.now().toUtc();
    // 昵称优先级：store 里已保存的（用户改过的）> 首次启动的默认值（登录账户名）。
    // 不这么做的话，用户改完名字重启会被默认值覆盖回去。
    final String? savedName = await store.getSetting('profile.name');
    final String effectiveName =
        (savedName != null && savedName.trim().isNotEmpty) ? savedName : name;
    final AvatarStore avatars = AvatarStore(store);
    final String savedAvatar =
        await store.getSetting('profile.avatarHash') ?? '';
    await avatars.loadSelf(savedAvatar);
    await store.upsertDevice(
      DeviceRecord(
        peerId: identity.peerId,
        publicKey: identity.publicKey,
        name: effectiveName,
        avatarHash: savedAvatar,
        os: Platform.operatingSystem,
        firstSeen: now,
        lastSeen: now,
        online: true,
        isSelf: true,
        isGuest: false,
        note: '',
      ),
    );
    // 兼容旧版单文件分享（rootUri 是父目录，displayName 是源文件名）。
    if (await store.getSetting('shares.fileRootVersion') != '1') {
      for (final ShareRecord share in await store.listShares(
        owner: identity.peerId,
      )) {
        if (share.rootKind != 'localPath' ||
            share.kind != 'file' ||
            p.basename(share.displayName) != share.displayName ||
            share.displayName == '.' ||
            share.displayName == '..') {
          continue;
        }
        final FileSystemEntityType type = await FileSystemEntity.type(
          share.rootUri,
        );
        if (type == FileSystemEntityType.directory ||
            (type == FileSystemEntityType.notFound &&
                p.basename(share.rootUri) != share.displayName)) {
          await store.upsertShare(
            share.copyWith(rootUri: p.join(share.rootUri, share.displayName)),
          );
        }
      }
      await store.setSetting('shares.fileRootVersion', '1');
    }

    // 2.5) 本机局域网地址：网页链接与公告的 ip 字段都要它。
    //      拿不到就留 null，由 buildWebLink 给出可读提示（不猜地址）。
    final String? lanHost = await pickLanAddress();

    // 3) 凭证：issuer 自证，公钥查表指向 store。
    final PublicKeyLookup keys = StorePublicKeyLookup(store);
    // 吊销表必须是**同一个实例**：设置页的「立即失效所有链接」要吊销它，
    // codec 验签也要读它。内联 new 一个会让按钮点了不生效。
    final TokenRevocationStore revocation = TokenRevocationStore();
    final CapabilityCodec codec = CapabilityCodecImpl(
      issuer: identity,
      revoked: revocation,
      keys: keys,
    );

    // 4) HTTP：先建路由，再起服务，拿到真实端口后回填给发现层。
    final Router router = Router();
    final StoredProfileSource profile = StoredProfileSource(
      store: store,
      peerId: identity.peerId,
      name: effectiveName,
      avatarHash: savedAvatar,
    );
    registerPingRoutes(
      router,
      peerId: identity.peerId,
      nameReader: () => profile.name,
    );
    registerProfileRoutes(router, profile);
    router.get(
      '/api/v1/identity',
      (HttpRequest request) =>
          jsonResponse(request.response, HttpStatus.ok, <String, Object?>{
            'peerId': identity.peerId.value,
            'publicKey': base64Url.encode(identity.publicKey),
          }),
    );
    router.get('/api/v1/avatar/:peerId', (HttpRequest request) async {
      final PeerId? peer = PeerId.tryParse(request.uri.pathSegments.last);
      final DeviceRecord? device = peer == null
          ? null
          : await store.findDevice(peer);
      if (device == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final Uint8List? bytes = await avatars.read(device.avatarHash);
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      if (bytes != null) {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(bytes);
      } else {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(await buildIdenticonPng(device.peerId.value));
      }
      await request.response.close();
    });

    // 网页取件与打包下载：生产版静态资源 + 真实存储支撑的分享来源。
    final windowsClientDownload =
        enableWindowsClientDownload ?? Platform.isWindows;
    final StaticAssetSource assets = FlutterAssetSource(
      fallbackDir: webAssetsFallbackDir,
      windowsClientDownload: windowsClientDownload,
    );
    final StoreShareSource shareSource = StoreShareSource(
      store: store,
      localFactory: const LocalRefFactory(),
      safFactory: SafRefFactory(const SafBridge()),
    );
    registerStaticRoutes(router, StaticHandler(source: assets));
    if (windowsClientDownload) {
      final clientPackage = ClientPackageSource(
        runtime: File(Platform.resolvedExecutable).parent,
      );
      registerClientDownloadRoutes(router, clientPackage.package);
    }
    registerShareRoutes(router, shareSource, templates: assets);
    registerShareCatalogRoutes(
      router,
      source: shareSource,
      listMine: () => store.listShares(owner: identity.peerId),
      owner: identity.peerId,
      nameReader: () => profile.name,
      avatarReader: () => profile.avatarHash,
    );
    registerTreeRoutes(router, shareSource);
    registerZipRoutes(router, shareSource);
    final HttpServerHost server = HttpServerHost(
      router: router,
      preferredPort: httpPortOverride ?? LanFileConstants.httpPort,
    );
    final int port = await server.start();
    HttpServerHost? browserServer;
    String? browserServerError;
    if (enableLocalDomains) {
      final candidate = HttpServerHost(
        router: router,
        preferredPort: browserPort,
        fallbackSpan: 0,
      );
      try {
        await candidate.start();
        browserServer = candidate;
      } on LanFileException {
        browserServerError = '默认网页端口不可用，当前域名链接仍需带端口';
      }
    }
    final LocalDomainService? localDomain = enableLocalDomains
        ? LocalDomainService(
            username: () => profile.name,
            deviceId: identity.peerId.value,
            address: pickLanAddress,
          )
        : null;
    if (localDomain != null) await localDomain.start();
    router.get(
      '/api/v1/local-domain',
      (request) =>
          jsonResponse(request.response, HttpStatus.ok, <String, Object?>{
            'enabled': localDomain != null,
            'peerId': identity.peerId.value,
            'host': localDomain?.host,
            'address': localDomain?.ip,
            'httpPort': browserServer?.port ?? port,
            'httpError': browserServerError,
            'ready': localDomain?.ready ?? false,
            'error': localDomain?.error,
          }),
    );

    // 5) 发现层：端口就绪后广播才有意义。
    final PeerActivityTracker tracker = PeerActivityTracker(
      clock: DateTime.now,
    );
    final AnnounceServiceImpl announce = AnnounceServiceImpl(
      identity: identity,
      serverPort: port,
      shareCountProvider: const ZeroShareCountProvider(),
      name: effectiveName,
      nameReader: () => profile.name,
      avatarHashReader: () => profile.avatarHash,
      operatingSystem: Platform.operatingSystem,
      // 公告里必须带本机地址：之前一直是空串，导致对端「能看到人却
      // 下不了他的文件」（StoreTargetResolver 拿不到 host 就判离线）。
      localIp: lanHost ?? '',
      localIpReader: localDomain == null ? null : () => localDomain.ip ?? '',
      port: udpPortOverride ?? LanFileConstants.udpPort,
    );
    announce.publicKeyLookup = keys;
    final PeerKeyBootstrap bootstrap = PeerKeyBootstrap();
    announce.unknownPeerKeyResolver = bootstrap.resolve;
    announce.peerSink = StorePeerUpsertSink(
      store,
      identity.peerId,
      keyFor: bootstrap.keyFor,
    );
    profile.onChanged = () async {
      await localDomain?.refresh();
      await announce.probe();
      await announce.announceNow();
    };
    if (enableDiscovery) {
      await announce.start();
    }
    String? announcedIp = localDomain?.ip;
    final localDomainChanges = localDomain?.changes.listen((_) {
      if (enableDiscovery &&
          localDomain.ready &&
          localDomain.ip != announcedIp) {
        announcedIp = localDomain.ip;
        unawaited(announce.announceNow());
      }
    });

    // 6) 消息服务：注入 keys + verifier，收侧验签才是真的生效。
    //    不注入的话 messaging 会停留在「能签不能验」的降级态（有 unverifiedInbound 计数）。
    late final DiscoveryServiceImpl discovery;
    final HttpGroupTransport groupTransport = HttpGroupTransport(
      store: store,
      identity: identity,
      endpointFor: (PeerId peer) => discovery.findEndpoint(peer),
      nameReader: () => profile.name,
      avatarHashReader: () => profile.avatarHash,
    );
    await groupTransport.load();
    final GroupService groupService = GroupService(
      store: store,
      self: identity.peerId,
      broadcaster: groupTransport,
    );
    final MessagingServiceImpl messaging = MessagingServiceImpl(
      store: store,
      identity: identity,
      selfName: effectiveName,
      selfAvatarHash: savedAvatar,
      groupDelegate: StoreGroupLifecycle(groupService),
      keys: keys,
      verifier: Ed25519Signer(),
    );
    final chatAuth = WsPeerAuth(
      identity: identity,
      keys: keys,
      verifier: Ed25519Signer(),
    );
    router.get(
      kWsPath,
      (request) => handleWsRequest(
        request,
        messaging.adoptInboundLink,
        localPeerId: identity.peerId,
        localName: profile.name,
        localAvatarHash: profile.avatarHash,
        localCapabilities: WsFrame.all,
        authenticate: chatAuth.authenticate,
      ),
    );

    // 7) 网页会话分享：临时区 + 登记表 + 清扫器，并起一个周期 sweep。
    //    没有这个定时器，心跳超时永远不会被判定，「关页即失效」的兜底路径形同虚设。
    final String webShareRoot =
        '${dataDir.path}${Platform.pathSeparator}temp${Platform.pathSeparator}web-share';
    final StagingArea stagingArea = StagingArea(rootPath: webShareRoot);
    final GuestSessionRegistry guestRegistry = GuestSessionRegistry(
      hostPeer: identity.peerId,
    );
    late final SessionSweeper sweeper = SessionSweeper(
      registry: guestRegistry,
      staging: stagingArea,
      store: store,
    );
    final WebShareServiceImpl webShareService = WebShareServiceImpl(
      registry: guestRegistry,
      staging: stagingArea,
      sweeper: sweeper,
      store: store,
      hostPeer: identity.peerId,
    );
    registerGuestRoutes(router, service: webShareService, templates: assets);
    final Timer sweepTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(sweeper.sweep());
    });

    final httpDiscovery = HttpPeerDiscovery(
      identity: identity,
      announce: announce,
      accept: (packet, key, host, remotePort) async {
        bootstrap.remember(packet.peerId, key);
        await announce.acceptVerifiedPacket(packet);
        tracker.touch(packet);
        discovery.rememberDirectEndpoint(packet.peerId, host, remotePort);
        await discovery.refresh();
      },
    );
    httpDiscovery.register(router);
    // 8) 发现服务：把公告流 + 活动表 + peers 表组合成 UI 可直接消费的列表。
    discovery = DiscoveryServiceImpl(
      announce: announce,
      tracker: tracker,
      identity: identity,
      directProbe: (host, remotePort) async {
        final id = await httpDiscovery.exchange(host, remotePort);
        if (id == null) {
          throw LanFileException(
            LanFileErrorCode.network,
            httpDiscovery.lastError ?? '设备无法连接',
          );
        }
      },
      nameResolver: (PeerId p) async => (await store.findDevice(p))?.name,
      avatarHashReader: (PeerId p) async =>
          (await store.findDevice(p))?.avatarHash,
      osReader: (PeerId p) async => (await store.findDevice(p))?.os,
      shareCountReader: (PeerId p) async {
        final List<ShareRecord> list = await store.listShares(
          owner: p,
          enabledOnly: true,
        );
        return list.length;
      },
    );
    if (enableDiscovery) await discovery.start();
    final chatConnections = PeerChatConnections(
      self: identity.peerId,
      messaging: messaging,
      endpointFor: discovery.findEndpoint,
      nameReader: () => profile.name,
      avatarReader: () => profile.avatarHash,
      headersFor: chatAuth.headers,
    );
    if (enableDiscovery) chatConnections.start(discovery.watchPeers());
    final peerBrowserLinks = enableDiscovery && Platform.isWindows
        ? PeerBrowserLinks(
            self: identity.peerId,
            domainForPeer: (peer) async {
              final endpoint = await discovery.findEndpoint(peer);
              return endpoint == null
                  ? null
                  : fetchPeerLocalDomain(peer, endpoint, requireIdentity: true);
            },
          )
        : null;
    peerBrowserLinks?.start(discovery.watchPeers());
    if (enableDiscovery && Platform.isAndroid && lanHost == '10.0.2.15') {
      httpDiscovery.startHostPolling(
        '10.0.2.2',
        LanFileConstants.httpPort,
        chatConnections.connect,
      );
    }

    router.post(
      HttpGroupTransport.path,
      (HttpRequest request) =>
          groupTransport.receive(request, groupService, () async {
            await messaging.refreshThreads();
            await messaging.syncConnectedPeers();
          }),
    );
    final StreamSubscription<List<PeerView>> groupDiscoverySubscription =
        discovery.watchPeers().listen((_) => unawaited(groupTransport.flush()));

    // 9) 网关：任何节点都能作为入口。/j/ 只发 302，链接里永远不含 IP。
    //    放在 discovery 之后，因为需要它的 PeerEndpointLookup 能力。
    registerGatewayRoutes(
      router,
      GatewayResolver(
        ownShares: shareSource,
        // 归属来自本机 store 里的 share 记录（发现层拉到对端分享时会写入）。
        // 完全没见过就返回 null -> 网关给 410，绝不去猜。
        ownerLookup: shareSource.ownerOf,
        endpoints: discovery,
        selfPeerId: identity.peerId,
        selfPort: null, // 用相对路径，不暴露本机端口
      ),
    );

    // 10) 双向传输：offer 走真实 HTTP 投递，接收侧路由已注册。
    final OfferServiceImpl offerService = OfferServiceImpl(
      store: store,
      identity: identity,
      codec: codec,
      transport: HttpOfferTransport(endpoints: discovery),
    );
    registerOfferRoutes(router, offerService);

    // 11) 远端取件：按 peers 表解析地址，走局域网 HTTP 拉取。
    final TransferServiceImpl remoteFiles = TransferServiceImpl(
      resolver: StoreTargetResolver(endpoints: discovery),
      store: store,
    );

    // 10) 共享服务：在线探测走发现层的活动表。
    final shares.ShareServiceImpl shareService = shares.ShareServiceImpl(
      store: store,
      identity: identity,
      codec: codec,
      localFactory: const LocalRefFactory(),
      safFactory: SafRefFactory(const SafBridge()),
      probe: DiscoveryOnlineProbe(tracker),
    );

    return AppServices(
      identity: identity,
      store: store,
      codec: codec,
      keys: keys,
      revocation: revocation,
      profile: profile,
      lanHost: lanHost,
      announce: announce,
      discovery: discovery,
      shares: shareService,
      remoteFiles: remoteFiles,
      offers: offerService,
      messaging: messaging,
      webShare: webShareService,
      server: server,
      tracker: tracker,
      port: port,
      avatars: avatars,
      groups: groupService,
      groupTransport: groupTransport,
      groupDiscoverySubscription: groupDiscoverySubscription,
      sweepTimer: sweepTimer,
      chatConnections: chatConnections,
      localDomain: localDomain,
      localDomainChanges: localDomainChanges,
      browserServer: browserServer,
      browserServerError: browserServerError,
      httpDiscovery: httpDiscovery,
      peerBrowserLinks: peerBrowserLinks,
    );
  }
}
