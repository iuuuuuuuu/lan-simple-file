// SPDX-License-Identifier: GPL-3.0-only

/// LanFileStore 的 drift 落地：契约里的每个方法都在这里实现，无 UnimplementedError。
///
/// 三条贯穿全文件的约定：
/// 1. **写操作一律 upsert**：重复写同一份数据不抛异常，也不产生第二行。
/// 2. **不吞异常**：数据库层的 SqliteException 原样上抛，由调用方决定语义。
/// 3. **时间统一 UTC 毫秒**：进来先 toUtc，出去 fromMillisecondsSinceEpoch(isUtc: true)，
///    读写两侧都不依赖本地时区。
library;

import 'dart:io';

import 'package:drift/drift.dart';

import '../contracts/store.dart';
import '../contracts/types.dart';
import 'database.dart';
import 'database_opener.dart';
import 'tables.dart';

/// [LanFileStore] 的 drift 实现。
///
/// 只经由契约类型进出，外部模块不接触 drift 生成物。
final class LanFileStoreImpl implements LanFileStore {
  LanFileStoreImpl._(AppDatabase database) : _db = database;

  /// 打开一个落在真实文件上的库；目录不存在会自动建。
  ///
  /// 不依赖 path_provider：调用方给什么文件就用什么文件，
  /// 因此测试可以直接传临时目录里的路径。
  static Future<LanFileStoreImpl> open({required File dbFile}) async {
    final AppDatabase database = AppDatabase(openExecutor(dbFile));
    // 触发一次真实连接，让建表与 pragma 在这里就完成，
    // 而不是把错误推迟到第一次业务调用。
    await database.customSelect('SELECT 1').getSingle();
    return LanFileStoreImpl._(database);
  }

  final AppDatabase _db;

  @override
  Future<void> init() async {
    await _db.customSelect('SELECT 1').getSingle();
  }

  @override
  Future<void> close() => _db.close();

  // ---------------------------------------------------------------- device

  @override
  Future<void> upsertDevice(DeviceRecord record) {
    return _db.into(_db.devices).insertOnConflictUpdate(
      DevicesCompanion(
        peerId: Value(record.peerId.value),
        pubkey: Value(record.publicKey),
        name: Value(record.name),
        avatarHash: Value(record.avatarHash),
        os: Value(record.os),
        firstSeen: Value(record.firstSeen.toUtc()),
        lastSeen: Value(record.lastSeen.toUtc()),
        online: Value(record.online),
        isSelf: Value(record.isSelf),
        isGuest: Value(record.isGuest),
        note: Value(record.note),
      ),
    );
  }

  @override
  Future<List<DeviceRecord>> listDevices() async {
    final List<DeviceRow> rows =
        await (_db.select(_db.devices)..orderBy([
              (t) => OrderingTerm.desc(t.lastSeen),
              (t) => OrderingTerm.asc(t.peerId),
            ]))
            .get();
    return rows.map(_toDeviceRecord).toList(growable: false);
  }

