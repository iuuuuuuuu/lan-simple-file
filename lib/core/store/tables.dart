// SPDX-License-Identifier: GPL-3.0-only

/// drift 表定义：表名与字段名与 docs/plan.md 第 5 节的 DDL 严格一致（snake_case）。
///
/// 全库统一约定：
/// - 时间列存 **毫秒整数（UTC）**，由 [UnixMillisConverter] 双向映射，不存在
///   「一部分存文本、一部分存整数」的混用。
/// - 布尔列存 INTEGER 0/1（drift 布尔列默认行为）。
/// - 大小、字节数、配额一律 INTEGER（i64），全程 int 运算，不降位。
/// - 枚举列存枚举名字符串（textEnum），不用下标，增删枚举项不会让旧数据错位。
library;

import 'package:drift/drift.dart';

import '../contracts/store.dart';
import '../contracts/types.dart';

/// 毫秒整数与 DateTime（UTC）的双向映射。
///
/// 计划第 5 节要求时间「存 ISO8601 UTC 文本或毫秒整数，二选一并全表统一」，
/// 本项目选毫秒整数：SQL 里的排序与比较直接是整数比较，没有格式歧义，
/// 也不受本地时区偏移影响。
final class UnixMillisConverter extends TypeConverter<DateTime, int> {
  const UnixMillisConverter();

  @override
  int toSql(DateTime value) => value.toUtc().millisecondsSinceEpoch;

  @override
  DateTime fromSql(int fromDb) =>
      DateTime.fromMillisecondsSinceEpoch(fromDb, isUtc: true);
}

/// 已知设备。
///
/// DDL: device(peer_id PK, pubkey, alg, name, avatar_hash, os, first_seen,
/// last_seen, online, is_self, is_guest, note)
@DataClassName('DeviceRow')
class Devices extends Table {
  @override
  String get tableName => 'device';

  TextColumn get peerId => text().named('peer_id')();

  /// 裸 Ed25519 公钥（32 字节）。
  BlobColumn get pubkey => blob()();

  /// 签名算法标识；v1 固定 ed25519。
  TextColumn get alg => text().withDefault(const Constant('ed25519'))();

  TextColumn get name => text().withDefault(const Constant(''))();

  TextColumn get avatarHash =>
      text().named('avatar_hash').withDefault(const Constant(''))();

  TextColumn get os => text().withDefault(const Constant(''))();

  IntColumn get firstSeen =>
      integer().named('first_seen').map(const UnixMillisConverter())();

  IntColumn get lastSeen =>
      integer().named('last_seen').map(const UnixMillisConverter())();

  BoolColumn get online => boolean().withDefault(const Constant(false))();

  BoolColumn get isSelf =>
      boolean().named('is_self').withDefault(const Constant(false))();

  BoolColumn get isGuest =>
      boolean().named('is_guest').withDefault(const Constant(false))();

  TextColumn get note => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {peerId};
}

