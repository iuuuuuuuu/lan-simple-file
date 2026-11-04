// SPDX-License-Identifier: GPL-3.0-only

/// MessagingService 的实现：单聊与群聊、HLC 同步、撤回、离线补发。
///
/// 设计取舍（都写在这里，避免后人重踩）：
///
/// 1. **消息落库是唯一真相，网络只是加速器。**
///    每条消息先 putMessage 落库再尝试发送，收到 ACK 前保留在待发队列。
///    进程重启后消息仍在，对端通过补拉恢复历史。
///
/// 2. **补拉是双向且幂等的。**
///    连上后双方发送 pull 请求；单聊按 HLC 增量拉取，群聊补拉历史并去重。
///    putMessage 对新旧是 upsert 语义，重复到达的同一条消息不会产生第二行，
///    因此「拉了重复区间」是安全的——这让补拉不需要精确协议。
///
/// 3. **撤回只标记不删除。**
///    本地写 revokedAt 后广播 revoke 帧；对端收到也只写 revokedAt。
///    物理删除会让「已撤回」和「从没存在过」不可区分，也无中心下无法保证一致。
///
/// 4. **单聊 threadId 由双方 peerId 字典序拼出**，群聊使用 g_ + groupId。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../contracts/contracts.dart';
import 'hlc_clock.dart';
import 'message_sync.dart';
import 'ws_hub.dart';

/// 单帧处理失败的上报点；缺省实现写 stderr。
///
/// 存在的意义：链路不能因为一帧坏掉就断，但失败必须可见——
/// 否则「对端发了、我这边没收到」将没有任何线索可查。
typedef FrameErrorReporter = void Function(
  PeerId peer,
  WsFrame frame,
  Object error,
  StackTrace stackTrace,
);

/// 群组创建与退出由 GroupService 提供，消息服务负责群消息的收发与同步。
abstract interface class GroupLifecycleDelegate {
  /// 建群，返回 groupId。
  Future<String> createGroup(String name, List<PeerId> members);

  /// 退群。
  Future<void> leaveGroup(String groupId);
}

/// 单聊 threadId 前缀。
const String kDirectThreadPrefix = 'd_';

/// 两个 peerId 之间的固定分隔符。
///
/// 不能用下划线：peerId 自身就长成 p_xxxx，含下划线。
/// 用 _ 拼出来的 threadId 无法无歧义地切回两个 peerId
/// （实测 d_p_22rfrcmq4hsfq_p_9oz6bgxrlbwug 一 split 就成 4 段，
/// 反解恒为 null，消息会全部落到「无对端」分支而静默发送失败）。
/// -- 不在 peerId 的字符集 [a-z0-9_] 内，因此可以安全地做分隔。
const String kThreadIdSeparator = '--';

/// 分隔符的正则形式（String.split 支持正则，避免逐个字面量判断）。
final RegExp _threadIdSplitter = RegExp(kThreadIdSeparator);

/// 由两个 peerId 生成单聊 threadId：按字典序拼接，两侧必然相同。
String directThreadId(PeerId a, PeerId b) {
  final List<String> ordered = <String>[a.value, b.value]..sort();
  return kDirectThreadPrefix + ordered[0] + kThreadIdSeparator + ordered[1];
}

/// 从 threadId 里还原对端 peerId（本机自己的那个排除掉）。
///
/// 同时兼容旧格式（下划线分隔）：旧值还能被读懂，避免历史库里的线程失联。
PeerId? peerInDirectThread(String threadId, PeerId self) {
  if (!threadId.startsWith(kDirectThreadPrefix)) return null;
  final String rest = threadId.substring(kDirectThreadPrefix.length);

  if (rest.contains(kThreadIdSeparator)) {
    final List<String> parts = rest.split(_threadIdSplitter);
    if (parts.length != 2) return null;
    for (final String part in parts) {
      final PeerId? candidate = PeerId.tryParse(part);
      if (candidate != null && candidate != self) return candidate;
    }
    return null;
  }

  // 兼容旧格式：d_ + a.value + _ + b.value，而 a.value 自身以 p_ 开头。
  final List<String> legacy = rest.split('_');
  if (legacy.length != 4 || legacy[0] != 'p' || legacy[2] != 'p') return null;
  final PeerId? left = PeerId.tryParse('p_${legacy[1]}');
  final PeerId? right = PeerId.tryParse('p_${legacy[3]}');
  if (left != null && left != self) return left;
  if (right != null && right != self) return right;
  return null;
}

