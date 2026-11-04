// SPDX-License-Identifier: GPL-3.0-only

/// 群成员关系在多节点间的收敛：角色、事件编解码、成员账本。
///
/// 依赖方向是**单向**的：本文件不 import group_service_impl.dart，
/// 只被它 import。共享的角色/排序辅助放在这里，因为它们是「成员」域的属性，
/// 而不是「服务编排」的细节。
///
/// 无中心架构下没有权威服务器，成员的加入/退出是一组**广播事件**。
/// 幂等与顺序无关性是硬要求：同一批事件以任意顺序到达，最终成员表必须一致。
/// 因此每个事件只写「某 (groupId, peerId) 的终态」，不做 +1/-1 式计数。
library;

import 'dart:convert';

import '../contracts/contracts.dart';

/// 群会话线程 id 的唯一权威：契约要求 g_ + groupId。
///
/// 放在成员域而不是服务域：线程 id 是群的**标识属性**，
/// 服务编排只是它的使用者，据此保持依赖单向（service -> member_sync）。
String groupThreadId(String groupId) => 'g_$groupId';

/// 从线程 id 反解 groupId；不是群线程时返回 null。
String? groupIdFromThread(String threadId) {
  const String prefix = 'g_';
  if (!threadId.startsWith(prefix)) return null;
  final String id = threadId.substring(prefix.length);
  return id.isEmpty ? null : id;
}

/// 群主角色字面量；契约里 role 是 String，不需要额外枚举。
const String kGroupRoleOwner = 'owner';

/// 普通成员角色字面量。
const String kGroupRoleMember = 'member';

/// 归一化角色：契约只认 owner，其余一律按 member。
String normalizeGroupRole(String raw) =>
    raw == kGroupRoleOwner ? kGroupRoleOwner : kGroupRoleMember;

/// 成员是否群主。
bool isGroupOwner(GroupMemberRecord member) =>
    normalizeGroupRole(member.role) == kGroupRoleOwner;

/// 按契约排序成员：群主恒在首位，其余按加入时间升序，最后用 peerId 兜底稳定排序。
List<GroupMemberRecord> sortGroupMembers(List<GroupMemberRecord> raw) {
  final List<GroupMemberRecord> list = List<GroupMemberRecord>.of(raw);
  list.sort((GroupMemberRecord a, GroupMemberRecord b) {
    final bool ao = isGroupOwner(a);
    final bool bo = isGroupOwner(b);
    if (ao != bo) return ao ? -1 : 1;
    final int byTime = a.joinedAt.compareTo(b.joinedAt);
    if (byTime != 0) return byTime;
    return a.peerId.compareTo(b.peerId);
  });
  return list;
}

/// 从群成员表里找群主；没有则返回 null。
GroupMemberRecord? findGroupOwner(List<GroupMemberRecord> members) {
  for (final GroupMemberRecord member in members) {
    if (isGroupOwner(member)) return member;
  }
  return null;
}

/// 成员表里是否含 [peer]。
bool containsGroupMember(List<GroupMemberRecord> members, PeerId peer) {
  for (final GroupMemberRecord member in members) {
    if (member.peerId == peer) return true;
  }
  return false;
}

/// 群事件的类型。
enum GroupEventKind {
  /// 建群：携带初始成员名单。
  invite,

  /// 我接受邀请入群。
  accept,

  /// 主动退出。
  leave,

  /// 群主移除成员。
  removeMember,

  /// 群主解散群。
  dissolve,

  /// 成员角色变更（如转让群主）。
  roleChange,
}

/// 一条群事件。
///
/// [hlc] 是去重与定序依据；[actor] 是发起者，用于权限判定
/// （只有群主能 removeMember / dissolve / roleChange）。
final class GroupEvent {
  const GroupEvent({
    required this.kind,
    required this.groupId,
    required this.actor,
    required this.hlc,
    required this.ts,
    this.subject,
    this.name,
    this.role = kGroupRoleMember,
  });

  final GroupEventKind kind;
  final String groupId;

  /// 事件发起者。
  final PeerId actor;

  /// 事件的操作对象（被移除者、被邀请者、退出者本人）。
  final PeerId? subject;

  final Hlc hlc;
  final DateTime ts;

  /// 建群时携带的群名。
  final String? name;

  /// roleChange 时的目标角色（owner / member）。
  final String role;

  /// 事件的操作对象；缺省时视为 actor 自己（用于 leave / accept）。
  PeerId get effectiveSubject => subject ?? actor;

