// SPDX-License-Identifier: GPL-3.0-only

/// AnnounceService 实现：UDP 广播 + 组播公告、验签、上下线状态机。
///
/// # 契约缺口与本文件的补法
///
/// [AnnounceService] 只有 5 个方法（start/stop/buildPacket/watchIncoming/probe），
/// 它**没有任何「把收到的 peer 写进库」的入口**，也无法表达「验签失败的包
/// 要丢弃并计数」。验收要求「验签失败必须丢弃并计数、不得 upsert」，
/// 因此本实现额外引入：
///
/// - [PeerUpsertSink]：一个极小的写入门面，只有 `upsertVerifiedPeer`。
///   生产侧由 App 用 `LanFileStore.upsertDevice` 实现；测试侧可注入内存实现。
///   默认是 [NoopPeerUpsertSink]，即「不接存储也不丢数据」——
///   保证不接线时也不会崩，但也不假装写了库。
/// - [RejectedDatagramCounter]：验签失败与畸形包的计数账本，
///   带最近失败样例，供 UI 排障与验收断言。
///
/// 这两者都是**新增**类型，不改动任何冻结契约。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/identity/ed25519_signer.dart';

import 'announce_codec.dart';
import 'multicast_join.dart';
import 'peer_activity_tracker.dart';
import 'udp_channel.dart';

/// 不落库的默认实现（未接线时用）。
///
/// 契约里的 [PeerUpsertSink] 要求「只接收已验签通过的公告」；
/// 这个 no-op 实现字面上什么都不做，因此绝不假装写过库。
final class NoopPeerUpsertSink implements PeerUpsertSink {
  const NoopPeerUpsertSink();

  @override
  Future<void> upsertVerifiedPeer(AnnouncePacket packet) async {}
}

/// [RejectedDatagramCounter] 的可变实现。
///
/// 契约只给了 getter；写入口（record*）留在实现侧，
/// 因为「谁来记一笔」属于发现层内部职责，不该暴露给 UI。
final class MutableRejectedCounter implements RejectedDatagramCounter {
  int _badSignature = 0;
  int _malformed = 0;
  int _fromSelf = 0;
  int _unknownPeerId = 0;
  final List<String> _recentReasons = <String>[];

  /// 最多保留多少条原因；超出丢最旧的。
  static const int maxReasons = 20;

  @override
  int get badSignature => _badSignature;

  @override
  int get malformed => _malformed;

  @override
  int get fromSelf => _fromSelf;

  @override
  int get unknownPeerId => _unknownPeerId;

  /// 总丢弃数（不含 fromSelf，那是正常回环不是错误）。
  int get totalRejected => _badSignature + _malformed + _unknownPeerId;

  @override
  List<String> get recentReasons => List<String>.unmodifiable(_recentReasons);

  void _remember(String reason) {
    _recentReasons.add(reason);
    if (_recentReasons.length > maxReasons) {
      _recentReasons.removeAt(0);
    }
  }

  /// 记一次验签失败。
  void recordBadSignature(PeerId peerId) {
    _badSignature++;
    _remember('验签失败: ${peerId.value}');
  }

  /// 记一次畸形包。
  void recordMalformed(String reason) {
    _malformed++;
    _remember('畸形包: $reason');
  }

  /// 记一次自己的回环包。
  void recordSelf() {
    _fromSelf++;
  }

  /// 记一次 peerId 非法。
  void recordUnknownPeerId(String raw) {
    _unknownPeerId++;
    _remember('非法 peerId: $raw');
  }

  /// 清零（测试与重启用）。
  void reset() {
    _badSignature = 0;
    _malformed = 0;
    _fromSelf = 0;
    _unknownPeerId = 0;
    _recentReasons.clear();
  }

  @override
  String toString() =>
      'RejectedDatagramCounter(bad=$_badSignature, '
      'malformed=$_malformed, self=$_fromSelf, badPeerId=$_unknownPeerId)';
}

/// 公告帧的发送方式；测试可替换成不落网卡的直投。
typedef AnnounceSender = void Function(Uint8List bytes);

/// 实现说明见文件头。
final class AnnounceServiceImpl implements AnnounceService {
  AnnounceServiceImpl({
    required this.identity,
    required this.serverPort,
    required this.shareCountProvider,
    this.name = '',
    this.avatarHash = '',
    this.nameReader,
    this.avatarHashReader,
    this.capabilities = const <String>{
      'chat',
      'group',
      'offer',
      'push',
      'web-session',
    },
    this.port = LanFileConstants.udpPort,
    this.localIp = '',
    this.localIpReader,
    DateTime Function()? clock,
    PeerUpsertSink? sink,
    Ed25519Signer? verifier,
    MulticastGroup? multicast,
  }) : _clock = clock ?? DateTime.now,
       _sink = sink ?? const NoopPeerUpsertSink(),
       _verifier = verifier ?? Ed25519Signer(),
       _multicast =
           multicast ??
           MulticastGroup.defaultGroup(
             port: port == 0 ? LanFileConstants.udpPort : port,
           ) {
    _tracker = PeerActivityTracker(clock: _clock);
  }