/// 一条分享；含网页会话专用的 session_id 与 is_ephemeral 两列。
///
/// DDL: share(id PK, kind, root_kind, root_uri, display_name, owner_peer_id,
/// created_at, expires_at, mode, password_hash, group_id, max_speed_kbps,
/// enabled, missing, revoked_at, session_id, is_ephemeral)
@DataClassName('ShareRow')
@TableIndex(name: 'idx_share_owner', columns: {#ownerPeerId})
@TableIndex(name: 'idx_share_session', columns: {#sessionId})
class Shares extends Table {
  @override
  String get tableName => 'share';

  TextColumn get id => text()();

  /// folder 或 file。
  TextColumn get kind => text()();

  TextColumn get rootKind => text().named('root_kind')();

  TextColumn get rootUri => text().named('root_uri')();

  TextColumn get displayName => text().named('display_name')();

  TextColumn get ownerPeerId => text().named('owner_peer_id')();

  IntColumn get createdAt =>
      integer().named('created_at').map(const UnixMillisConverter())();

  IntColumn get expiresAt =>
      integer().named('expires_at').map(const UnixMillisConverter()).nullable()();

  TextColumn get mode => textEnum<ShareMode>()();

  TextColumn get passwordHash => text().named('password_hash').nullable()();

  TextColumn get groupId => text().named('group_id').nullable()();

  IntColumn get maxSpeedKbps => integer().named('max_speed_kbps').nullable()();

  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  BoolColumn get missing => boolean().withDefault(const Constant(false))();

  IntColumn get revokedAt =>
      integer().named('revoked_at').map(const UnixMillisConverter()).nullable()();

  /// 网页会话分享绑定的 guest 会话 id。
  TextColumn get sessionId => text().named('session_id').nullable()();

  /// 是否随会话失效：网页会话分享为 true。
  BoolColumn get isEphemeral =>
      boolean().named('is_ephemeral').withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 分享内的一条索引项；复合主键 (share_id, item_key)。
///
/// DDL: share_item(share_id, item_key, rel_path, size, mtime, mime, is_dir,
/// PRIMARY KEY(share_id, item_key))
@DataClassName('ShareItemRow')
class ShareItems extends Table {
  @override
  String get tableName => 'share_item';

  TextColumn get shareId =>
      text().named('share_id').references(Shares, #id, onDelete: KeyAction.cascade)();

  TextColumn get itemKey => text().named('item_key')();

  /// 相对 root 的路径投影，与 itemKey 同源，供按路径前缀查询。
  TextColumn get relPath =>
      text().named('rel_path').withDefault(const Constant(''))();

  IntColumn get size => integer().withDefault(const Constant(0))();

  IntColumn get mtime => integer().map(const UnixMillisConverter()).nullable()();

  TextColumn get mime => text().nullable()();

  BoolColumn get isDir =>
      boolean().named('is_dir').withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {shareId, itemKey};
}

/// 按人授权：谁在什么时间被授权访问某分享。
@DataClassName('GrantRow')
class Grants extends Table {
  @override
  String get tableName => 'grant';

  TextColumn get shareId =>
      text().named('share_id').references(Shares, #id, onDelete: KeyAction.cascade)();

  TextColumn get peerId => text().named('peer_id')();

  IntColumn get grantedAt =>
      integer().named('granted_at').map(const UnixMillisConverter())();

  IntColumn get expiresAt =>
      integer().named('expires_at').map(const UnixMillisConverter()).nullable()();

  @override
  Set<Column> get primaryKey => {shareId, peerId};
}

/// 会话（私聊或群聊）。
@DataClassName('ThreadRow')
class Threads extends Table {
  @override
  String get tableName => 'thread';

  TextColumn get id => text()();

  /// direct 或 group。
  TextColumn get kind => text()();

  TextColumn get title => text().withDefault(const Constant(''))();

  TextColumn get avatarHash =>
      text().named('avatar_hash').withDefault(const Constant(''))();

  TextColumn get peerId => text().named('peer_id').nullable()();

  TextColumn get groupId => text().named('group_id').nullable()();

  TextColumn get lastMsgHlc => text().named('last_msg_hlc').nullable()();

  TextColumn get lastMsgPreview =>
      text().named('last_msg_preview').nullable()();

  IntColumn get unread => integer().withDefault(const Constant(0))();

  BoolColumn get muted => boolean().withDefault(const Constant(false))();

  BoolColumn get pinned => boolean().withDefault(const Constant(false))();

  IntColumn get createdAt =>
      integer().named('created_at').map(const UnixMillisConverter())();

  IntColumn get deletedAt =>
      integer().named('deleted_at').map(const UnixMillisConverter()).nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 群。表名按计划用 grp（group 是 SQL 保留字）。
@DataClassName('GrpRow')
class Grps extends Table {
  @override
  String get tableName => 'grp';

  TextColumn get id => text()();

  TextColumn get name => text().withDefault(const Constant(''))();

  TextColumn get avatarHash =>
      text().named('avatar_hash').withDefault(const Constant(''))();

  TextColumn get ownerPeerId => text().named('owner_peer_id')();

  IntColumn get createdAt =>
      integer().named('created_at').map(const UnixMillisConverter())();

  IntColumn get epoch => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('GroupMemberRow')
class GroupMembers extends Table {
  @override
  String get tableName => 'group_member';

  TextColumn get groupId =>
      text().named('group_id').references(Grps, #id, onDelete: KeyAction.cascade)();

  TextColumn get peerId => text().named('peer_id')();

  TextColumn get role => text().withDefault(const Constant('member'))();

  IntColumn get joinedAt =>
      integer().named('joined_at').map(const UnixMillisConverter())();

  IntColumn get lastSeen =>
      integer().named('last_seen').map(const UnixMillisConverter()).nullable()();

  @override
  Set<Column> get primaryKey => {groupId, peerId};
}

@DataClassName('GroupKeyRow')
class GroupKeys extends Table {
  @override
  String get tableName => 'group_key';

  TextColumn get groupId =>
      text().named('group_id').references(Grps, #id, onDelete: KeyAction.cascade)();

  IntColumn get epoch => integer()();

  TextColumn get wrappedForPeer => text().named('wrapped_for_peer')();

  BlobColumn get wrappedBlob => blob().named('wrapped_blob')();

  @override
  Set<Column> get primaryKey => {groupId, epoch, wrappedForPeer};
}

/// 一条聊天消息。
///
/// DDL: message(id PK, thread_id, sender_peer_id, kind, hlc, ts, body,
/// attach_json, sig, revoked_at, revoke_reason, edited_at)
@DataClassName('MessageRow')
@TableIndex(name: 'idx_message_thread_hlc', columns: {#threadId, #hlc})
class Messages extends Table {
  @override
  String get tableName => 'message';

  TextColumn get id => text()();

  TextColumn get threadId => text().named('thread_id')();

  TextColumn get senderPeerId => text().named('sender_peer_id')();

  TextColumn get kind => textEnum<MessageKind>()();

  /// HLC 的定宽文本形式，见 [zeroPaddedHlc]。
  ///
  /// 定宽的理由：HLC 的字典序只有在毫秒 13 位、计数器 6 位定宽时才等价于
  /// 数值序；否则 9:xxx 会排在 10:xxx 之后。定宽后 ORDER BY hlc 与
  /// Hlc.compareTo 顺序一致，不需要额外排序列。
  TextColumn get hlc => text()();

  IntColumn get ts => integer().map(const UnixMillisConverter())();

  TextColumn get body => text().withDefault(const Constant(''))();

  TextColumn get attachJson =>
      text().named('attach_json').withDefault(const Constant(''))();

  TextColumn get sig => text().withDefault(const Constant(''))();

  IntColumn get revokedAt =>
      integer().named('revoked_at').map(const UnixMillisConverter()).nullable()();

  TextColumn get revokeReason => text().named('revoke_reason').nullable()();

  IntColumn get editedAt =>
      integer().named('edited_at').map(const UnixMillisConverter()).nullable()();

  /// 删除者：群主删他人消息时记录其 peerId；null 表示发送者本人操作。
  /// 与契约 [MessageRecord.deletedBy] 一一对应，必须有真实列，
  /// 不得塞进 revoke_reason（见决策笔记 derived-group-fields-must-hit-storage）。
  TextColumn get deletedBy => text().named('deleted_by').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 消息挂的附件索引：只记位置，不复制文件本体。
@DataClassName('AttachRow')
@TableIndex(name: 'idx_attach_msg', columns: {#msgId})
class Attachments extends Table {
  @override
  String get tableName => 'attach';

  TextColumn get id => text()();

  TextColumn get msgId => text().named('msg_id')();

  TextColumn get shareId => text().named('share_id')();

  TextColumn get ownerPeerId => text().named('owner_peer_id')();

  TextColumn get itemKey => text().named('item_key')();

  TextColumn get name => text().withDefault(const Constant(''))();

  IntColumn get size => integer().withDefault(const Constant(0))();

  TextColumn get mime => text().nullable()();

  BoolColumn get isDir =>
      boolean().named('is_dir').withDefault(const Constant(false))();

  TextColumn get subPath => text().named('sub_path').nullable()();

  TextColumn get localPath => text().named('local_path').nullable()();

  TextColumn get state => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 入站传输的 offer。
@DataClassName('OfferRow')
@TableIndex(name: 'idx_offer_to_status', columns: {#toPeer, #status})
class Offers extends Table {
  @override
  String get tableName => 'offer';

  TextColumn get id => text()();

  TextColumn get fromPeer => text().named('from_peer').nullable()();

  TextColumn get fromSession => text().named('from_session').nullable()();

  /// offer 来源：peer 表示节点，webSession 表示网页访客。
  ///
  /// **与契约 OfferRecord.origin 一一对应**，是一等存储列，不是从
  /// from_peer / from_session 的空值推导出来的。
  /// 推导在「会话撤销后把 from_session 清空」时会静默漂移成 peer，
  /// 这类错误在联调中极难发现，因此这里显式落列。
  ///
  /// 注意：OfferOrigin 声明在 contracts/types.dart（不在 store.dart），
  /// 而本表所在的 library 由 database.dart 承载，故 database.dart 需要
  /// 同时 import 两个契约文件（生成物作为 part 只共享 database.dart 的 import 集）。
  TextColumn get origin => textEnum<OfferOrigin>()();

  TextColumn get toPeer => text().named('to_peer')();

  TextColumn get attachJson =>
      text().named('attach_json').withDefault(const Constant(''))();

  IntColumn get sizeTotal =>
      integer().named('size_total').withDefault(const Constant(0))();

  /// pending / accepted / rejected / expired / cancelled。
  ///
  /// 存文本而非枚举：契约用 OfferStatusWire 值对象表达，且线上字段名已冻结，
  /// 这里保持与线上值域一致，不做二次映射。
  TextColumn get status => text()();

  IntColumn get createdAt =>
      integer().named('created_at').map(const UnixMillisConverter())();

  IntColumn get decidedAt =>
      integer().named('decided_at').map(const UnixMillisConverter()).nullable()();

  TextColumn get note => text().nullable()();

  IntColumn get expireAt =>
      integer().named('expire_at').map(const UnixMillisConverter())();

  @override
  Set<Column> get primaryKey => {id};
}

/// 一条传输任务。
@DataClassName('TransferRow')
@TableIndex(name: 'idx_transfer_status', columns: {#status})
class Transfers extends Table {
  @override
  String get tableName => 'transfer';

  TextColumn get id => text()();

  TextColumn get direction => textEnum<TransferDirection>()();

  TextColumn get peerId => text().named('peer_id')();

  TextColumn get shareId => text().named('share_id')();

  TextColumn get itemKey => text().named('item_key')();

  IntColumn get bytesTotal => integer().named('bytes_total')();

  IntColumn get bytesDone =>
      integer().named('bytes_done').withDefault(const Constant(0))();

  TextColumn get status => textEnum<TransferStatus>()();

  IntColumn get speedBps => integer().named('speed_bps').nullable()();

  IntColumn get createdAt =>
      integer().named('created_at').map(const UnixMillisConverter())();

  IntColumn get finishedAt =>
      integer().named('finished_at').map(const UnixMillisConverter()).nullable()();

  TextColumn get err => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 网页访客会话。
@DataClassName('GuestSessionRow')
@TableIndex(name: 'idx_guest_host', columns: {#hostPeer})
class GuestSessions extends Table {
  @override
  String get tableName => 'guest_session';

  TextColumn get sessionId => text().named('session_id')();

  TextColumn get hostPeer => text().named('host_peer')();

  BlobColumn get pubkey => blob()();

  IntColumn get createdAt =>
      integer().named('created_at').map(const UnixMillisConverter())();

  IntColumn get lastBeat =>
      integer().named('last_beat').map(const UnixMillisConverter())();

  IntColumn get revokedAt =>
      integer().named('revoked_at').map(const UnixMillisConverter()).nullable()();

  IntColumn get quotaBytes =>
      integer().named('quota_bytes').withDefault(const Constant(0))();

  IntColumn get usedBytes =>
      integer().named('used_bytes').withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {sessionId};
}

/// 每个线程我已读到的 HLC，供未读计数使用。
@DataClassName('MsgSeenRow')
class MsgSeens extends Table {
  @override
  String get tableName => 'msg_seen';

  TextColumn get threadId =>
      text().named('thread_id').references(Threads, #id, onDelete: KeyAction.cascade)();

  TextColumn get peerId => text().named('peer_id')();

  /// 定宽 HLC 文本，规则见 [zeroPaddedHlc]。
  TextColumn get lastHlc => text().named('last_hlc')();

  @override
  Set<Column> get primaryKey => {threadId, peerId};
}

@DataClassName('PeerBlockRow')
class PeerBlocks extends Table {
  @override
  String get tableName => 'peer_block';

  TextColumn get peerId => text().named('peer_id')();

  TextColumn get reason => text().withDefault(const Constant(''))();

  IntColumn get until => integer().map(const UnixMillisConverter()).nullable()();

  @override
  Set<Column> get primaryKey => {peerId};
}

/// 键值设置；必须在 close 再 reopen 后依然存在。
@DataClassName('SettingRow')
class Settings extends Table {
  @override
  String get tableName => 'settings';

  TextColumn get key => text()();

  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// 把 Hlc 编码成定宽文本，使 SQL 字典序等价于 HLC 数值序。
///
/// 毫秒固定 13 位（用到 2286 年仍够），计数器固定 6 位。
/// 该文本可被 Hlc.parse 原样解析回来（int.parse 接受前导零）。
String zeroPaddedHlc(Hlc hlc) =>
    '${hlc.millis.toString().padLeft(13, '0')}:'
    '${hlc.counter.toString().padLeft(6, '0')}:'
    '${hlc.origin}';
