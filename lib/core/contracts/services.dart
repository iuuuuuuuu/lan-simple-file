// SPDX-License-Identifier: GPL-3.0-only

/// 用户可见功能契约：本文件是 UI、传输、发现三方的共同边界。
library;

import 'dart:typed_data';

import 'file_ref.dart';
import 'identity.dart';
import 'protocol.dart';
import 'store.dart';
import 'types.dart';

/// 附近的人列表里的一名成员。
final class PeerView {
  const PeerView({
    required this.peerId,
    required this.name,
    required this.avatarHash,
    required this.online,
    required this.shareCount,
    required this.lastSeen,
    this.os,
  });

  final PeerId peerId;
  final String name;
  final String avatarHash;
  final bool online;
  final int shareCount;
  final DateTime lastSeen;
  final String? os;
}

/// 某人名下挂载的一项分享。
final class SharedRootView {
  const SharedRootView({
    required this.share,
    required this.available,
    this.offlineHint,
  });

  final ShareRecord share;

  /// 提供者在线且分享未停用、源未失效时为 true。
  final bool available;

  /// 不可用时给用户的说明；可读文案，不得为空字符串。
  final String? offlineHint;
}

/// 分享内的一个条目，供浏览树使用。
final class TreeEntryView {
  const TreeEntryView({
    required this.itemKey,
    required this.name,
    required this.isDirectory,
    this.size,
    this.modifiedAt,
    this.mime,
  });

  final ItemKey itemKey;
  final String name;
  final bool isDirectory;
  final int? size;
  final DateTime? modifiedAt;
  final String? mime;
}

/// 创建分享的请求。
final class CreateShareRequest {
  const CreateShareRequest({
    required this.rootKind,
    required this.rootUri,
    required this.displayName,
    required this.mode,
    this.expiresAt,
    this.password,
    this.groupId,
    this.maxSpeedKbps,
    this.kind = 'folder',
  });

  final ShareRootKind rootKind;
  final String rootUri;
  final String displayName;
  final ShareMode mode;
  final DateTime? expiresAt;
  final String? password;
  final String? groupId;
  final int? maxSpeedKbps;
  final String kind;
}

/// 入站 offer 的展示投影。
final class OfferView {
  const OfferView({
    required this.id,
    required this.fromLabel,
    required this.origin,
    required this.files,
    required this.sizeTotal,
    required this.createdAt,
    required this.expireAt,
    required this.status,
    this.note,
  });

  final String id;

  /// 「YG 的台式机」或「网页访客」。
  final String fromLabel;
  final OfferOrigin origin;
  final List<OfferViewFile> files;
  final int sizeTotal;
  final DateTime createdAt;
  final DateTime expireAt;
  final String status;
  final String? note;
}

/// offer 里的一个文件条目。
final class OfferViewFile {
  const OfferViewFile({
    required this.name,
    required this.size,
    this.mime,
  });

  final String name;
  final int size;
  final String? mime;
}

/// 传输进度快照。
final class TransferProgress {
  const TransferProgress({
    required this.transferId,
    required this.bytesDone,
    required this.bytesTotal,
    required this.status,
    this.speedBps,
  });

  final String transferId;
  final int bytesDone;
  final int bytesTotal;
  final TransferStatus status;
  final int? speedBps;

  double get ratio => bytesTotal <= 0 ? 0 : bytesDone / bytesTotal;
}

/// 分享服务：创建、列举、停止、重新定位。
abstract interface class ShareService {
  Future<ShareRecord> create(CreateShareRequest request);

  Future<List<ShareRecord>> listMine();

  Future<void> stop(ShareId id);

  Future<void> rename(ShareId id, String name);

  Future<void> relocate(ShareId id, String newRootUri);

  /// 生成分享链接，不含任何网络地址。
  Future<Uri> buildLink(ShareId id, {CapabilityGrant? grant});

  /// 列出某人名下的分享，含可用性判定。
  Future<List<SharedRootView>> listPeerShares(PeerId peer);

  /// 浏览某分享下的目录；[cursor] 分页。
  Future<({List<TreeEntryView> entries, String? nextCursor})> browse(
    ShareId id, {
    ItemKey? path,
    String? cursor,
    int limit,
  });
}

/// 发现服务：附近的人。
abstract interface class DiscoveryService {
  /// 当前已知的所有人，自己排在首位。
  Stream<List<PeerView>> watchPeers();

  /// 立即刷新一轮（广播探测 + 可选的网段扫描）。
  Future<void> refresh({bool sweep});

  /// 手动添加一个地址。
  Future<void> addByAddress(String host, int port);
}

/// 传输服务：下载、上传、暂停、取消、续传。
abstract interface class TransferService {
  Stream<TransferProgress> watchAll();

  Future<TransferRecord> download({
    required PeerId peer,
    required ShareId share,
    required ItemKey itemKey,
    required String targetDir,
  });

  Future<void> pause(String transferId);

  Future<void> cancel(String transferId);

  /// 对已存在的 .part 继续。
  Future<TransferRecord> resume(String transferId);
}