  /// 本机身份，用于签名与判别「这是不是我发的」。
  final DeviceIdentity identity;

  /// 本机 HTTP 端口（可能因占用顺延）。
  final int serverPort;

  /// 分享数量来源；每次 buildPacket 都重新问一次。
  final ShareCountProvider shareCountProvider;

  /// 本机展示名。
  final String name;

  /// 本机头像哈希。
  final String avatarHash;
  final String Function()? nameReader;
  final String Function()? avatarHashReader;

  /// 能力集合；写进公告供对端协商。
  final Set<String> capabilities;

  /// UDP 端口；测试可覆盖（同进程双实例互发必须用不同端口）。
  final int port;

  /// 公告里携带的本机 IP（可空；契约允许空串）。
  final String localIp;
  final String Function()? localIpReader;

  final DateTime Function() _clock;
  PeerUpsertSink _sink;
  final Ed25519Signer _verifier;
  final MulticastGroup _multicast;

  late final PeerActivityTracker _tracker;

  /// 丢弃计数账本；对外按契约的 [RejectedDatagramCounter] 暴露。
  final MutableRejectedCounter _rejected = MutableRejectedCounter();

  @override
  RejectedDatagramCounter get rejected => _rejected;

  UdpChannel? _channel;
  Timer? _announceTimer;
  Timer? _sweepTimer;
  StreamController<AnnouncePacket>? _incoming;
  Future<void>? _starting;
  bool _running = false;
  bool _degradedSendOnly = false;
  String _degradedReason = '';

  /// 最近一次公告的发送报告，供排障。
  SendReport? lastSendReport;

  /// 当前是否在跑。
  bool get isRunning => _running;

  /// 是否降级为「只发不收」（端口被占用时）。
  @override
  bool get isSendOnly => _degradedSendOnly;

  /// 降级原因；未降级为 null。
  @override
  String? get degradedReason => _degradedSendOnly ? _degradedReason : null;

  /// 上下线状态机的只读视图，供 UI 与测试断言。
  PeerActivityTracker get tracker => _tracker;

  @override
  Future<void> start() async {
    if (_running) {
      return;
    }
    final Future<void>? inFlight = _starting;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final Completer<void> gate = Completer<void>();
    _starting = gate.future;
    try {
      await _startInternal();
      _running = true;
    } finally {
      _starting = null;
      if (!gate.isCompleted) {
        gate.complete();
      }
    }
  }

  Future<void> _startInternal() async {
    _incoming ??= StreamController<AnnouncePacket>.broadcast();
    final UdpChannel channel = UdpChannel(
      port: port,
      multicastGroup: _multicast.address.address,
      onDatagram: _handleDatagram,
      onError: (Object error, StackTrace? stackTrace) {
        // 收包错误不静默：计数账本里留痕，由 rejected 暴露给 UI。
        _rejected.recordMalformed('通道错误: $error');
      },
    );
    try {
      await channel.bind();
      _channel = channel;
      _degradedSendOnly = false;
      _degradedReason = '';
    } on LanFileException catch (error) {
      // 端口被占用：降级为只发不收，并记录原因，绝不崩。
      _degradedSendOnly = true;
      _degradedReason = error.message;
      _channel = null;
      // 只发也需要一个 socket；用一个临时通道绑 0（系统分配）来发包。
      final UdpChannel sendOnly = UdpChannel(
        port: 0,
        multicastGroup: _multicast.address.address,
        onDatagram: null,
        onError: (Object e, StackTrace? s) {
          _rejected.recordMalformed('降级通道错误: $e');
        },
      );
      try {
        await sendOnly.bind();
        _channel = sendOnly;
      } on LanFileException {
        _channel = null;
      }
    }
    _scheduleAnnounce();
    _sweepTimer = Timer.periodic(
      LanFileConstants.announceIntervalServing,
      (_) => _sweepAndEmit(),
    );
  }

  @override
  Future<void> stop() async {
    if (!_running) {
      return;
    }
    _running = false;
    _announceTimer?.cancel();
    _announceTimer = null;
    _sweepTimer?.cancel();
    _sweepTimer = null;
    final UdpChannel? channel = _channel;
    _channel = null;
    await channel?.close();
    final StreamController<AnnouncePacket>? controller = _incoming;
    if (controller != null) {
      await controller.close();
      _incoming = null;
    }
    _tracker.clear();
  }

