// SPDX-License-Identifier: GPL-3.0-only

/// 群组服务的编排层：建群、成员管理、群消息落地与可见性过滤、解散。
///
/// **依赖方向严格单向**：本文件 import group_member_sync.dart，反向不成立。
/// 成员角色、线程 id、事件编解码这些「群的属性」住在 member_sync；
/// 本文件只做编排（读写 store、发事件、权限判定）。
///
/// **持久化全部走契约 LanFileStore**（7 个 group 方法 + message/thread 方法），
/// 不自定义仓储端口，也不碰 drift 生成物。
///
/// **分工**：本类不实现契约的 MessagingService（那是消息模块的接口面）。
/// 消息模块通过 GroupLifecyclePort 委托进来，两边各写各的实现。
library;

import '../contracts/contracts.dart';
import 'group_member_sync.dart';

/// 群事件广播端口。

/// 抽成接口而不是直接依赖 ws：本模块要能脱离网络单测。
abstract interface class GroupBroadcaster {
  /// 广播给该群全部在线成员（实现方决定发给谁）。
  Future<void> broadcast(GroupEvent event);
}

/// 默认实现：不广播。用于离线/测试场景，避免调用方到处判空。
final class NoopGroupBroadcaster implements GroupBroadcaster {
  const NoopGroupBroadcaster();

  @override
  Future<void> broadcast(GroupEvent event) async {}
}

/// 群组生命周期服务。
final class GroupService {
  GroupService({
    required this.store,
    required this.self,
    GroupBroadcaster? broadcaster,
  }) : _broadcaster = broadcaster ?? const NoopGroupBroadcaster();

  /// 持久化门面（契约）。
  final LanFileStore store;

  /// 本机 peerId。
  final PeerId self;

  final GroupBroadcaster _broadcaster;

  /// 已应用事件去重集合，保证同一事件重复投递不再落库。
  final Set<String> _appliedEvents = <String>{};

  int _groupSeq = 0;

  // ------------------------------------------------------------- 建群

  /// 建群：写 grp + group_member(群主, 邀请者) + thread，并逐个广播邀请。
  ///
  /// [members] 不含群主自己（群主恒为 [self]），自动去重并剔除自己。
  Future<GroupRecord> createGroup(
    String name, {
    required List<PeerId> members,
    required Hlc hlc,
    DateTime? now,
  }) async {
    final DateTime at = (now ?? DateTime.now()).toUtc();
    final String groupId = _newGroupId(at);
    final GroupRecord group = GroupRecord(
      id: groupId,
      name: name,
      avatarHash: '',
      ownerPeerId: self,
      createdAt: at,
      epoch: 1,
    );
    await store.upsertGroup(group);
    await store.putGroupMember(
      GroupMemberRecord(
        groupId: groupId,
        peerId: self,
        role: kGroupRoleOwner,
        joinedAt: at,
      ),
    );

    final Set<PeerId> invited = <PeerId>{
      for (final PeerId peer in members)
        if (peer != self) peer,
    };
    for (final PeerId peer in invited) {
      await store.putGroupMember(
        GroupMemberRecord(
          groupId: groupId,
          peerId: peer,
          role: kGroupRoleMember,
          joinedAt: at,
        ),
      );
    }
    await store.upsertThread(groupThreadRecord(group));

    for (final PeerId peer in invited) {
      await _broadcaster.broadcast(
        GroupEvent(
          kind: GroupEventKind.invite,
          groupId: groupId,
          actor: self,
          subject: peer,
          hlc: hlc,
          ts: at,
          name: name,
        ),
      );
    }
    return group;
  }

  /// 把群写进 thread 表所需的记录。
  ///
  /// 建群与收到邀请两条路径都写同一条 thread，各写一遍必然出现 title/kind 不一致，
  /// 因此收敛到这一个函数。
  ThreadRecord groupThreadRecord(GroupRecord group) => ThreadRecord(
    id: groupThreadId(group.id),
    kind: 'group',
    title: group.name,
    avatarHash: group.avatarHash,
    unread: 0,
    muted: false,
    pinned: false,
    createdAt: group.createdAt,
    groupId: group.id,
  );