/// 单聊 / 群聊消息服务。
final class MessagingServiceImpl implements MessagingService {
  MessagingServiceImpl({
    required this.store,
    required this.identity,
    required this.selfName,
    required this.selfAvatarHash,
    HlcClock? clock,
    DateTime Function()? now,
    this.groupDelegate,
    this.onFrameError,
    this.keys,
    this.verifier,
  }) : _clock = clock ?? HlcClock(origin: identity.peerId.value),
       _now = now ?? DateTime.now;

  /// 收侧验签所需的公钥来源。
  ///
  /// 未注入时**跳过收侧验签**并在 [unverifiedInbound] 计数——这是刻意的降级，
  /// 不能把它说成「已经验过」。生产接线必须注入（见 AppAssembler）。
  final PublicKeyLookup? keys;

  /// 收侧验签器；未注入时同样降级。
  final SignatureVerifier? verifier;

  /// 因未注入 keys/verifier 而未经签名校验的入站消息条数。
  ///
  /// 不提供这个计数，降级就是隐形的——排查时无法区分「对方没签」与「我没验」。
  int get unverifiedInbound => _unverifiedInbound;
  int _unverifiedInbound = 0;

  /// 已验签链路下、对方未签名的入站消息条数（当前允许的降级形态）。
  int get unsignedInbound => _unsignedInbound;
  int _unsignedInbound = 0;

  /// 群生命周期委派；为 null 时 createGroup/leaveGroup 抛 unsupported。
  final GroupLifecycleDelegate? groupDelegate;

  /// 单帧处理失败的上报点；为 null 时写 stderr。
  final FrameErrorReporter? onFrameError;

  final LanFileStore store;
  final DeviceIdentity identity;
  final String selfName;
  final String selfAvatarHash;
  final HlcClock _clock;
  final DateTime Function() _now;

  /// 每个 thread 的变更广播；watchMessages 据此推送。
  final Map<String, StreamController<List<MessageRecord>>> _messageWatch =
      <String, StreamController<List<MessageRecord>>>{};
  final StreamController<List<ThreadRecord>> _threadWatch =
      StreamController<List<ThreadRecord>>.broadcast();

  /// 已建立的出站/入站链路，键为对端 peerId。
  final Map<String, WsLink> _links = <String, WsLink>{};

  /// 离线待发队列：键为对端 peerId，值为尚未被 ack 的消息 id 队列。
  ///
  /// 用 id 而不是整条消息：重连后按 id 从库里重新取出当前内容再发，
  /// 这样期间发生的撤回/编辑会自动反映到重发的内容里。
  final Map<String, List<String>> _pending = <String, List<String>>{};

  int? _sequence;
  Future<void> _sending = Future<void>.value();
  final Map<String, Future<void>> _receiving = {};

  bool _disposed = false;

  /// 当前 HLC 时钟（供测试断言单调性）。
  HlcClock get clock => _clock;

  /// 某对端是否在线。
  bool isPeerOnline(PeerId peer) {
    final WsLink? link = _links[peer.value];
    return link != null && !link.isClosed;
  }

  /// 离线队列里某对端待发的条数（测试与 UI 角标用）。
  int pendingCount(PeerId peer) => _pending[peer.value]?.length ?? 0;

  // ------------------------------------------------------------ service API

  @override
  Stream<List<ThreadRecord>> watchThreads() async* {
    yield await store.listThreads();
    yield* _threadWatch.stream;
  }

  @override
  Stream<List<MessageRecord>> watchMessages(String threadId) async* {
    yield await _loadThread(threadId);
    final StreamController<List<MessageRecord>> controller = _messageWatch
        .putIfAbsent(
          threadId,
          () => StreamController<List<MessageRecord>>.broadcast(),
        );
    yield* controller.stream;
  }

