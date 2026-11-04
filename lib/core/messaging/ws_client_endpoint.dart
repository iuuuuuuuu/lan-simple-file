// SPDX-License-Identifier: GPL-3.0-only

/// WS 客户端端点：连接对端、断线自动重连（指数退避，上限 30s）。
///
/// 重连循环的设计要点：
/// - 重连是后台自驱的：await [connect] 只等首次连上；
/// - 每次断开都重走 hello 握手，上层靠 [onLinkUp] 重新补拉，
///   这样离线期间对端新增的消息不会漏（协议 6.4 的双向补拉）；
/// - [dispose] 之后不再重连，等待中的退避定时器会被取消。
library;

import 'dart:async';

import 'package:web_socket_channel/io.dart';

import '../contracts/contracts.dart';
import 'ws_hub.dart';
import 'ws_server_endpoint.dart' show kWsPath;

/// 一条到对端的持久 WS 客户端（含自动重连）。
final class WsClientEndpoint {
  WsClientEndpoint({
    required this.host,
    required this.port,
    required this.localPeerId,
    required this.localName,
    required this.localAvatarHash,
    required this.localCapabilities,
    ReconnectBackoff? backoff,
    this.connectTimeout = const Duration(seconds: 5),
    this.onLinkUp,
    this.onLinkDown,
    this.onReconnectScheduled,
    this.headersReader,
  }) : _backoff = backoff ?? ReconnectBackoff();

  final String host;
  final int port;
  final PeerId localPeerId;
  final String localName;
  final String localAvatarHash;
  final Set<String> localCapabilities;
  final ReconnectBackoff _backoff;
  final Duration connectTimeout;
  final Future<Map<String, String>> Function()? headersReader;

  /// 新链路握手完成后回调（上层在此触发双向补拉）。
  final Future<void> Function(WsLink link)? onLinkUp;

  /// 链路断开回调。
  final void Function(WsLink link)? onLinkDown;

  /// 安排了下次重连（测试据此断言退避生效，不必真等 30s）。
  final void Function(Duration delay)? onReconnectScheduled;

  WsLink? _link;
  Timer? _retryTimer;
  bool _disposed = false;
  bool _connecting = false;

  /// 当前链路；未连接时为 null。
  WsLink? get link => _link;

  bool get isConnected => _link != null && !_link!.isClosed;

  /// 当前连续失败次数。
  int get attempts => _backoff.attempt;

  /// 目标地址。
  Uri get uri => Uri(scheme: 'ws', host: host, port: port, path: kWsPath);

  /// 发起连接并等待首次握手完成。
  ///
  /// 首次失败直接抛错（调用方需要知道对端不可达）；
  /// 成功之后的重连由后台自驱，不再抛给任何 await 点。
  Future<WsLink> connect() async {
    final WsLink? existing = _link;
    if (existing != null && !existing.isClosed) return existing;

    // 直接让 connect() 持有失败语义：由 _attemptOnce 返回建立的链路或抛错。
    // 之前用一个中间 Completer 转手，失败路径里 completer 会被清引用，
    // 调用方最后拿到的是一个永不完成的 future（表现为干等到超时）。
    // 首次连接失败必须同步地抛给调用方，重连才走后台定时器。
    final WsLink? link = await _attemptOnce(awaitInitial: true);
    if (link == null) {
      throw LanFileException(LanFileErrorCode.network, '连接 $host:$port 失败');
    }
    return link;
  }

  /// 停掉重连并关闭当前链路。
  Future<void> dispose() async {
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    final WsLink? link = _link;
    _link = null;
    if (link != null) await link.close(reason: 'client disposed');
  }