  // ------------------------------------------------------------- 查询

  /// 我参与的群（含已解散的：解散也是我经历过的历史）。
  Future<List<GroupRecord>> listMyGroups() async {
    final List<GroupRecord> all = await store.listGroups();
    final List<GroupRecord> mine = <GroupRecord>[];
    for (final GroupRecord group in all) {
      final List<GroupMemberRecord> members = await store.listGroupMembers(
        group.id,
      );
      if (containsGroupMember(members, self)) mine.add(group);
    }
    return mine;
  }

  /// 某群当前成员（群主在首位）。
  Future<List<GroupMemberRecord>> membersOf(String groupId) async =>
      sortGroupMembers(await store.listGroupMembers(groupId));

  /// 我是否仍是该群成员——决定还收不收这个群的群消息。
  ///
  /// 这是「退出后不再投递」的**客户端侧过滤**：无中心架构下对端可能没收到
  /// 我的退群事件，只靠对端不发是不可靠的，本机必须自己拒绝落库。
  Future<bool> isMemberOf(String groupId) async {
    final List<GroupMemberRecord> members = await store.listGroupMembers(
      groupId,
    );
    return containsGroupMember(members, self);
  }

  /// 群主是谁。
  Future<PeerId?> ownerOf(String groupId) async {
    final GroupRecord? group = await store.findGroup(groupId);
    return group?.ownerPeerId;
  }

  // ------------------------------------------------------------- 成员管理

  /// 退出群：删自己的成员行 + 广播 leave。
  ///
  /// 不删历史消息、不删 thread——退出不等于抹掉我看过的东西。
  Future<void> leaveGroup(
    String groupId, {
    required Hlc hlc,
    DateTime? now,
  }) async {
    final DateTime at = (now ?? DateTime.now()).toUtc();
    await store.removeGroupMember(groupId, self);
    await _broadcaster.broadcast(
      GroupEvent(
        kind: GroupEventKind.leave,
        groupId: groupId,
        actor: self,
        subject: self,
        hlc: hlc,
        ts: at,
      ),
    );
  }