  /// 线上形态。
  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.name,
        'gid': groupId,
        'actor': actor.value,
        'hlc': hlc.encode(),
        'ts': ts.toUtc().millisecondsSinceEpoch,
        if (subject != null) 'subject': subject!.value,
        if (name != null) 'name': name,
        if (kind == GroupEventKind.roleChange) 'role': role,
      };

  /// 从线上值域解析；缺字段或类型不符抛 invalidArgument，绝不静默补默认值。
  factory GroupEvent.fromJson(Map<String, Object?> json) {
    final Object? kindRaw = json['kind'];
    final Object? gidRaw = json['gid'];
    final Object? actorRaw = json['actor'];
    final Object? hlcRaw = json['hlc'];
    final Object? tsRaw = json['ts'];
    if (kindRaw is! String ||
        gidRaw is! String ||
        gidRaw.isEmpty ||
        actorRaw is! String ||
        hlcRaw is! String ||
        tsRaw is! int) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        '群事件缺少必需字段',
      );
    }
    final GroupEventKind kind = GroupEventKind.values.firstWhere(
      (GroupEventKind value) => value.name == kindRaw,
      orElse: () => throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '群事件 kind 非法: $kindRaw',
      ),
    );
    final PeerId actor = PeerId.tryParse(actorRaw) ??
        (throw LanFileException(
          LanFileErrorCode.invalidArgument,
          '群事件 actor 不是合法 peerId: $actorRaw',
        ));
    final Object? subjectRaw = json['subject'];
    final PeerId? subject =
        subjectRaw is String ? PeerId.tryParse(subjectRaw) : null;
    if (subjectRaw != null && subject == null) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        '群事件 subject 不是合法 peerId',
      );
    }
    final Hlc hlc;
    try {
      hlc = Hlc.parse(hlcRaw);
    } on FormatException catch (error) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '群事件 hlc 非法: $hlcRaw',
        cause: error,
      );
    }
    return GroupEvent(
      kind: kind,
      groupId: gidRaw,
      actor: actor,
      hlc: hlc,
      ts: DateTime.fromMillisecondsSinceEpoch(tsRaw, isUtc: true),
      subject: subject,
      name: json['name'] as String?,
      role: normalizeGroupRole((json['role'] as String?) ?? kGroupRoleMember),
    );
  }

  /// WS 帧形式（沿用 WsFrame.msg 通道，payload 里带 groupEvent）。
  WsFrame toFrame() => WsFrame(WsFrame.msg, <String, Object?>{
        'groupEvent': toJson(),
      });

  /// 从 WsFrame.msg 的 payload 里取群事件；不是群事件帧则 null。
  static GroupEvent? tryFromFrame(WsFrame frame) {
    if (frame.type != WsFrame.msg) return null;
    final Object? raw = frame.payload['groupEvent'];
    if (raw is! Map<String, Object?>) return null;
    return GroupEvent.fromJson(raw);
  }
}

/// 事件去重键：kind + groupId + actor + hlc + subject。
String groupEventKey(GroupEvent event) => <String>[
      event.kind.name,
      event.groupId,
      event.actor.value,
      event.hlc.encode(),
      event.effectiveSubject.value,
    ].join('|');

/// 群成员关系在一个节点上的收敛视图。
///
/// 只由事件驱动，不直接读写数据库：调用方（GroupService）负责落盘，
/// 这样收敛逻辑可以完全脱离存储单测。
final class GroupMemberLedger {
  GroupMemberLedger({required this.self});

  /// 本机 peerId；用于判定「我还在不在群里」。
  final PeerId self;

  final Map<String, Map<PeerId, GroupMemberRecord>> _members =
      <String, Map<PeerId, GroupMemberRecord>>{};
  final Map<String, GroupRecord> _groups = <String, GroupRecord>{};
  final Set<String> _applied = <String>{};

  /// 当前已知的全部群。
  List<GroupRecord> get groups => _groups.values.toList(growable: false);

  /// 某个群当前可见的成员（群主在前）。
  List<GroupMemberRecord> membersOf(String groupId) {
    final Map<PeerId, GroupMemberRecord>? map = _members[groupId];
    if (map == null) return const <GroupMemberRecord>[];
    return List<GroupMemberRecord>.unmodifiable(
      sortGroupMembers(map.values.toList()),
    );
  }

  /// 我是否仍是该群成员（决定还收不收该群消息）。
  bool isMemberOf(String groupId) {
    final Map<PeerId, GroupMemberRecord>? map = _members[groupId];
    if (map == null) return false;
    return map.containsKey(self);
  }

  /// 群是否已解散。
  bool isArchived(String groupId) => _groups[groupId]?.isArchived ?? false;

  /// 应用一条事件；返回是否真的改变了状态。
  ///
  /// 幂等：同一事件第二次应用返回 false。
  /// 顺序无关：每条事件只写终态，不依赖先前事件的到达顺序。
  bool apply(GroupEvent event, {DateTime? now}) {
    if (!_applied.add(groupEventKey(event))) return false;
    final DateTime at = now ?? event.ts;
    switch (event.kind) {
      case GroupEventKind.invite:
        return _applyInvite(event, at);
      case GroupEventKind.accept:
        return _ensureMember(event, event.actor, kGroupRoleMember, at);
      case GroupEventKind.leave:
      case GroupEventKind.removeMember:
        return _dropMember(event.groupId, event.effectiveSubject);
      case GroupEventKind.dissolve:
        return _applyDissolve(event, at);
      case GroupEventKind.roleChange:
        return _applyRoleChange(event, at);
    }
  }

