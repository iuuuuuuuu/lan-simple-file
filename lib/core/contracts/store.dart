// SPDX-License-Identifier: GPL-3.0-only

/// 持久化契约：所有模块经由本文件定义的接口读写，禁止绕过 DAO 直接开库。
library;

import 'dart:typed_data';

import 'types.dart';

/// 一个已知设备。
final class DeviceRecord {
  const DeviceRecord({
    required this.peerId,
    required this.publicKey,
    required this.name,
    required this.avatarHash,
    required this.os,
    required this.firstSeen,
    required this.lastSeen,
    required this.online,
    required this.isSelf,
    required this.isGuest,
    required this.note,
  });

  final PeerId peerId;
  final Uint8List publicKey;
  final String name;
  final String avatarHash;
  final String os;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final bool online;
  final bool isSelf;
  final bool isGuest;
  final String note;
}

/// 分享的模式；顺序即 UI 严格度递增。
enum ShareMode {
  /// 同网段任何持链接者均可读。
  lan,

  /// 必须携带有效能力凭证。
  token,

  /// 口令校验。
  password,

  /// 仅指定 peer 可读。
  people,

  /// 仅群成员可读。
  group,

  /// 一次性 offer 专用，仅接收方可读且用后即撤。
  offer,

  /// 网页会话专用，随会话失效。
  session,
}

/// 一条分享记录。
final class ShareRecord {
  const ShareRecord({
    required this.id,
    required this.kind,
    required this.rootKind,
    required this.rootUri,
    required this.displayName,
    required this.ownerPeerId,
    required this.createdAt,
    required this.mode,
    required this.enabled,
    required this.missing,
    required this.isEphemeral,
    this.expiresAt,
    this.passwordHash,
    this.groupId,
    this.maxSpeedKbps,
    this.revokedAt,
    this.sessionId,
  });

  final ShareId id;

  /// folder 或 file。
  final String kind;
  final String rootKind;
  final String rootUri;
  final String displayName;
  final PeerId ownerPeerId;
  final DateTime createdAt;
  final ShareMode mode;
  final bool enabled;

  /// 源文件已失效（被移动或删除）。
  final bool missing;
  final bool isEphemeral;
  final DateTime? expiresAt;
  final String? passwordHash;
  final String? groupId;
  final int? maxSpeedKbps;
  final DateTime? revokedAt;
  final String? sessionId;

  bool get isRevoked => revokedAt != null;

  ShareRecord copyWith({String? displayName, String? rootUri}) => ShareRecord(
    id: id,
    kind: kind,
    rootKind: rootKind,
    rootUri: rootUri ?? this.rootUri,
    displayName: displayName ?? this.displayName,
    ownerPeerId: ownerPeerId,
    createdAt: createdAt,
    mode: mode,
    enabled: enabled,
    missing: missing,
    isEphemeral: isEphemeral,
    expiresAt: expiresAt,
    passwordHash: passwordHash,
    groupId: groupId,
    maxSpeedKbps: maxSpeedKbps,
    revokedAt: revokedAt,
    sessionId: sessionId,
  );
}

/// 分享内的一条索引项。
final class ShareItemRecord {
  const ShareItemRecord({
    required this.shareId,
    required this.itemKey,
    required this.size,
    required this.isDir,
    this.mtime,
    this.mime,
  });

  final ShareId shareId;
  final ItemKey itemKey;
  final int size;
  final bool isDir;
  final DateTime? mtime;
  final String? mime;
}

/// 消息的 kind。
enum MessageKind { text, image, file, system, share }

/// 一条聊天消息。
final class MessageRecord {
  const MessageRecord({
    required this.id,
    required this.threadId,
    required this.senderPeerId,
    required this.kind,
    required this.hlc,
    required this.ts,
    required this.body,
    required this.attachJson,
    required this.sig,
    this.revokedAt,
    this.revokeReason,
    this.editedAt,
    this.deletedBy,
  });

  final String id;
  final String threadId;
  final PeerId senderPeerId;
  final MessageKind kind;
  final Hlc hlc;
  final DateTime ts;
  final String body;
  final String attachJson;
  final String sig;
  final DateTime? revokedAt;
  final String? revokeReason;
  final DateTime? editedAt;

  /// 该消息被谁删除（群主删他人消息时记录）；为 null 表示由发送者本人操作。
  final PeerId? deletedBy;

  bool get isRevoked => revokedAt != null;
}

/// 会话（私聊或群聊）。
final class ThreadRecord {
  const ThreadRecord({
    required this.id,
    required this.kind,
    required this.title,
    required this.avatarHash,
    required this.unread,
    required this.muted,
    required this.pinned,
    required this.createdAt,
    this.peerId,
    this.groupId,
    this.lastMsgHlc,
    this.lastMsgPreview,
    this.deletedAt,
  });

  final String id;

  /// direct 或 group。
  final String kind;
  final String title;
  final String avatarHash;
  final int unread;
  final bool muted;
  final bool pinned;
  final DateTime createdAt;
  final PeerId? peerId;
  final String? groupId;
  final Hlc? lastMsgHlc;
  final String? lastMsgPreview;
  final DateTime? deletedAt;
}

/// 入站传输的 offer。
final class OfferRecord {
  const OfferRecord({
    required this.id,
    required this.origin,
    required this.toPeer,
    required this.filesJson,
    required this.sizeTotal,
    required this.status,
    required this.createdAt,
    required this.expireAt,
    this.fromPeer,
    this.fromSession,
    this.note,
    this.decidedAt,
  });