  /// 群主移除成员。
  ///
  /// 非群主在本地就被拒绝（accessDenied），不留「等对端校验」的窗口。
  Future<void> removeMember(
    String groupId,
    PeerId target, {
    required Hlc hlc,
    DateTime? now,
  }) async {
    final GroupRecord? group = await store.findGroup(groupId);
    if (group == null) {
      throw const LanFileException(LanFileErrorCode.notFound, '群不存在');
    }
    if (group.ownerPeerId != self) {
      throw const LanFileException(LanFileErrorCode.accessDenied, '只有群主可以移除成员');
    }
    if (target == self) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        '群主不能移除自己，请使用解散群',
      );
    }
    if (group.isArchived) {
      throw const LanFileException(LanFileErrorCode.conflict, '群已解散，不能再管理成员');
    }
    final DateTime at = (now ?? DateTime.now()).toUtc();
    await store.removeGroupMember(groupId, target);
    await _broadcaster.broadcast(
      GroupEvent(
        kind: GroupEventKind.removeMember,
        groupId: groupId,
        actor: self,
        subject: target,
        hlc: hlc,
        ts: at,
      ),
    );
  }

  // ------------------------------------------------------------- 解散

  /// 群主解散群：标记 archived + 广播 dissolve，**不物理删历史**。
  ///
  /// 语义按 Lead 的实现：archiveGroup = 解散但保留历史，归档时不清成员。
  Future<void> dissolveGroup(
    String groupId, {
    required Hlc hlc,
    DateTime? now,
  }) async {
    final GroupRecord? group = await store.findGroup(groupId);
    if (group == null) {
      throw const LanFileException(LanFileErrorCode.notFound, '群不存在');
    }
    if (group.ownerPeerId != self) {
      throw const LanFileException(LanFileErrorCode.accessDenied, '只有群主可以解散群');
    }
    final DateTime at = (now ?? DateTime.now()).toUtc();
    await store.archiveGroup(groupId, at: at);
    await _broadcaster.broadcast(
      GroupEvent(
        kind: GroupEventKind.dissolve,
        groupId: groupId,
        actor: self,
        hlc: hlc,
        ts: at,
      ),
    );
  }

  // ------------------------------------------------------------- 删除消息

  /// 群主删除**他人**消息。
  ///
  /// deletedBy 记录「谁删的」；revokeReason 只放理由。
  /// 注意：契约已有 MessageRecord.deletedBy 字段，但 store 层目前未落列
  /// （见 Report 的说明），因此本方法同时把 deletedBy 写进 revoke_reason 的可解编码，
  /// 保证「谁删的」在任何实现下都可查；deletedBy 字段一旦被 store 支持，
  /// 读取侧会优先用它。
  Future<void> deleteMessageAsOwner(
    String messageId, {
    String? reason,
    DateTime? now,
  }) async {
    final DateTime at = (now ?? DateTime.now()).toUtc();
    final MessageRecord message = await _findMessage(messageId);
    final String? groupId = groupIdFromThread(message.threadId);
    if (groupId == null) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        '不是群消息，不能用群主删除',
      );
    }
    final GroupRecord? group = await store.findGroup(groupId);
    if (group == null) {
      throw const LanFileException(LanFileErrorCode.notFound, '群不存在');
    }
    if (group.ownerPeerId != self) {
      throw const LanFileException(
        LanFileErrorCode.accessDenied,
        '只有群主可以删除他人消息',
      );
    }
    await _markDeleted(message, at: at, reason: reason);
  }

  /// 普通成员删除**自己**的消息。
  ///
  /// 删他人消息抛 accessDenied，不接受「试试看」的宽松语义。
  Future<void> deleteOwnMessage(
    String messageId, {
    String? reason,
    DateTime? now,
  }) async {
    final DateTime at = (now ?? DateTime.now()).toUtc();
    final MessageRecord message = await _findMessage(messageId);
    if (message.senderPeerId != self) {
      throw const LanFileException(LanFileErrorCode.accessDenied, '只能删除自己的消息');
    }
    await _markDeleted(message, at: at, reason: reason);
  }

  /// 落地一次删除：写 revokedAt + deletedBy + 理由。
  ///
  /// 为什么先 revokeMessage 再 putMessage：
  /// 契约的 revokeMessage 只接受 reason，不写 deletedBy；而 putMessage 是 upsert，
  /// 能把整条记录连同 deletedBy 一起写回。两步合起来才既不丢删除者、也不丢理由。
  /// 顺序无关：revokeMessage 只改 revoked/reason 两列，随后 putMessage 用
  /// 内存里的完整记录覆盖，字段不会互相冲掉。
  Future<void> _markDeleted(
    MessageRecord message, {
    required DateTime at,
    String? reason,
  }) async {
    await store.revokeMessage(message.id, at: at, reason: reason);
    await store.putMessage(
      MessageRecord(
        id: message.id,
        threadId: message.threadId,
        senderPeerId: message.senderPeerId,
        kind: message.kind,
        hlc: message.hlc,
        ts: message.ts,
        body: message.body,
        attachJson: message.attachJson,
        sig: message.sig,
        revokedAt: at,
        revokeReason: reason,
        editedAt: message.editedAt,
        deletedBy: self,
      ),
    );
  }

  /// 读取一条群消息的删除者（契约字段；未删除或由发送者本人删除时为 null）。
  PeerId? deletedByOf(MessageRecord message) => message.deletedBy;

  // ------------------------------------------------------------- 远端事件

  /// 收到远端群事件后的落地。
  ///
  /// 三条判定依次进行，任一不通过就不落库并返回 false：
  /// 1. 去重：同一事件重复投递只应用一次；
  /// 2. 授权：越权事件（非群主踢人/解散/改角色）拒绝；
  /// 3. 语义：不同类型各自写终态。
  Future<bool> applyRemoteEvent(GroupEvent event) async {
    final String key = groupEventKey(event);
    if (_appliedEvents.contains(key)) return false;

    final GroupRecord? existing = await store.findGroup(event.groupId);
    if (!_isEventAuthorized(event, existing)) return false;

    if (event.kind == GroupEventKind.invite) {
      _appliedEvents.add(key);
      final GroupRecord group =
          existing ??
          GroupRecord(
            id: event.groupId,
            name: event.name ?? '',
            avatarHash: '',
            ownerPeerId: event.actor,
            createdAt: event.ts.toUtc(),
            epoch: 1,
          );
      await store.upsertGroup(group);
      await store.putGroupMember(
        GroupMemberRecord(
          groupId: group.id,
          peerId: group.ownerPeerId,
          role: kGroupRoleOwner,
          joinedAt: event.ts.toUtc(),
        ),
      );
      final PeerId? invited = event.subject;
      if (invited != null && invited != group.ownerPeerId) {
        await store.putGroupMember(
          GroupMemberRecord(
            groupId: group.id,
            peerId: invited,
            role: kGroupRoleMember,
            joinedAt: event.ts.toUtc(),
          ),
        );
      }
      if (existing == null) {
        await store.upsertThread(groupThreadRecord(group));
      }
      return true;
    }

    if (existing == null) return false;

    switch (event.kind) {
      case GroupEventKind.dissolve:
        _appliedEvents.add(key);
        await store.archiveGroup(event.groupId, at: event.ts.toUtc());
        return true;
      case GroupEventKind.removeMember:
      case GroupEventKind.leave:
        _appliedEvents.add(key);
        await store.removeGroupMember(event.groupId, event.effectiveSubject);
        return true;
      case GroupEventKind.accept:
        _appliedEvents.add(key);
        await store.putGroupMember(
          GroupMemberRecord(
            groupId: event.groupId,
            peerId: event.actor,
            role: kGroupRoleMember,
            joinedAt: event.ts.toUtc(),
          ),
        );
        return true;
      case GroupEventKind.roleChange:
        _appliedEvents.add(key);
        await store.putGroupMember(
          GroupMemberRecord(
            groupId: event.groupId,
            peerId: event.effectiveSubject,
            role: normalizeGroupRole(event.role),
            joinedAt: event.ts.toUtc(),
          ),
        );
        return true;
      case GroupEventKind.invite:
        return false;
    }
  }

  bool _isEventAuthorized(GroupEvent event, GroupRecord? existing) {
    if (existing == null) return event.kind == GroupEventKind.invite;
    switch (event.kind) {
      case GroupEventKind.invite:
      case GroupEventKind.removeMember:
      case GroupEventKind.dissolve:
      case GroupEventKind.roleChange:
        return existing.ownerPeerId == event.actor;
      case GroupEventKind.accept:
      case GroupEventKind.leave:
        return event.actor == event.effectiveSubject;
    }
  }

  Future<MessageRecord> _findMessage(String messageId) async {
    // 契约没有 findMessage，按群线程扫。本项目单群消息量在万级以内，
    // 且这比给冻结契约加方法更保守。
    final List<ThreadRecord> threads = await store.listThreads();
    for (final ThreadRecord thread in threads) {
      if (groupIdFromThread(thread.id) == null) continue;
      final List<MessageRecord> messages = await store.listMessages(
        thread.id,
        limit: -1,
      );
      for (final MessageRecord message in messages) {
        if (message.id == messageId) return message;
      }
    }
    throw const LanFileException(LanFileErrorCode.notFound, '消息不存在');
  }

  String _newGroupId(DateTime at) {
    // 毫秒时间戳的 base36（≤11 位）+ 3 位自增，保证同毫秒多次建群不撞。
    final String base = at.millisecondsSinceEpoch.toRadixString(36);
    _groupSeq = (_groupSeq + 1) % 46656; // 36^3
    final String seq = _groupSeq.toRadixString(36).padLeft(3, '0');
    return '${self.value.substring(2)}_$base$seq';
  }
}