  @override
  Future<void> sendText(String threadId, String text) async {
    await _send(threadId, MessageKind.text, body: text, attachJson: '');
  }

  @override
  Future<void> sendFile(
    String threadId,
    ShareId share, {
    ItemKey? itemKey,
  }) async {
    // 只记位置，不复制文件本体（计划 6.5）：attach 里存 shareId + itemKey。
    final record = await store.findShare(share);
    final Map<String, Object?> attach = <String, Object?>{
      'shareId': share.value,
      'owner': identity.peerId.value,
      if (record != null) 'name': record.displayName,
      if (itemKey != null) 'itemKey': itemKey.value,
    };
    await _send(
      threadId,
      MessageKind.share,
      body: '',
      attachJson: _encodeAttach(attach),
    );
  }

  @override
  Future<void> revoke(String messageId, {String? reason}) async {
    final DateTime at = _now().toUtc();
    final MessageRecord? record = await _findMessage(messageId);
    if (record == null) {
      throw LanFileException(
        LanFileErrorCode.notFound,
        '要撤回的消息不存在: $messageId',
      );
    }
    if (record.senderPeerId != identity.peerId) {
      throw const LanFileException(
        LanFileErrorCode.accessDenied,
        '只能撤回自己发送的消息',
      );
    }
    if (record.isRevoked) return;
    await store.revokeMessage(messageId, at: at, reason: reason);
    final WsFrame frame = WsFrame(
      WsFrame.revoke,
      encodeRevoke(messageId, at, reason: reason),
    );
    await _broadcast(record.threadId, frame);
    await _notifyThread(record.threadId);
  }

  @override
  Future<void> deleteLocal(String messageId) async {
    // 本地删除只是不再展示；对端不受影响（计划 6.3）。
    await store.revokeMessage(
      messageId,
      at: _now().toUtc(),
      reason: 'deletedLocal',
    );
  }

  @override
  Future<void> deleteThread(String threadId) async {
    // 仅本地：置 deletedAt，不影响对方；同 peer 再来信会重建。
    final ThreadRecord? existing = await _findThread(threadId);
    if (existing == null) return;
    await store.upsertThread(
      ThreadRecord(
        id: existing.id,
        kind: existing.kind,
        title: existing.title,
        avatarHash: existing.avatarHash,
        unread: 0,
        muted: existing.muted,
        pinned: existing.pinned,
        createdAt: existing.createdAt,
        peerId: existing.peerId,
        groupId: existing.groupId,
        lastMsgHlc: existing.lastMsgHlc,
        lastMsgPreview: existing.lastMsgPreview,
        deletedAt: _now().toUtc(),
      ),
    );
    await _notifyThread(threadId);
  }

  @override
  Future<String> createGroup(String name, List<PeerId> members) async {
    // 群组成员与邀请由 GroupService 管理，消息服务只刷新对应的会话。
    final GroupLifecycleDelegate? delegate = groupDelegate;
    if (delegate == null) {
      throw const LanFileException(
        LanFileErrorCode.unsupported,
        '未注入 GroupLifecycleDelegate：群组功能由 GroupService 提供',
      );
    }
    final String id = await delegate.createGroup(name, members);
    await _notifyThread('g_$id');
    return id;
  }

  @override
  Future<void> leaveGroup(String groupId) {
    final GroupLifecycleDelegate? delegate = groupDelegate;
    if (delegate == null) {
      throw const LanFileException(
        LanFileErrorCode.unsupported,
        '未注入 GroupLifecycleDelegate：群组功能由 GroupService 提供',
      );
    }
    return delegate.leaveGroup(groupId);
  }

  // --------------------------------------------------------------- 内部实现

  Future<void> _send(
    String threadId,
    MessageKind kind, {
    required String body,
    required String attachJson,
  }) {
    final task = _sending.then(
      (_) => _sendOnce(threadId, kind, body: body, attachJson: attachJson),
    );
    _sending = task.catchError((Object _) {});
    return task;
  }