  final String id;
  final OfferOrigin origin;
  final PeerId toPeer;
  final String filesJson;
  final int sizeTotal;
  final OfferStatusWire status;
  final DateTime createdAt;
  final DateTime expireAt;
  final PeerId? fromPeer;
  final String? fromSession;
  final String? note;
  final DateTime? decidedAt;
}

/// offer 状态的线上投影，与协议层解耦以避免循环依赖。
final class OfferStatusWire {
  const OfferStatusWire(this.value);

  static const pending = OfferStatusWire('pending');
  static const accepted = OfferStatusWire('accepted');
  static const rejected = OfferStatusWire('rejected');
  static const expired = OfferStatusWire('expired');
  static const cancelled = OfferStatusWire('cancelled');

  final String value;

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      other is OfferStatusWire && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// 传输任务的方向。
enum TransferDirection { download, upload }

/// 传输任务状态。
enum TransferStatus { pending, active, paused, failed, done }

/// 一条传输任务。
final class TransferRecord {
  const TransferRecord({
    required this.id,
    required this.direction,
    required this.peerId,
    required this.shareId,
    required this.itemKey,
    required this.bytesTotal,
    required this.bytesDone,
    required this.status,
    required this.createdAt,
    this.speedBps,
    this.finishedAt,
    this.err,
  });

  final String id;
  final TransferDirection direction;
  final PeerId peerId;
  final ShareId shareId;
  final ItemKey itemKey;
  final int bytesTotal;
  final int bytesDone;
  final TransferStatus status;
  final DateTime createdAt;
  final int? speedBps;
  final DateTime? finishedAt;
  final String? err;
}

/// 网页访客会话。
final class GuestSessionRecord {
  const GuestSessionRecord({
    required this.sessionId,
    required this.hostPeer,
    required this.pubkey,
    required this.createdAt,
    required this.lastBeat,
    required this.quotaBytes,
    required this.usedBytes,
    this.revokedAt,
  });

  final String sessionId;
  final PeerId hostPeer;
  final Uint8List pubkey;
  final DateTime createdAt;
  final DateTime lastBeat;
  final int quotaBytes;
  final int usedBytes;
  final DateTime? revokedAt;
}

/// 群组记录。
final class GroupRecord {
  const GroupRecord({
    required this.id,
    required this.name,
    required this.avatarHash,
    required this.ownerPeerId,
    required this.createdAt,
    required this.epoch,
    this.archivedAt,
  });

  final String id;
  final String name;
  final String avatarHash;
  final PeerId ownerPeerId;
  final DateTime createdAt;

  /// 群密钥世代；v1 明文阶段恒为 1。
  final int epoch;

  /// 解散时间；非空表示已解散但历史保留。
  final DateTime? archivedAt;

  bool get isArchived => archivedAt != null;
}

/// 群成员。
final class GroupMemberRecord {
  const GroupMemberRecord({
    required this.groupId,
    required this.peerId,
    required this.role,
    required this.joinedAt,
    this.lastSeen,
  });

  final String groupId;
  final PeerId peerId;

  /// owner / member。
  final String role;
  final DateTime joinedAt;
  final DateTime? lastSeen;
}

/// 存储门面：模块只依赖本接口，不依赖 drift 生成物。
abstract interface class LanFileStore {
  Future<void> init();

  Future<void> close();

  // device
  Future<void> upsertDevice(DeviceRecord record);

  Future<List<DeviceRecord>> listDevices();

  Future<DeviceRecord?> findDevice(PeerId peerId);

  // share
  Future<void> upsertShare(ShareRecord record);

  Future<ShareRecord?> findShare(ShareId id);

  Future<List<ShareRecord>> listShares({PeerId? owner, bool? enabledOnly});

  Future<void> markShareMissing(ShareId id, {required bool missing});

  Future<void> revokeShare(ShareId id, {required DateTime at});

  // share_item
  Future<void> putItems(List<ShareItemRecord> items);

  Future<List<ShareItemRecord>> listItems(ShareId id, {String? prefix});

  // message
  Future<void> putMessage(MessageRecord record);

  Future<List<MessageRecord>> listMessages(
    String threadId, {
    Hlc? since,
    int limit,
  });

  Future<void> revokeMessage(String id, {required DateTime at, String? reason});

  // thread
  Future<void> upsertThread(ThreadRecord record);

  Future<List<ThreadRecord>> listThreads();

  // offer
  Future<void> putOffer(OfferRecord record);

  Future<OfferRecord?> findOffer(String id);

  Future<List<OfferRecord>> listPendingOffers(PeerId toPeer);

  // transfer
  Future<void> putTransfer(TransferRecord record);

  Future<List<TransferRecord>> listTransfers({TransferStatus? status});

  // guest session
  Future<void> putGuestSession(GuestSessionRecord record);

  Future<GuestSessionRecord?> findGuestSession(String sessionId);

  // group
  Future<void> upsertGroup(GroupRecord record);

  Future<GroupRecord?> findGroup(String groupId);

  Future<List<GroupRecord>> listGroups();

  Future<void> archiveGroup(String groupId, {required DateTime at});

  Future<void> putGroupMember(GroupMemberRecord record);

  Future<List<GroupMemberRecord>> listGroupMembers(String groupId);

  Future<void> removeGroupMember(String groupId, PeerId peerId);

  // settings
  Future<String?> getSetting(String key);

  Future<void> setSetting(String key, String value);
}