  @override
  AnnouncePacket buildPacket() {
    final int shareCount = shareCountProvider.shareCount;
    final String mode = shareCount > 0 ? 'serving' : 'idle';
    final AnnouncePacket unsigned = AnnouncePacket(
      version: LanFileConstants.protocolVersion,
      peerId: identity.peerId,
      name: nameReader?.call() ?? name,
      avatarHash: avatarHashReader?.call() ?? avatarHash,
      port: serverPort,
      ip: localIpReader?.call() ?? localIp,
      shareCount: shareCount,
      capabilities: capabilities,
      mode: mode,
      timestamp: _clock().toUtc().millisecondsSinceEpoch,
      signature: '',
    );
    return unsigned;
  }

  /// 真正广播出去的签名版公告。
  ///
  /// 契约允许 [buildPacket] 返回未签名形态（UI 预览不需要签名），
  /// 而 Ed25519 只能异步签，所以上线包一律走这里。
  @override
  Future<AnnouncePacket> buildSignedPacket() async {
    final AnnouncePacket unsigned = buildPacket();
    final Uint8List payload = Uint8List.fromList(unsigned.signableBytes());
    final Uint8List signature = await identity.sign(payload);
    return unsigned.withSignature(_encodeBase64Url(signature));
  }

  @override
  Stream<AnnouncePacket> watchIncoming() {
    _incoming ??= StreamController<AnnouncePacket>.broadcast();
    return _incoming!.stream;
  }

  @override
  Future<void> probe() async {
    final UdpChannel? channel = _channel;
    if (channel == null) {
      return;
    }
    final Uint8List frame = encodeProbeFrame(
      peerId: identity.peerId,
      timestamp: _clock().toUtc().millisecondsSinceEpoch,
    );
    channel.broadcast(frame);
  }

  /// 已 join 组播的网卡地址（字符串形式），供排障与测试断言。
  List<String> get debugJoinedInterfaces =>
      _channel?.joinedInterfaces
          .map((InternetAddress a) => a.address)
          .toList(growable: false) ??
      const <String>[];

  /// 把一段已编码字节投递到指定端口（测试与定向 probe 用）。
  ///
  /// 走真实 socket，不伪造任何网络层。
  bool debugSendTo(Uint8List bytes, int targetPort) {
    final UdpChannel? channel = _channel;
    if (channel == null) {
      return false;
    }
    return channel.sendTo(bytes, InternetAddress.loopbackIPv4, targetPort);
  }

  /// 把一段已编码字节投递到组播组地址（测试用）。
  bool debugSendToMulticast(Uint8List bytes, int targetPort) {
    final UdpChannel? channel = _channel;
    if (channel == null) {
      return false;
    }
    return channel.sendTo(
      bytes,
      InternetAddress(_multicast.address.address),
      targetPort,
    );
  }

  /// 手动发一次公告（测试与「改名后立即生效」用）。
  Future<SendReport?> announceNow() async {
    final UdpChannel? channel = _channel;
    if (channel == null) {
      return null;
    }
    final AnnouncePacket signed = await buildSignedPacket();
    final SendReport report = channel.broadcast(encodeAnnounceFrame(signed));
    lastSendReport = report;
    return report;
  }

  void _scheduleAnnounce() {
    _announceTimer?.cancel();
    final Duration interval = shareCountProvider.shareCount > 0
        ? LanFileConstants.announceIntervalServing
        : LanFileConstants.announceIntervalIdle;
    _announceTimer = Timer(interval, () async {
      if (!_running) {
        return;
      }
      await announceNow();
      _scheduleAnnounce();
    });
    // 立即先发一次，让对方 3 秒内看到（M1 验收要求）。
    unawaited(announceNow());
  }

  void _sweepAndEmit() {
    _tracker.sweep();
  }

  Future<void> _handleDatagram(
    Uint8List data,
    InternetAddress from,
    int fromPort,
  ) async {
    final DecodedDatagram decoded = decodeDatagram(data);
    switch (decoded) {
      case DecodedInvalid(:final String reason):
        _rejected.recordMalformed(reason);
        return;
      case DecodedProbe(:final ProbeFrame frame):
        await _handleProbe(frame, from, fromPort);
        return;
      case DecodedAnnounce(:final AnnounceEnvelope envelope):
        await _handleAnnounce(envelope, from);
        return;
    }
  }