  Future<void> _sendOnce(
    String threadId,
    MessageKind kind, {
    required String body,
    required String attachJson,
  }) async {
    if (_disposed) throw StateError('消息服务已关闭');
    if (kind == MessageKind.text &&
        (body.trim().isEmpty || body.length > 16000)) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        '消息不能为空或超过 16000 字符',
      );
    }
    final recipients = await _recipients(threadId);
    final String messageId = await _nextMessageId();
    final Hlc hlc = _clock.next();
    final DateTime ts = _now().toUtc();

    // 签名只覆盖不可变字段（契约 MessageSignature 已定死字段集合与先后顺序）。
    // 撤回/删除/编辑都是后续事件，故意不进签名：
    // 否则一撤回历史消息的签名就集体失效。
    final Uint8List canonical = MessageSignature.canonicalBytes(
      messageId: messageId,
      threadId: threadId,
      senderPeerId: identity.peerId.value,
      hlc: hlc.encode(),
      tsMillis: ts.millisecondsSinceEpoch,
      kind: kind.name,
      body: body,
      attachJson: attachJson,
    );
    final Uint8List signature = await identity.sign(canonical);

    final MessageRecord record = MessageRecord(
      id: messageId,
      threadId: threadId,
      senderPeerId: identity.peerId,
      kind: kind,
      hlc: hlc,
      ts: ts,
      body: body,
      attachJson: attachJson,
      sig: base64Url.encode(signature).replaceAll('=', ''),
    );

    // 先落库：网络失败也不能让这条消息凭空消失。
    await store.putMessage(record);
    await _ensureThread(
      recipients.isEmpty ? identity.peerId : recipients.first,
      record,
    );
    await _notifyThread(threadId);

    for (final peer in recipients) {
      _pending.putIfAbsent(peer.value, () => <String>[]).add(record.id);
      _trySendTo(peer, record);
    }
  }

  String _encodeAttach(Map<String, Object?> attach) => jsonEncode(attach);

  Future<String> _nextMessageId() async {
    int current = _sequence ?? 0;
    if (_sequence == null) {
      current =
          int.tryParse(await store.getSetting('messaging.sequence') ?? '') ?? 0;
      for (final thread in await store.listThreads()) {
        for (final message in await _loadThread(thread.id)) {
          if (message.senderPeerId != identity.peerId) continue;
          final prefix = '${identity.peerId.value}:';
          if (!message.id.startsWith(prefix)) continue;
          final seq = int.tryParse(message.id.substring(prefix.length));
          if (seq != null && seq > current) current = seq;
        }
      }
    }
    current++;
    await store.setSetting('messaging.sequence', current.toString());
    _sequence = current;
    return '${identity.peerId.value}:$current';
  }

  Future<void> _ensureThread(
    PeerId peer,
    MessageRecord latest, {
    bool incoming = false,
    bool isNew = true,
  }) async {
    final String threadId = latest.threadId;
    final ThreadRecord? existing = await _findThread(threadId);
    final String? groupId = _groupId(threadId);
    final group = groupId == null ? null : await store.findGroup(groupId);
    final bool newer =
        existing?.lastMsgHlc == null ||
        latest.hlc.compareTo(existing!.lastMsgHlc!) >= 0;
    await store.upsertThread(
      ThreadRecord(
        id: threadId,
        kind: groupId == null ? 'direct' : 'group',
        title: group?.name ?? existing?.title ?? peer.value,
        avatarHash: existing?.avatarHash ?? '',
        unread:
            (existing?.unread ?? 0) +
            (incoming && isNew && latest.senderPeerId != identity.peerId
                ? 1
                : 0),
        muted: existing?.muted ?? false,
        pinned: existing?.pinned ?? false,
        createdAt: existing?.createdAt ?? latest.ts,
        peerId: groupId == null ? peer : null,
        groupId: groupId,
        lastMsgHlc: newer ? latest.hlc : existing.lastMsgHlc,
        lastMsgPreview: newer ? _previewOf(latest) : existing.lastMsgPreview,
        deletedAt: null,
      ),
    );
  }

  String _previewOf(MessageRecord message) {
    if (message.kind == MessageKind.text) {
      return message.body;
    }
    return '[${message.kind.name}]';
  }

  Future<MessageRecord?> _findMessage(String id) async {
    // 契约没有单条查询；按线程扫描是已知代价，后续可加 findMessage。
    final List<ThreadRecord> threads = await store.listThreads();
    for (final ThreadRecord thread in threads) {
      final List<MessageRecord> messages = await store.listMessages(
        thread.id,
        limit: -1,
      );
      for (final MessageRecord message in messages) {
        if (message.id == id) return message;
      }
    }
    return null;
  }

  Future<ThreadRecord?> _findThread(String threadId) async {
    final List<ThreadRecord> threads = await store.listThreads();
    for (final ThreadRecord thread in threads) {
      if (thread.id == threadId) return thread;
    }
    return null;
  }

  Future<List<MessageRecord>> _loadThread(String threadId) =>
      store.listMessages(threadId, limit: -1);

  Future<void> _notifyThread(String threadId) async {
    final StreamController<List<MessageRecord>>? controller =
        _messageWatch[threadId];
    if (controller != null && !controller.isClosed) {
      controller.add(await _loadThread(threadId));
    }
    if (!_threadWatch.isClosed) {
      _threadWatch.add(await store.listThreads());
    }
  }

  Future<void> refreshThreads() async {
    if (!_threadWatch.isClosed) {
      _threadWatch.add(await store.listThreads());
    }
  }

  Future<void> syncConnectedPeers() async {
    for (final value in _links.keys.toList()) {
      await pullFrom(PeerId.parse(value));
    }
  }

  bool _trySendTo(PeerId peer, MessageRecord record) {
    final WsLink? link = _links[peer.value];
    if (link == null || link.isClosed) return false;
    return link.send(WsFrame(WsFrame.msg, encodeMessage(record)));
  }

  Future<void> _broadcast(String threadId, WsFrame frame) async {
    for (final peer in await _recipients(threadId)) {
      final link = _links[peer.value];
      if (link != null && !link.isClosed) link.send(frame);
    }
  }

  String? _groupId(String threadId) =>
      threadId.startsWith('g_') && threadId.length > 2
      ? threadId.substring(2)
      : null;

  Future<List<PeerId>> _recipients(String threadId) async {
    final groupId = _groupId(threadId);
    if (groupId == null) {
      if (threadId == directThreadId(identity.peerId, identity.peerId)) {
        return [];
      }
      final peer = peerInDirectThread(threadId, identity.peerId);
      if (peer == null || threadId != directThreadId(identity.peerId, peer)) {
        throw const LanFileException(
          LanFileErrorCode.invalidArgument,
          '会话标识无效',
        );
      }
      return [peer];
    }
    final group = await store.findGroup(groupId);
    final members = await store.listGroupMembers(groupId);
    if (group == null ||
        group.isArchived ||
        !members.any((m) => m.peerId == identity.peerId)) {
      throw const LanFileException(LanFileErrorCode.accessDenied, '群聊已解散或你已退出');
    }
    return [
      for (final member in members)
        if (member.peerId != identity.peerId) member.peerId,
    ];
  }

  Future<void> _requirePeerInThread(String threadId, PeerId peer) async {
    if (!(await _recipients(threadId)).contains(peer)) {
      throw const LanFileException(LanFileErrorCode.accessDenied, '无权访问这个会话');
    }
  }

  Future<void> markRead(String threadId) async {
    final thread = await _findThread(threadId);
    if (thread == null || thread.unread == 0) return;
    await store.upsertThread(
      ThreadRecord(
        id: thread.id,
        kind: thread.kind,
        title: thread.title,
        avatarHash: thread.avatarHash,
        unread: 0,
        muted: thread.muted,
        pinned: thread.pinned,
        createdAt: thread.createdAt,
        peerId: thread.peerId,
        groupId: thread.groupId,
        lastMsgHlc: thread.lastMsgHlc,
        lastMsgPreview: thread.lastMsgPreview,
        deletedAt: thread.deletedAt,
      ),
    );
    await refreshThreads();
  }

  /// 采纳一条入站链路（服务端接受对端连入时调用）。
  Future<void> adoptInboundLink(WsLink link) async {
    link.start();
    link.sendHello();
    final RemoteIdentity remote = await link.handshake;
    await _registerLink(remote.peerId, link);
  }

  /// 采纳一条出站链路（客户端连上对端后调用）。
  Future<void> adoptOutboundLink(PeerId peer, WsLink link) async {
    await _registerLink(peer, link);
  }

  Future<void> _registerLink(PeerId peer, WsLink link) async {
    assert(!_disposed, '已释放的服务不应再接纳链路');
    final WsLink? previous = _links[peer.value];
    _links[peer.value] = link;
    if (previous != null && !identical(previous, link) && !previous.isClosed) {
      // 同一条对端同时有入站与出站链路时，后者胜出并关掉前者，
      // 否则两套链路会各自投递同一批帧，补拉变成重复劳动。
      unawaited(previous.close(reason: 'replaced by newer link'));
    }

    // 订阅业务帧。少了这一步，链路能握手但收不到任何消息——
    // 表现为「发送方本地有条目、接收方永远为空」。
    final StreamSubscription<WsFrame> subscription = link.frames.listen((
      WsFrame frame,
    ) {
      final task = (_receiving[peer.value] ?? Future<void>.value()).then(
        (_) => _handleFrameSafely(peer, frame),
      );
      _receiving[peer.value] = task;
    });
    unawaited(
      link.closed.whenComplete(() {
        unawaited(subscription.cancel());
        _onLinkClosed(peer, link);
      }),
    );

    // 建链即补拉：把对端有、我没有的消息拉过来。
    await pullFrom(peer);
    // 再把离线积压推给对端。
    await flushPending(peer);
  }

  /// 处理单帧并兜住异常：一帧出错不能让整条链路的监听器崩掉。
  ///
  /// 兜住 ≠ 吞掉：每次失败都经 [onFrameError] 上报（缺省写 stderr），
  /// 否则「消息静默丢失」会是最难查的一类故障。
  Future<void> _handleFrameSafely(PeerId peer, WsFrame frame) async {
    try {
      await handleFrame(peer, frame);
    } on LanFileException catch (error, stackTrace) {
      // 契约内错误：帧不合法或被本地拒绝。链路继续，但必须留痕。
      _reportFrameError(peer, frame, error, stackTrace);
    } on Object catch (error, stackTrace) {
      // 非预期错误：同样上报。下一次补拉会自愈，但先要能看见。
      _reportFrameError(peer, frame, error, stackTrace);
    }
  }

  void _reportFrameError(
    PeerId peer,
    WsFrame frame,
    Object error,
    StackTrace stackTrace,
  ) {
    final FrameErrorReporter? reporter = onFrameError;
    if (reporter != null) {
      reporter(peer, frame, error, stackTrace);
      return;
    }
    stderr.writeln(
      '[messaging] 处理来自 ${peer.value} 的 ${frame.type} 帧失败: $error',
    );
    stderr.writeln(stackTrace.toString());
  }

  void _onLinkClosed(PeerId peer, WsLink link) {
    if (identical(_links[peer.value], link)) {
      _links.remove(peer.value);
    }
  }

  /// 主动向 [peer] 拉取缺失消息（双向补拉的本方发起侧）。
  Future<void> pullFrom(PeerId peer) async {
    final WsLink? link = _links[peer.value];
    if (link == null || link.isClosed) return;
    final String threadId = directThreadId(identity.peerId, peer);
    final List<MessageRecord> local = await _loadThread(threadId);
    // sinceHlc 取本地最大 HLC；对端从这个点之后给我们。
    final Hlc? since = local.isEmpty ? null : local.last.hlc;
    link.send(WsFrame(WsFrame.pull, encodePull(threadId, since)));
    for (final thread in await store.listThreads()) {
      if (thread.kind != 'group' || thread.deletedAt != null) continue;
      try {
        await _requirePeerInThread(thread.id, peer);
        // 群历史可能由不同成员在离线期间补入；拉全量再按消息 ID 去重。
        link.send(WsFrame(WsFrame.pull, encodePull(thread.id, null)));
      } on LanFileException {
        // 已退出或解散的群不再同步。
      }
    }
  }

  /// 把离线积压的消息重发给 [peer]。
  Future<void> flushPending(PeerId peer) async {
    final List<String>? queue = _pending[peer.value];
    if (queue == null || queue.isEmpty) return;
    final WsLink? link = _links[peer.value];
    if (link == null || link.isClosed) return;
    for (final String id in List<String>.of(queue)) {
      final MessageRecord? record = await _findMessage(id);
      if (record == null) {
        queue.remove(id);
        continue;
      }
      try {
        await _requirePeerInThread(record.threadId, peer);
        if (!link.send(WsFrame(WsFrame.msg, encodeMessage(record)))) return;
      } on LanFileException {
        queue.remove(id);
      }
    }
  }

  /// 处理一条入站帧。链路已握手，[peer] 是已确认的对端。
  Future<void> handleFrame(PeerId peer, WsFrame frame) async {
    switch (frame.type) {
      case WsFrame.msg:
        await _onIncomingMessage(peer, frame.payload);
        return;
      case WsFrame.pull:
        if (frame.payload.containsKey('messages')) {
          final threadId = frame.payload['thread'] as String;
          await _requirePeerInThread(threadId, peer);
          for (final message in decodePullResponse(frame.payload)) {
            if (message.threadId != threadId) {
              throw const LanFileException(
                LanFileErrorCode.accessDenied,
                '补拉响应的会话不匹配',
              );
            }
            await _onIncomingMessage(
              peer,
              encodeMessage(message),
              history: true,
            );
          }
        } else {
          await _onPullRequest(peer, frame.payload);
        }
        return;
      case WsFrame.revoke:
        await _onRevoke(peer, frame.payload);
        return;
      case WsFrame.ack:
        await _onAck(peer, frame.payload);
        return;
      default:
        // hello 已在链路层消费；其它帧本任务不处理（offer/progress 属后续任务）。
        return;
    }
  }

  Future<void> _onIncomingMessage(
    PeerId peer,
    Map<String, Object?> payload, {
    bool history = false,
  }) async {
    final MessageRecord record = decodeMessage(payload);
    await _requirePeerInThread(record.threadId, peer);
    final allowedSenders = [
      identity.peerId,
      ...await _recipients(record.threadId),
    ];
    if ((!history && record.senderPeerId != peer) ||
        !allowedSenders.contains(record.senderPeerId) ||
        !record.id.startsWith('${record.senderPeerId.value}:')) {
      throw const LanFileException(
        LanFileErrorCode.accessDenied,
        '消息发送者与会话不匹配',
      );
    }

    // 收侧验签：没有它，「签名」只落实了一半（能签不能验）。
    //
    // 三种情况必须区分清楚，不能含糊过去：
    //   1. keys/verifier 未注入 → 降级跳过，计入 unverifiedInbound（不静默）；
    //   2. 发送者公钥查不到 → 拒收并抛 accessDenied（可能是伪造来源）；
    //   3. 签名不匹配 → 拒收并抛 accessDenied（内容被篡改或来源被冒充）。
    // 未签名（sig 为空）但发送者已知 → 接受但计入 unsigedInbound，
    // 因为「不做签名」是当前允许的降级形态，不能因此丢掉消息本身。
    final PublicKeyLookup? lookup = keys;
    final SignatureVerifier? sigVerifier = verifier;
    if (lookup == null || sigVerifier == null) {
      _unverifiedInbound++;
    } else if (record.sig.isEmpty) {
      _unsignedInbound++;
    } else {
      final Uint8List? pubkey = await lookup.findPublicKey(record.senderPeerId);
      if (pubkey == null) {
        throw LanFileException(
          LanFileErrorCode.accessDenied,
          '未知发送者的公钥：${record.senderPeerId.value}',
        );
      }
      final Uint8List canonical = MessageSignature.canonicalBytes(
        messageId: record.id,
        threadId: record.threadId,
        senderPeerId: record.senderPeerId.value,
        hlc: record.hlc.encode(),
        tsMillis: record.ts.millisecondsSinceEpoch,
        kind: record.kind.name,
        body: record.body,
        attachJson: record.attachJson,
      );
      final bool ok = await sigVerifier.verify(
        canonical,
        _decodeSignature(record.sig),
        pubkey,
      );
      if (!ok) {
        throw LanFileException(
          LanFileErrorCode.accessDenied,
          '消息签名校验失败：${record.id}',
        );
      }
    }

    // upsert 幂等：补拉重复到达时不会产生第二行。
    final old = (await _loadThread(record.threadId))
        .where((m) => m.id == record.id)
        .firstOrNull;
    // 本地删除和已撤回的记录不被补拉恢复。
    if (old?.isRevoked != true) await store.putMessage(record);
    _clock.observe(record.hlc);
    await _ensureThread(peer, record, incoming: true, isNew: old == null);
    // 立刻 ack，让对端可以清掉待发队列。
    final WsLink? link = _links[peer.value];
    if (link != null && !link.isClosed) {
      link.send(WsFrame(WsFrame.ack, encodeAck(<String>[record.id])));
    }
    await _notifyThread(record.threadId);
  }

  Future<void> _onPullRequest(PeerId peer, Map<String, Object?> payload) async {
    final PullRequest request = decodePull(payload);
    await _requirePeerInThread(request.threadId, peer);
    final List<MessageRecord> all = await _loadThread(request.threadId);
    final Hlc? since = request.since;
    final List<MessageRecord> delta = since == null
        ? all
        : all
              .where(
                (MessageRecord m) =>
                    m.hlc.compareTo(since) > 0 ||
                    (m.isRevoked && m.revokeReason != 'deletedLocal'),
              )
              .toList(growable: false);
    final WsLink? link = _links[peer.value];
    if (link == null || link.isClosed) return;
    link.send(
      WsFrame(WsFrame.pull, encodePullResponse(request.threadId, delta)),
    );
  }

  Future<void> _onRevoke(PeerId peer, Map<String, Object?> payload) async {
    final RevokeRequest request = decodeRevoke(payload);
    final record = await _findMessage(request.messageId);
    if (record == null) return;
    await _requirePeerInThread(record.threadId, peer);
    if (record.senderPeerId != peer) {
      throw const LanFileException(
        LanFileErrorCode.accessDenied,
        '只能撤回自己发送的消息',
      );
    }
    // 只标记不删除（计划 6.3）。
    await store.revokeMessage(
      request.messageId,
      at: request.at,
      reason: request.reason,
    );
    await _notifyThread(record.threadId);
  }

  Future<void> _onAck(PeerId peer, Map<String, Object?> payload) async {
    final List<String> acked = decodeAck(payload);
    final List<String>? queue = _pending[peer.value];
    if (queue == null) return;
    for (final String id in acked) {
      queue.remove(id);
    }
    if (queue.isEmpty) _pending.remove(peer.value);
  }

  /// 释放资源；之后不再处理任何帧。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _sending;
    // 必须先拷贝再遍历：close 会触发 closed 回调，回调里会 remove 同一张 map，
    // 直接遍历 values 会抛 Concurrent modification（真实踩过）。
    final List<WsLink> links = List<WsLink>.of(_links.values);
    _links.clear();
    for (final WsLink link in links) {
      await link.close(reason: 'service disposed');
    }
    await Future.wait(_receiving.values);
    final List<StreamController<List<MessageRecord>>> controllers =
        List<StreamController<List<MessageRecord>>>.of(_messageWatch.values);
    _messageWatch.clear();
    for (final StreamController<List<MessageRecord>> controller
        in controllers) {
      if (!controller.isClosed) await controller.close();
    }
    if (!_threadWatch.isClosed) await _threadWatch.close();
  }
}

/// 从 base64url（无填充）还原签名字节。
///
/// 契约里签名以无填充 base64url 存放（与凭证 token 的段编码一致），
/// Dart 的 [base64Url.decode] 要求 4 的倍数，故此处补齐填充。
Uint8List _decodeSignature(String sig) {
  final int remainder = sig.length % 4;
  final String padded = remainder == 0 ? sig : sig + '=' * (4 - remainder);
  return Uint8List.fromList(base64Url.decode(padded));
}