/// offer 服务：入站请求的接受与拒绝。
abstract interface class OfferService {
  Stream<List<OfferView>> watchIncoming();

  /// 发起方：把文件发给 [toPeer]。
  Future<String> propose({
    required PeerId toPeer,
    required List<String> localPaths,
    String? note,
  });

  /// 接收方：接受，返回可下载的临时分享。
  Future<ShareRecord> accept(String offerId);

  Future<void> reject(String offerId, {String? reason});
}

/// 会话服务：私聊与群聊。
abstract interface class MessagingService {
  Stream<List<ThreadRecord>> watchThreads();

  Stream<List<MessageRecord>> watchMessages(String threadId);

  Future<void> sendText(String threadId, String text);

  Future<void> sendFile(String threadId, ShareId share, {ItemKey? itemKey});

  Future<void> revoke(String messageId, {String? reason});

  Future<void> deleteLocal(String messageId);

  Future<void> deleteThread(String threadId);

  Future<String> createGroup(String name, List<PeerId> members);

  Future<void> leaveGroup(String groupId);
}

/// 头像服务：identicon 生成与自定义头像缓存。
abstract interface class AvatarService {
  /// 未设置自定义头像时，按 peerId 生成稳定 identicon。
  Future<Uint8List> identiconSvg(PeerId peerId, {required bool dark});

  /// 本地已缓存的头像字节；没有则 null。
  Future<Uint8List?> cachedAvatar(AvatarHash hash);
}
/// 网络层可用的本机上下文：其它模块通过它拿到端口、身份与公告能力。
///
/// 由 App 组装后注入，禁止各模块自行读取全局单例。
final class RuntimeContext {
  const RuntimeContext({
    required this.identity,
    required this.serverPort,
    required this.store,
    required this.codec,
    required this.keys,
  });

  final DeviceIdentity identity;

  /// 实际监听端口（可能因占用而顺延，不恒等于 47870）。
  final int serverPort;
  final LanFileStore store;
  final CapabilityCodec codec;
  final PublicKeyLookup keys;
}

/// 验签通过的公告落库口子。
///
/// 发现的产物必须能进 peers 表，否则「附近的人」永远空着。
/// 实现方由 App 组装层用 `LanFileStore.upsertDevice` 实现，发现层不得直接依赖 store。
abstract interface class PeerUpsertSink {
  /// 只接收**已验签通过**的公告；未验签的包绝不允许流到这里。
  Future<void> upsertVerifiedPeer(AnnouncePacket packet);
}

/// 被丢弃数据报的计数，用于诊断「为什么一个邻居也看不见」。
///
/// 不提供这个窗口，网络问题只能表现为「空列表」，无法区分是没广播、
/// 验签全失败、还是端口被占。
abstract interface class RejectedDatagramCounter {
  int get badSignature;

  int get malformed;

  int get fromSelf;

  int get unknownPeerId;

  /// 最近若干条丢弃原因的可读描述，供设置页展示。
  List<String> get recentReasons;
}

/// 公告收发：把本机状态广播出去，同时收集别人的公告。
abstract interface class AnnounceService {
  /// 启动广播/组播循环；幂等。
  Future<void> start();

  Future<void> stop();

  /// 当前公告载荷。
  ///
  /// **返回值允许未签名**（`signature` 为空串）：UI 预览"我看起来是什么样"不需要签名，
  /// 而 Ed25519 签名只能是异步的。真正上线的包一律走 [buildSignedPacket]。
  AnnouncePacket buildPacket();

  /// 真正广播出去的签名版公告。
  Future<AnnouncePacket> buildSignedPacket();

  /// 收到的公告流，已验签、已过滤自己的。
  Stream<AnnouncePacket> watchIncoming();

  /// 主动向局域网发一次探测，请求所有人立即回包。
  Future<void> probe();

  /// 验签通过的公告落库口子；未接线时为 no-op，不得假装写入。
  set peerSink(PeerUpsertSink? sink);

  /// 验签所需的公钥来源；未接线时**所有公告都会验签失败并被丢弃**，
  /// 这是刻意的安全默认。
  set publicKeyLookup(PublicKeyLookup? lookup);

  /// 丢弃计数窗口。
  RejectedDatagramCounter get rejected;

  /// 端口被占等原因降级为「只发不收」时非 null。
  String? get degradedReason;

  /// 当前是否只能发不能收。
  bool get isSendOnly;
}

/// 网页端会话分享服务（M6）。
abstract interface class WebShareService {
  /// 浏览器握手换取 guest 凭证。
  Future<String> openSession({required String clientPubkey});

  /// 心跳；返回 false 表示会话已不存在。
  Future<bool> heartbeat(String sessionId);

  /// 显式撤销会话及其全部临时分享。
  Future<void> revokeSession(String sessionId);

  /// 处理入站上传：把字节写进临时区并登记为临时 share。
  Future<ShareRecord> acceptUpload(
    String sessionId,
    OfferView offer,
    FileRef stagingRoot,
  );
}
