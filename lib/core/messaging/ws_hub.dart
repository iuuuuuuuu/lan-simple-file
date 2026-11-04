// SPDX-License-Identifier: GPL-3.0-only

/// WS 链路层的公共底座：传输抽象、收发封装、握手状态、重连退避策略。
///
/// 为什么自定义 [WsTransport] 而不是直接用 web_socket_channel 的 WebSocketChannel：
/// 服务端是 dart:io 的 WebSocketTransformer.upgrade 之后拿到的 WebSocket，
/// 而 web_socket_channel 只提供客户端适配（IOWebSocketChannel）。
/// 要让两侧共用一份 WsLink，只需抽象出「收流 / 发消息 / 关闭」三件事，
/// 不必去实现 WebSocketChannel + WebSocketSink + StreamChannel 三个接口——
/// 那样写出来的适配器大半是空壳，反而更难维护。
library;

import 'dart:async';

import '../contracts/contracts.dart';
import 'message_sync.dart';

/// WS 传输层的最小接口。
abstract interface class WsTransport {
  /// 入站消息流；每项是一帧文本（本协议只用文本帧）。
  Stream<Object?> get stream;

  /// 发送一帧文本。
  void add(Object? data);

  /// 关闭连接；[code] 缺省为正常关闭。
  Future<void> close([int? code, String? reason]);
}

/// 握手后确定的对端身份。
final class RemoteIdentity {
  const RemoteIdentity({
    required this.peerId,
    required this.name,
    required this.avatarHash,
    required this.capabilities,
  });

  final PeerId peerId;
  final String name;
  final String avatarHash;
  final Set<String> capabilities;

  /// 对端是否声明支持某帧类型。
  bool supports(String frameType) => capabilities.contains(frameType);
}

/// 一条已建立的 WS 链路。
///
/// 生命周期：`start -> hello 互换 -> handshake 完成 -> 业务帧`；
/// 任一端关闭或网络断开时 [closed] 完成，上层据此决定是否重连。
final class WsLink {
  WsLink({
    required WsTransport transport,
    required this.localPeerId,
    required this.localName,
    required this.localAvatarHash,
    required this.localCapabilities,
  // ignore: prefer_initializing_formals
  }) : _transport = transport;

  final WsTransport _transport;

  final PeerId localPeerId;
  final String localName;
  final String localAvatarHash;
  final Set<String> localCapabilities;

  final StreamController<WsFrame> _frames =
      StreamController<WsFrame>.broadcast();
  final Completer<void> _closed = Completer<void>();
  final Completer<RemoteIdentity> _handshaken =
      Completer<RemoteIdentity>();

  StreamSubscription<Object?>? _subscription;
  RemoteIdentity? _remote;
  bool _disposed = false;

  /// 握手中确定的对端身份；握手完成前为 null。
  RemoteIdentity? get remote => _remote;

  /// 握手完成信号。
  Future<RemoteIdentity> get handshake => _handshaken.future;

  /// 收到除 hello 以外的所有帧。
  Stream<WsFrame> get frames => _frames.stream;

  /// 链路关闭信号（正常关闭或异常断开都会完成，不会悬挂）。
  Future<void> get closed => _closed.future;

  bool get isClosed => _closed.isCompleted;

  /// 开始收帧。握手阶段的 hello 由本方法内部消费，不投递给上层。
  void start() {
    if (_subscription != null) return;
    _subscription = _transport.stream.listen(
      _onRaw,
      onError: (Object error, StackTrace stackTrace) => _finish(),
      onDone: _finish,
      cancelOnError: false,
    );
  }

  /// 主动发 hello 帧（两端都要发，见协议 6.4）。
  void sendHello() {
    send(WsFrame(WsFrame.hello, <String, Object?>{
      'id': localPeerId.value,
      'name': localName,
      'av': localAvatarHash,
      'caps': (localCapabilities.toList()..sort()),
    }));
  }