  /// 尝试连接一次。
  ///
  /// 返回建好的链路；失败时返回 null（awaitInitial 为 true 时改为抛出），
  /// 并把重连定时器排好。返回值语义比中间 Completer 可靠得多：
  /// 之前用 Completer 转手，失败路径清掉引用后调用方拿到的是永不完成的 future。
  Future<WsLink?> _attemptOnce({required bool awaitInitial}) async {
    if (_disposed || _connecting) return _link;
    _connecting = true;
    IOWebSocketChannel? channel;
    try {
      channel = IOWebSocketChannel.connect(
        uri,
        headers: await headersReader?.call(),
        connectTimeout: connectTimeout,
        pingInterval: const Duration(seconds: 20),
      );
      // 不能用 await channel.ready：实测连接被拒时它既不完成也不抛错
      // （底层把 TimeoutException 混进 stream 后就不再推进 ready），
      // 于是调用方会一直挂着到测试超时。
      // 改为与 stream 的终止事件竞争：先到者决定结果。
      final StreamSubscription<Object?> alreadyListening =
          await _awaitReadyOrStreamEnd(channel, connectTimeout);
      final WsLink link = WsLink(
        transport: _ChannelWsTransport(channel, alreadyListening),
        localPeerId: localPeerId,
        localName: localName,
        localAvatarHash: localAvatarHash,
        localCapabilities: localCapabilities,
      );
      link.start();
      link.sendHello();
      await link.handshake.timeout(connectTimeout);
      _link = link;
      _backoff.reset();
      _connecting = false;
      unawaited(link.closed.whenComplete(() => _onClosed(link)));
      final Future<void> Function(WsLink)? up = onLinkUp;
      if (up != null) await up(link);
      return link;
    } on Object catch (error) {
      _connecting = false;
      try {
        await channel?.sink.close();
      } on Object {
        // 关闭一个从未连上的通道会失败，属预期。
      }
      final Duration delay = _backoff.recordFailure();
      onReconnectScheduled?.call(delay);
      if (awaitInitial) {
        // 首次连接失败：如实抛出，调用方要知道对端不可达。
        throw LanFileException(
          LanFileErrorCode.network,
          '连接 $host:$port 失败',
          cause: error,
        );
      }
      _scheduleRetry(delay);
      return null;
    }
  }

  void _onClosed(WsLink link) {
    if (_disposed) return;
    if (identical(_link, link)) _link = null;
    onLinkDown?.call(link);
    final Duration delay = _backoff.recordFailure();
    onReconnectScheduled?.call(delay);
    _scheduleRetry(delay);
  }

  /// 等待通道就绪，但把「stream 提前结束」也算作失败。
  ///
  /// 只 await ready 会漏掉「连接被拒」：实测那种情况下 ready 既不完成也不抛错，
  /// 底层只把错误丢进 stream，调用方会一直挂到测试超时。
  /// 因此这里让 ready 与 stream 的终止事件竞速。
  ///
  /// **不要 cancel 那个监听**：IOWebSocketChannel 的 stream 是单订阅的，
  /// cancel 掉之后 WsLink 就再也收不到 hello 与业务帧
  /// （表现为「握手前链路已断开」）。成功路径上把这个订阅转交给 WsLink 复用。
  Future<StreamSubscription<Object?>> _awaitReadyOrStreamEnd(
    IOWebSocketChannel channel,
    Duration timeout,
  ) async {
    final Completer<Never> aborted = Completer<Never>();
    final StreamSubscription<Object?> probe = channel.stream.listen(
      (Object? _) {},
      onError: (Object error, StackTrace stackTrace) {
        if (!aborted.isCompleted) aborted.completeError(error, stackTrace);
      },
      onDone: () {
        if (!aborted.isCompleted) {
          aborted.completeError(
            const LanFileException(LanFileErrorCode.network, '连接在就绪前被关闭'),
          );
        }
      },
    );

    try {
      await Future.any<void>(<Future<void>>[
        channel.ready,
        aborted.future,
        Future<void>.delayed(timeout).then((_) {
          throw LanFileException(LanFileErrorCode.network, '连接 $host:$port 超时');
        }),
      ]);
    } on Object {
      await probe.cancel();
      rethrow;
    }
    return probe;
  }

  void _scheduleRetry(Duration delay) {
    if (_disposed) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (_disposed || _connecting) return;
      unawaited(_attemptOnce(awaitInitial: false));
    });
  }
}

/// 把 web_socket_channel 的通道包成 [WsTransport]。
///
/// [existing] 是就绪判定阶段已经建立的那个订阅。
/// IOWebSocketChannel 的 stream 为单订阅，若在这里重新 listen 会抛
/// StateError: Stream has already been listened to；
/// 因此把已有订阅包装成一个可再次被监听的广播流，交给 WsLink。
final class _ChannelWsTransport implements WsTransport {
  _ChannelWsTransport(this._channel, StreamSubscription<Object?> existing)
    : _bridge = StreamController<Object?>.broadcast() {
    existing.onData(_bridge.add);
    existing.onError((Object error, StackTrace stackTrace) {
      _bridge.addError(error, stackTrace);
    });
    existing.onDone(_bridge.close);
  }

  final IOWebSocketChannel _channel;
  final StreamController<Object?> _bridge;

  @override
  Stream<Object?> get stream => _bridge.stream;

  @override
  void add(Object? data) => _channel.sink.add(data);

  @override
  Future<void> close([int? code, String? reason]) =>
      _channel.sink.close(code, reason);
}