  Future<void> _handleProbe(
    ProbeFrame frame,
    InternetAddress sourceAddress,
    int sourcePort,
  ) async {
    final PeerId? prober = frame.peerId;
    if (prober == null) {
      _rejected.recordUnknownPeerId('<probe 无 id>');
      return;
    }
    if (prober == identity.peerId) {
      _rejected.recordSelf();
      return;
    }
    if (frame.isReply) {
      // 对端的应答，无需再回。
      return;
    }
    // 收到 probe 立即回一次，不等心跳周期。
    //
    // 定向回复给探询来源：如果这里用 broadcast，包会被发到本机自己的端口，
    // 而探询方监听的是**它的**端口，永远收不到。
    final UdpChannel? channel = _channel;
    if (channel == null) {
      return;
    }
    final AnnouncePacket signed = await buildSignedPacket();
    channel.sendTo(encodeAnnounceFrame(signed), sourceAddress, sourcePort);
  }

  Future<void> _handleAnnounce(
    AnnounceEnvelope envelope,
    InternetAddress sender,
  ) async {
    final AnnouncePacket packet = envelope.packet;

    // 1) 过滤自己（广播/组播会回环）。
    if (packet.peerId == identity.peerId) {
      _rejected.recordSelf();
      return;
    }

    // 2) 取对端公钥。公告里没有公钥字段（契约 fixed），只能靠 peers 表。
    //    未收录的公钥 → 无法验签 → 丢弃并计数，绝不 upsert。
    final Uint8List? publicKey =
        await _resolvePublicKey(packet.peerId) ??
        await unknownPeerKeyResolver?.call(packet, sender);
    if (publicKey == null) {
      _rejected.recordBadSignature(packet.peerId);
      return;
    }

    // 3) 验签。
    final Uint8List signature = _decodeSignature(packet.signature);
    final bool valid =
        signature.isNotEmpty &&
        await _verifier.verify(
          Uint8List.fromList(packet.signableBytes()),
          signature,
          publicKey,
        );
    if (!valid) {
      _rejected.recordBadSignature(packet.peerId);
      return;
    }

    // 4) 验签通过：交给状态机，并 upsert。
    final PeerTouchResult touch = _tracker.touch(packet);
    await _sink.upsertVerifiedPeer(packet);
    _incoming?.add(packet);
    for (final TrackedPeer gone in touch.removed) {
      // 超时移除由 tracker 记录；此处不广播，交由 UI 从 watchPeers 侧感知。
      _rejected._remember('超时移除: ${gone.packet.peerId.value}');
    }
  }

  /// 公钥来源：默认从 peers 表注入；未注入则返回 null（→ 丢弃）。
  Future<Uint8List?> _resolvePublicKey(PeerId peerId) async {
    final PublicKeyLookup? lookup = publicKeyLookup;
    if (lookup == null) {
      return null;
    }
    return lookup.findPublicKey(peerId);
  }

  /// 公钥查找表；由 App 用 store 支撑实现后挂载。
  ///
  /// 未接线时 resolvePublicKey 一律返回 null，于是**所有公告都会验签失败
  /// 并被丢弃**——这是契约写死的安全默认，不是缺陷。
  @override
  set publicKeyLookup(PublicKeyLookup? lookup) {
    _publicKeyLookup = lookup;
  }

  /// 当前公钥查找表；未接线为 null。
  PublicKeyLookup? get publicKeyLookup => _publicKeyLookup;

  PublicKeyLookup? _publicKeyLookup;
  Future<Uint8List?> Function(AnnouncePacket, InternetAddress)?
  unknownPeerKeyResolver;

  /// 验签通过的公告落库口子；未接线为 no-op。
  @override
  set peerSink(PeerUpsertSink? sink) {
    _sink = sink ?? const NoopPeerUpsertSink();
  }

  /// 当前落库口子。
  PeerUpsertSink get peerSink => _sink;

  Uint8List _decodeSignature(String text) {
    if (text.isEmpty) {
      return Uint8List(0);
    }
    final int remainder = text.length % 4;
    final String padded = remainder == 0 ? text : text + '=' * (4 - remainder);
    try {
      return Uint8List.fromList(base64Url.decode(padded));
    } on FormatException {
      return Uint8List(0);
    }
  }
}

/// 分享数量的来源；由 share 服务实现。
abstract interface class ShareCountProvider {
  int get shareCount;
}

/// 无分享时的默认来源（未接线时用）。
final class ZeroShareCountProvider implements ShareCountProvider {
  const ZeroShareCountProvider();

  @override
  int get shareCount => 0;
}

/// base64url，**不带** `=` 填充。
String _encodeBase64Url(Uint8List bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');