  /// 发送一个帧；链路已关闭时返回 false，由上层补发队列兜底。
  bool send(WsFrame frame) {
    if (isClosed || _disposed) return false;
    try {
      _transport.add(encodeFrame(frame));
      return true;
    } on Object {
      // 写失败等价于断开；不在这里抛，交给 closed 信号统一处理。
      _finish();
      return false;
    }
  }

  void _onRaw(Object? raw) {
    if (raw is! String) {
      // 本项目只用文本帧；收到二进制帧视为协议错误，直接断链。
      unawaited(close(reason: 'protocol error'));
      return;
    }
    final WsFrame frame;
    try {
      frame = decodeFrame(raw);
    } on LanFileException {
      // 单帧解析失败不影响链路上其它帧；但握手前的坏帧说明对端不可信。
      if (_remote == null) unawaited(close(reason: 'protocol error'));
      return;
    }
    if (frame.type == WsFrame.hello) {
      _acceptHello(frame);
      return;
    }
    if (_remote == null) {
      // 未握手先发业务帧：不接受。
      unawaited(close(reason: 'protocol error'));
      return;
    }
    if (!_frames.isClosed) _frames.add(frame);
  }

  void _acceptHello(WsFrame frame) {
    if (_remote != null) return; // 重复 hello 忽略，不覆盖已确认身份。
    final Object? idRaw = frame.payload['id'];
    final PeerId? id = idRaw is String ? PeerId.tryParse(idRaw) : null;
    if (id == null) {
      unawaited(close(reason: 'bad hello'));
      return;
    }
    final Object? capsRaw = frame.payload['caps'];
    _remote = RemoteIdentity(
      peerId: id,
      name: (frame.payload['name'] as String?) ?? '',
      avatarHash: (frame.payload['av'] as String?) ?? '',
      capabilities: capsRaw is List<Object?>
          ? capsRaw.whereType<String>().toSet()
          : <String>{},
    );
    if (!_handshaken.isCompleted) _handshaken.complete(_remote!);
  }

  /// 关闭链路。幂等，重复调用安全。
  Future<void> close({String? reason}) async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _transport.close(1000, reason);
    } on Object {
      // 对端已断开时关闭半开 socket 会失败，不影响本地状态收敛。
    }
    await _subscription?.cancel();
    _finish();
  }

  void _finish() {
    if (_closed.isCompleted) return;
    if (!_handshaken.isCompleted) {
      _handshaken.completeError(
        const LanFileException(LanFileErrorCode.network, '握手前链路已断开'),
      );
      // 消费掉错误，避免无人 await 时变成未捕获异常。
      _handshaken.future.ignore();
    }
    if (!_frames.isClosed) _frames.close();
    _closed.complete();
  }
}

/// 指数退避重连策略。
///
/// 从 [base] 起按 2 的幂增长，上限 [max]（协议要求 30s）。
/// [reset] 在成功连接后调用：长连接成功过之后偶发断一次，
/// 不该沿用之前退避到 30s 的等待。
final class ReconnectBackoff {
  ReconnectBackoff({
    this.base = const Duration(milliseconds: 200),
    this.max = const Duration(seconds: 30),
  });

  final Duration base;
  final Duration max;

  int _attempt = 0;

  /// 当前已连续失败次数。
  int get attempt => _attempt;

  /// 下一次重连前应等待的时长。
  Duration get nextDelay {
    final int capped = _attempt > 20 ? 20 : _attempt;
    final int micros = base.inMicroseconds * (1 << capped);
    final int limit = max.inMicroseconds;
    return Duration(microseconds: micros > limit ? limit : micros);
  }

  /// 记一次失败，返回本次应等待的时长。
  Duration recordFailure() {
    final Duration delay = nextDelay;
    _attempt++;
    return delay;
  }

  /// 连接成功后清零。
  void reset() {
    _attempt = 0;
  }
}