  /// 某条事件是否被授权（只有群主能踢人、解散、改角色）。
  ///
  /// 单独暴露而不是在 apply 里静默丢弃：调用方需要把
  /// 「收到越权事件」与「收到合法事件」区分开记录。
  bool isAuthorized(GroupEvent event) {
    final GroupRecord? group = _groups[event.groupId];
    if (group == null) return event.kind == GroupEventKind.invite;
    switch (event.kind) {
      case GroupEventKind.invite:
      case GroupEventKind.removeMember:
      case GroupEventKind.dissolve:
      case GroupEventKind.roleChange:
        return group.ownerPeerId == event.actor;
      case GroupEventKind.accept:
      case GroupEventKind.leave:
        return event.actor == event.effectiveSubject;
    }
  }

  bool _applyInvite(GroupEvent event, DateTime at) {
    if (!_groups.containsKey(event.groupId)) {
      _groups[event.groupId] = GroupRecord(
        id: event.groupId,
        name: event.name ?? '',
        avatarHash: '',
        ownerPeerId: event.actor,
        createdAt: at,
        epoch: 1,
      );
    }
    final GroupRecord group = _groups[event.groupId]!;
    _ensureMember(event, group.ownerPeerId, kGroupRoleOwner, at);
    final PeerId? invited = event.subject;
    if (invited != null && invited != group.ownerPeerId) {
      _ensureMember(event, invited, kGroupRoleMember, at);
    }
    return true;
  }

  bool _applyDissolve(GroupEvent event, DateTime at) {
    final GroupRecord? group = _groups[event.groupId];
    if (group == null) return false;
    _groups[event.groupId] = GroupRecord(
      id: group.id,
      name: group.name,
      avatarHash: group.avatarHash,
      ownerPeerId: group.ownerPeerId,
      createdAt: group.createdAt,
      epoch: group.epoch,
      archivedAt: at,
    );
    return true;
  }

  bool _applyRoleChange(GroupEvent event, DateTime at) {
    final PeerId target = event.effectiveSubject;
    final Map<PeerId, GroupMemberRecord>? map = _members[event.groupId];
    final GroupMemberRecord? current = map?[target];
    if (current == null) return false;
    final String role = normalizeGroupRole(event.role);

    // 一个群只能有一个群主：先把现群主降为普通成员，再升级目标。
    // 不做这一步的话，转让后成员表里会出现两个 owner，
    // findGroupOwner 会返回先遇到的那个（通常是旧群主），权限判定随之出错。
    final Map<PeerId, GroupMemberRecord> memberMap = map!;
    for (final GroupMemberRecord member in memberMap.values.toList()) {
      if (isGroupOwner(member) && member.peerId != target) {
        memberMap[member.peerId] = GroupMemberRecord(
          groupId: member.groupId,
          peerId: member.peerId,
          role: kGroupRoleMember,
          joinedAt: member.joinedAt,
          lastSeen: member.lastSeen,
        );
      }
    }

    memberMap[target] = GroupMemberRecord(
      groupId: event.groupId,
      peerId: target,
      role: role,
      joinedAt: current.joinedAt,
      lastSeen: current.lastSeen,
    );
    if (role == kGroupRoleOwner) {
      final GroupRecord? group = _groups[event.groupId];
      if (group != null) {
        _groups[event.groupId] = GroupRecord(
          id: group.id,
          name: group.name,
          avatarHash: group.avatarHash,
          ownerPeerId: target,
          createdAt: group.createdAt,
          epoch: group.epoch,
          archivedAt: group.archivedAt,
        );
      }
    }
    return true;
  }

  bool _ensureMember(
    GroupEvent event,
    PeerId peer,
    String role,
    DateTime at,
  ) {
    final Map<PeerId, GroupMemberRecord> map =
        _members.putIfAbsent(event.groupId, () => <PeerId, GroupMemberRecord>{});
    if (map.containsKey(peer)) return false;
    map[peer] = GroupMemberRecord(
      groupId: event.groupId,
      peerId: peer,
      role: role,
      joinedAt: at,
    );
    return true;
  }

  bool _dropMember(String groupId, PeerId peer) {
    final Map<PeerId, GroupMemberRecord>? map = _members[groupId];
    if (map == null) return false;
    return map.remove(peer) != null;
  }
}

/// 把成员账本编码成可落库的快照（供调试与测试断言使用）。
String encodeLedgerSnapshot(GroupMemberLedger ledger) => jsonEncode(
      <String, Object?>{
        'groups': <Object?>[
          for (final GroupRecord g in ledger.groups)
            <String, Object?>{
              'id': g.id,
              'name': g.name,
              'owner': g.ownerPeerId.value,
              'archived': g.isArchived,
            },
        ],
      },
    );