  @override
  Future<DeviceRecord?> findDevice(PeerId peerId) async {
    final DeviceRow? row = await (_db.select(_db.devices)
          ..where((t) => t.peerId.equals(peerId.value))
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : _toDeviceRecord(row);
  }

  DeviceRecord _toDeviceRecord(DeviceRow row) => DeviceRecord(
        peerId: PeerId.parse(row.peerId),
        publicKey: row.pubkey,
        name: row.name,
        avatarHash: row.avatarHash,
        os: row.os,
        firstSeen: row.firstSeen.toUtc(),
        lastSeen: row.lastSeen.toUtc(),
        online: row.online,
        isSelf: row.isSelf,
        isGuest: row.isGuest,
        note: row.note,
      );

  // ----------------------------------------------------------------- share

  @override
  Future<void> upsertShare(ShareRecord record) {
    return _db.into(_db.shares).insertOnConflictUpdate(
      SharesCompanion(
        id: Value(record.id.value),
        kind: Value(record.kind),
        rootKind: Value(record.rootKind),
        rootUri: Value(record.rootUri),
        displayName: Value(record.displayName),
        ownerPeerId: Value(record.ownerPeerId.value),
        createdAt: Value(record.createdAt.toUtc()),
        expiresAt: Value(record.expiresAt?.toUtc()),
        mode: Value(record.mode),
        passwordHash: Value(record.passwordHash),
        groupId: Value(record.groupId),
        maxSpeedKbps: Value(record.maxSpeedKbps),
        enabled: Value(record.enabled),
        missing: Value(record.missing),
        revokedAt: Value(record.revokedAt?.toUtc()),
        sessionId: Value(record.sessionId),
        isEphemeral: Value(record.isEphemeral),
      ),
    );
  }

  @override
  Future<ShareRecord?> findShare(ShareId id) async {
    final ShareRow? row = await (_db.select(_db.shares)
          ..where((t) => t.id.equals(id.value))
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : _toShareRecord(row);
  }

  @override
  Future<List<ShareRecord>> listShares({
    PeerId? owner,
    bool? enabledOnly,
  }) async {
    final SimpleSelectStatement<$SharesTable, ShareRow> query =
        _db.select(_db.shares);
    if (owner != null) {
      query.where((t) => t.ownerPeerId.equals(owner.value));
    }
    if (enabledOnly != null) {
      query.where((t) => t.enabled.equals(enabledOnly));
    }
    query.orderBy([
      (t) => OrderingTerm.desc(t.createdAt),
      (t) => OrderingTerm.asc(t.id),
    ]);
    final List<ShareRow> rows = await query.get();
    return rows.map(_toShareRecord).toList(growable: false);
  }

  @override
  Future<void> markShareMissing(ShareId id, {required bool missing}) {
    // 幂等：分享不存在时更新 0 行，不抛异常。
    return (_db.update(_db.shares)..where((t) => t.id.equals(id.value)))
        .write(SharesCompanion(missing: Value(missing)));
  }

  @override
  Future<void> revokeShare(ShareId id, {required DateTime at}) {
    // 撤销即视为不可再提供：同时把 enabled 置 false，
    // 否则 listShares(enabledOnly: true) 会把已撤销的分享当成活的。
    return (_db.update(_db.shares)..where((t) => t.id.equals(id.value)))
        .write(SharesCompanion(
      revokedAt: Value(at.toUtc()),
      enabled: const Value<bool>(false),
    ));
  }

  ShareRecord _toShareRecord(ShareRow row) => ShareRecord(
        id: ShareId.parse(row.id),
        kind: row.kind,
        rootKind: row.rootKind,
        rootUri: row.rootUri,
        displayName: row.displayName,
        ownerPeerId: PeerId.parse(row.ownerPeerId),
        createdAt: row.createdAt.toUtc(),
        mode: row.mode,
        enabled: row.enabled,
        missing: row.missing,
        isEphemeral: row.isEphemeral,
        expiresAt: row.expiresAt?.toUtc(),
        passwordHash: row.passwordHash,
        groupId: row.groupId,
        maxSpeedKbps: row.maxSpeedKbps,
        revokedAt: row.revokedAt?.toUtc(),
        sessionId: row.sessionId,
      );

  // ------------------------------------------------------------ share_item

  @override
  Future<void> putItems(List<ShareItemRecord> items) async {
    if (items.isEmpty) return;
    await _db.batch((Batch batch) {
      batch.insertAllOnConflictUpdate(
        _db.shareItems,
        items
            .map((ShareItemRecord item) => ShareItemsCompanion(
                  shareId: Value(item.shareId.value),
                  itemKey: Value(item.itemKey.value),
                  relPath: Value(item.itemKey.value),
                  size: Value(item.size),
                  mtime: Value(item.mtime?.toUtc()),
                  mime: Value(item.mime),
                  isDir: Value(item.isDir),
                ))
            .toList(growable: false),
      );
    });
  }

  @override
  Future<List<ShareItemRecord>> listItems(
    ShareId id, {
    String? prefix,
  }) async {
    final SimpleSelectStatement<$ShareItemsTable, ShareItemRow> query =
        _db.select(_db.shareItems);
    query.where((t) => t.shareId.equals(id.value));
    if (prefix != null && prefix.isNotEmpty) {
      // 用 substr 做精确前缀匹配，不用 LIKE：
      // SQLite 的 LIKE 对 ASCII 默认大小写不敏感，会把 a/b 与 A/B 混在一起。
      // 长度取 rune 数，因为 SQLite 的 substr 按码点计数，而 Dart 的
      // String.length 是 UTF-16 码元数，遇到增补平面字符（emoji）会多算。
      final int prefixRunes = prefix.runes.length;
      query.where((t) => t.itemKey.substr(1, prefixRunes).equals(prefix));
    }
    query.orderBy([(t) => OrderingTerm.asc(t.itemKey)]);
    final List<ShareItemRow> rows = await query.get();
    return rows
        .map((ShareItemRow row) => ShareItemRecord(
              shareId: ShareId.parse(row.shareId),
              itemKey: ItemKey.parse(row.itemKey),
              size: row.size,
              isDir: row.isDir,
              mtime: row.mtime?.toUtc(),
              mime: row.mime,
            ))
        .toList(growable: false);
  }

  // --------------------------------------------------------------- message

  @override
  Future<void> putMessage(MessageRecord record) {
    return _db.into(_db.messages).insertOnConflictUpdate(
      MessagesCompanion(
        id: Value(record.id),
        threadId: Value(record.threadId),
        senderPeerId: Value(record.senderPeerId.value),
        kind: Value(record.kind),
        hlc: Value(zeroPaddedHlc(record.hlc)),
        ts: Value(record.ts.toUtc()),
        body: Value(record.body),
        attachJson: Value(record.attachJson),
        sig: Value(record.sig),
        revokedAt: Value(record.revokedAt?.toUtc()),
        revokeReason: Value(record.revokeReason),
        editedAt: Value(record.editedAt?.toUtc()),
        deletedBy: Value(record.deletedBy?.value),
      ),
    );
  }

  @override
  Future<List<MessageRecord>> listMessages(
    String threadId, {
    Hlc? since,
    int limit = -1,
  }) async {
    // limit <= 0 表示不限制；负值与 0 都不应被当成「要 0 行」，
    // 因为契约里 limit 是位置无关的可选参数，调用方漏传时不该丢数据。
    final int effectiveLimit = limit <= 0 ? -1 : limit;
    final SimpleSelectStatement<$MessagesTable, MessageRow> query =
        _db.select(_db.messages);
    query.where((t) => t.threadId.equals(threadId));
    if (since != null) {
      // HLC 存的是定宽文本，字典序比较等价于 Hlc.compareTo 的数值序。
      query.where((t) => t.hlc.isBiggerThanValue(zeroPaddedHlc(since)));
    }
    query.orderBy([(t) => OrderingTerm.asc(t.hlc)]);
    if (effectiveLimit >= 0) {
      query.limit(effectiveLimit);
    }
    final List<MessageRow> rows = await query.get();
    return rows
        .map((MessageRow row) => MessageRecord(
              id: row.id,
              threadId: row.threadId,
              senderPeerId: PeerId.parse(row.senderPeerId),
              kind: row.kind,
              hlc: Hlc.parse(row.hlc),
              ts: row.ts.toUtc(),
              body: row.body,
              attachJson: row.attachJson,
              sig: row.sig,
              revokedAt: row.revokedAt?.toUtc(),
              revokeReason: row.revokeReason,
              editedAt: row.editedAt?.toUtc(),
              deletedBy:
                  row.deletedBy == null ? null : PeerId.parse(row.deletedBy!),
            ))
        .toList(growable: false);
  }

  @override
  Future<void> revokeMessage(
    String id, {
    required DateTime at,
    String? reason,
  }) {
    // 幂等：消息不存在就是更新 0 行。
    return (_db.update(_db.messages)..where((t) => t.id.equals(id)))
        .write(MessagesCompanion(
      revokedAt: Value(at.toUtc()),
      revokeReason: Value(reason),
    ));
  }

  // ---------------------------------------------------------------- thread

  @override
  Future<void> upsertThread(ThreadRecord record) {
    return _db.into(_db.threads).insertOnConflictUpdate(
      ThreadsCompanion(
        id: Value(record.id),
        kind: Value(record.kind),
        title: Value(record.title),
        avatarHash: Value(record.avatarHash),
        peerId: Value(record.peerId?.value),
        groupId: Value(record.groupId),
        lastMsgHlc: Value(
          record.lastMsgHlc == null ? null : zeroPaddedHlc(record.lastMsgHlc!),
        ),
        lastMsgPreview: Value(record.lastMsgPreview),
        unread: Value(record.unread),
        muted: Value(record.muted),
        pinned: Value(record.pinned),
        createdAt: Value(record.createdAt.toUtc()),
        deletedAt: Value(record.deletedAt?.toUtc()),
      ),
    );
  }

  @override
  Future<List<ThreadRecord>> listThreads() async {
    final List<ThreadRow> rows =
        await (_db.select(_db.threads)..orderBy([
              (t) => OrderingTerm.asc(t.id),
            ]))
            .get();
    return rows
        .map((ThreadRow row) => ThreadRecord(
              id: row.id,
              kind: row.kind,
              title: row.title,
              avatarHash: row.avatarHash,
              unread: row.unread,
              muted: row.muted,
              pinned: row.pinned,
              createdAt: row.createdAt.toUtc(),
              peerId: row.peerId == null ? null : PeerId.parse(row.peerId!),
              groupId: row.groupId,
              lastMsgHlc:
                  row.lastMsgHlc == null ? null : Hlc.parse(row.lastMsgHlc!),
              lastMsgPreview: row.lastMsgPreview,
              deletedAt: row.deletedAt?.toUtc(),
            ))
        .toList(growable: false);
  }

  // ----------------------------------------------------------------- offer

  @override
  Future<void> putOffer(OfferRecord record) {
    return _db.into(_db.offers).insertOnConflictUpdate(
      OffersCompanion(
        id: Value(record.id),
        fromPeer: Value(record.fromPeer?.value),
        fromSession: Value(record.fromSession),
        // origin 是一等列，按契约原样写入。
        origin: Value(record.origin),
        toPeer: Value(record.toPeer.value),
        attachJson: Value(record.filesJson),
        sizeTotal: Value(record.sizeTotal),
        status: Value(record.status.value),
        createdAt: Value(record.createdAt.toUtc()),
        decidedAt: Value(record.decidedAt?.toUtc()),
        note: Value(record.note),
        expireAt: Value(record.expireAt.toUtc()),
      ),
    );
  }

  @override
  Future<OfferRecord?> findOffer(String id) async {
    final OfferRow? row = await (_db.select(_db.offers)
          ..where((t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : _toOfferRecord(row);
  }

  @override
  Future<List<OfferRecord>> listPendingOffers(PeerId toPeer) async {
    final List<OfferRow> rows =
        await (_db.select(_db.offers)
              ..where((t) =>
                  t.toPeer.equals(toPeer.value) &
                  t.status.equals(OfferStatusWire.pending.value))
              ..orderBy([
                (t) => OrderingTerm.asc(t.createdAt),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get();
    return rows.map(_toOfferRecord).toList(growable: false);
  }

  OfferRecord _toOfferRecord(OfferRow row) => OfferRecord(
        id: row.id,
        // 直接读 origin 列，不再从 from_session 推导：
        // 会话撤销后 from_session 可能被清空，推导会静默漂移成 peer。
        origin: row.origin,
        toPeer: PeerId.parse(row.toPeer),
        filesJson: row.attachJson,
        sizeTotal: row.sizeTotal,
        status: OfferStatusWire(row.status),
        createdAt: row.createdAt.toUtc(),
        expireAt: row.expireAt.toUtc(),
        fromPeer: row.fromPeer == null ? null : PeerId.parse(row.fromPeer!),
        fromSession: row.fromSession,
        note: row.note,
        decidedAt: row.decidedAt?.toUtc(),
      );

  // -------------------------------------------------------------- transfer

  @override
  Future<void> putTransfer(TransferRecord record) {
    return _db.into(_db.transfers).insertOnConflictUpdate(
      TransfersCompanion(
        id: Value(record.id),
        direction: Value(record.direction),
        peerId: Value(record.peerId.value),
        shareId: Value(record.shareId.value),
        itemKey: Value(record.itemKey.value),
        bytesTotal: Value(record.bytesTotal),
        bytesDone: Value(record.bytesDone),
        status: Value(record.status),
        speedBps: Value(record.speedBps),
        createdAt: Value(record.createdAt.toUtc()),
        finishedAt: Value(record.finishedAt?.toUtc()),
        err: Value(record.err),
      ),
    );
  }

  @override
  Future<List<TransferRecord>> listTransfers({TransferStatus? status}) async {
    final SimpleSelectStatement<$TransfersTable, TransferRow> query =
        _db.select(_db.transfers);
    if (status != null) {
      // status 是 textEnum 列：生成类型是枚举，比较要用 equalsValue
      // （equals 只接受底层 String，传枚举会被静态拒绝）。
      query.where((t) => t.status.equalsValue(status));
    }
    query.orderBy([
      (t) => OrderingTerm.desc(t.createdAt),
      (t) => OrderingTerm.asc(t.id),
    ]);
    final List<TransferRow> rows = await query.get();
    return rows
        .map((TransferRow row) => TransferRecord(
              id: row.id,
              direction: row.direction,
              peerId: PeerId.parse(row.peerId),
              shareId: ShareId.parse(row.shareId),
              itemKey: ItemKey.parse(row.itemKey),
              bytesTotal: row.bytesTotal,
              bytesDone: row.bytesDone,
              status: row.status,
              createdAt: row.createdAt.toUtc(),
              speedBps: row.speedBps,
              finishedAt: row.finishedAt?.toUtc(),
              err: row.err,
            ))
        .toList(growable: false);
  }

  // --------------------------------------------------------- guest session

  @override
  Future<void> putGuestSession(GuestSessionRecord record) {
    return _db.into(_db.guestSessions).insertOnConflictUpdate(
      GuestSessionsCompanion(
        sessionId: Value(record.sessionId),
        hostPeer: Value(record.hostPeer.value),
        pubkey: Value(record.pubkey),
        createdAt: Value(record.createdAt.toUtc()),
        lastBeat: Value(record.lastBeat.toUtc()),
        revokedAt: Value(record.revokedAt?.toUtc()),
        quotaBytes: Value(record.quotaBytes),
        usedBytes: Value(record.usedBytes),
      ),
    );
  }

  @override
  Future<GuestSessionRecord?> findGuestSession(String sessionId) async {
    final GuestSessionRow? row = await (_db.select(_db.guestSessions)
          ..where((t) => t.sessionId.equals(sessionId))
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;
    return GuestSessionRecord(
      sessionId: row.sessionId,
      hostPeer: PeerId.parse(row.hostPeer),
      pubkey: row.pubkey,
      createdAt: row.createdAt.toUtc(),
      lastBeat: row.lastBeat.toUtc(),
      quotaBytes: row.quotaBytes,
      usedBytes: row.usedBytes,
      revokedAt: row.revokedAt?.toUtc(),
    );
  }

  // ---------------------------------------------------------------- group

  @override
  Future<void> upsertGroup(GroupRecord record) {
    return _db.into(_db.grps).insertOnConflictUpdate(
      GrpsCompanion(
        id: Value(record.id),
        name: Value(record.name),
        avatarHash: Value(record.avatarHash),
        ownerPeerId: Value(record.ownerPeerId.value),
        createdAt: Value(record.createdAt.toUtc()),
        epoch: Value(record.epoch),
      ),
    );
  }

  @override
  Future<GroupRecord?> findGroup(String groupId) async {
    final GrpRow? row = await (_db.select(_db.grps)
          ..where((Grps g) => g.id.equals(groupId))
          ..limit(1))
        .getSingleOrNull();
    if (row == null) {
      return null;
    }
    return _toGroupRecordAsync(row);
  }

  @override
  Future<List<GroupRecord>> listGroups() async {
    final List<GrpRow> rows = await (_db.select(_db.grps)
          ..orderBy(<OrderClauseGenerator<$GrpsTable>>[
            ($GrpsTable g) => OrderingTerm.asc(g.createdAt),
          ]))
        .get();
    final List<GroupRecord> out = <GroupRecord>[];
    for (final GrpRow row in rows) {
      out.add(await _toGroupRecordAsync(row));
    }
    return List<GroupRecord>.unmodifiable(out);
  }

  @override
  Future<void> archiveGroup(String groupId, {required DateTime at}) async {
    // grp 表当前无 archивед 列（见决策笔记 offer-origin-as-real-column 同源问题），
    // 归档时间先落在 settings，键名与 GroupService 约定一致。
    await setSetting('group.archived.$groupId', at.toUtc().toIso8601String());
  }

  @override
  Future<void> putGroupMember(GroupMemberRecord record) {
    return _db.into(_db.groupMembers).insertOnConflictUpdate(
      GroupMembersCompanion(
        groupId: Value(record.groupId),
        peerId: Value(record.peerId.value),
        role: Value(record.role),
        joinedAt: Value(record.joinedAt.toUtc()),
        lastSeen: Value(record.lastSeen?.toUtc()),
      ),
    );
  }

  @override
  Future<List<GroupMemberRecord>> listGroupMembers(String groupId) async {
    final List<GroupMemberRow> rows = await (_db.select(_db.groupMembers)
          ..where((GroupMembers g) => g.groupId.equals(groupId))
          ..orderBy(<OrderClauseGenerator<$GroupMembersTable>>[
            ($GroupMembersTable g) => OrderingTerm.asc(g.joinedAt),
          ]))
        .get();
    return rows
        .map(
          (GroupMemberRow row) => GroupMemberRecord(
            groupId: row.groupId,
            peerId: PeerId.parse(row.peerId),
            role: row.role,
            joinedAt: row.joinedAt.toUtc(),
            lastSeen: row.lastSeen?.toUtc(),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> removeGroupMember(String groupId, PeerId peerId) {
    return (_db.delete(_db.groupMembers)
          ..where(
            (GroupMembers g) =>
                g.groupId.equals(groupId) & g.peerId.equals(peerId.value),
          ))
        .go();
  }

  /// grp 表没有 archived_at 列，归档时间存在 settings 表；
  /// 因此转换是异步的——必须真查一次，不能用内存缓存（reopen 后缓存为空）。
  Future<GroupRecord> _toGroupRecordAsync(GrpRow row) async {
    final String? archivedRaw =
        await getSetting('group.archived.${row.id}');
    return GroupRecord(
      id: row.id,
      name: row.name,
      avatarHash: row.avatarHash,
      ownerPeerId: PeerId.parse(row.ownerPeerId),
      createdAt: row.createdAt.toUtc(),
      epoch: row.epoch,
      archivedAt: archivedRaw == null ? null : DateTime.tryParse(archivedRaw),
    );
  }

  // -------------------------------------------------------------- settings

  @override
  Future<String?> getSetting(String key) async {
    final SettingRow? row = await (_db.select(_db.settings)
          ..where((t) => t.key.equals(key))
          ..limit(1))
        .getSingleOrNull();
    return row?.value;
  }

  @override
  Future<void> setSetting(String key, String value) {
    return _db.into(_db.settings).insertOnConflictUpdate(
      SettingsCompanion(
        key: Value(key),
        value: Value(value),
      ),
    );
  }

  /// 供测试与后续管理页使用的库句柄；业务代码不应绕过契约调用它。
  AppDatabase get database => _db;
}