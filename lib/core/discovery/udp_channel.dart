// SPDX-License-Identifier: GPL-3.0-only

/// UDP 通道：广播与组播的双向收发，含多网卡枚举与绑定失败上报。
///
/// 一个节点在同一个 UDP 端口上做四件事：
///
/// 1. 绑定 `0.0.0.0:<port>` 收包（广播与组播都落到这个 socket）；
/// 2. 对**每一块可用网卡**分别发广播到 `255.255.255.255`；
/// 3. 在每块网卡上 joinMulticast 后向 `239.255.77.77` 发送；
/// 4. 组播接收同样走绑定的那个 socket（join 到底是 socket 级操作）。
///
/// 多网卡是硬需求：只从 `0.0.0.0` 发一次时，很多系统只挑默认路由网卡出包，
/// 接在第二块网卡上的机器永远收不到。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:lan_simple_file/core/contracts/contracts.dart';

import '../diagnostics/network_log.dart';
import '../net/lan_interfaces.dart';

/// 一次发送的结果，用于排障与测试断言。
final class SendReport {
  SendReport();

  /// 广播成功发出的次数（每块网卡一次）。
  int broadcastTargets = 0;

  /// 组播成功发出的次数。
  int multicastTargets = 0;

  /// 成功提交给系统的字节数。
  int bytesSent = 0;

  /// 逐条失败原因（不吞异常，留证据）。
  final List<String> failures = <String>[];

  /// 至少有一路发出去了。
  bool get delivered => broadcastTargets + multicastTargets > 0;

  @override
  String toString() =>
      'SendReport(broadcast=$broadcastTargets, multicast=$multicastTargets, '
      'bytes=$bytesSent, failures=${failures.length})';
}

/// 收包回调。
///
/// 携带来源地址与端口：probe 必须**定向回复给探询方**，而不是再广播一次
/// ——广播回到的是本机自己的端口，探询方根本收不到。
typedef DatagramHandler = void Function(
  Uint8List data,
  InternetAddress from,
  int fromPort,
);

/// 错误上报回调；默认写 stderr，绝不静默吞。
typedef UdpErrorReporter = void Function(Object error, StackTrace? stackTrace);

/// UDP 通道。
///
/// 生命周期：`bind()` → 收发 → `close()`。重复 bind 会抛 [LanFileException]。
final class UdpChannel {
  UdpChannel({
    required this.port,
    this.bindAddress,
    this.multicastGroup = LanFileConstants.multicastGroup,
    this.broadcastAddress = '255.255.255.255',
    this.onDatagram,
    this.onError,
  });

  /// 监听端口；测试必须能覆盖（同进程双实例互发时用不同端口）。
  final int port;

  /// 绑定地址；默认 [InternetAddress.anyIPv4]。
  final InternetAddress? bindAddress;

  /// 组播组地址字符串。
  final String multicastGroup;

  /// 广播目标地址字符串。
  final String broadcastAddress;

  /// 收到数据报时的回调。
  final DatagramHandler? onDatagram;

  /// 发送/接收错误回调。
  final UdpErrorReporter? onError;

  RawDatagramSocket? _socket;
  List<NetworkInterface> _interfaces = const <NetworkInterface>[];
  final List<InternetAddress> _joinedInterfaces = <InternetAddress>[];
  int _receiveFailures = 0;
  int _sendFailures = 0;
  bool _closed = false;
  bool unexpectedlyEnded = false;

  /// 已绑定则 true。
  bool get isBound => _socket != null;

  /// 实际监听端口。
  int? get boundPort => _socket?.port;

  /// 已 join 组播的网卡地址列表。
  List<InternetAddress> get joinedInterfaces =>
      List<InternetAddress>.unmodifiable(_joinedInterfaces);

  /// 接收侧错误计数（垃圾包不计入，那是丢弃计数的事）。
  int get receiveFailures => _receiveFailures;

  /// 发送侧错误计数。
  int get sendFailures => _sendFailures;

  /// 绑定端口、注册收包回调、在所有可用网卡上 join 组播组。
  ///
  /// 绑定失败抛 [LanFileException]（码 io），由调用方决定降级策略。
  Future<void> bind() async {
    if (_socket != null) {
      throw const LanFileException(LanFileErrorCode.conflict, 'UDP 通道已经绑定');
    }
    final RawDatagramSocket socket;
    NetworkLog.record('udp.bind_attempt', {
      'address': (bindAddress ?? InternetAddress.anyIPv4).address,
      'port': port,
    });
    try {
      socket = await RawDatagramSocket.bind(
        bindAddress ?? InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
        reusePort: false,
      );
    } on SocketException catch (error) {
      NetworkLog.record('udp.bind_error', NetworkLog.errorFields(error));
      throw LanFileException(
        LanFileErrorCode.io,
        'UDP 绑定 :$port 失败',
        cause: error,
      );
    }
    socket.broadcastEnabled = true;
    socket.multicastLoopback = true;
    socket.multicastHops = 1;
    _socket = socket;
    NetworkLog.record('udp.bound', {
      'address': socket.address.address,
      'port': socket.port,
    });
    socket.listen(
      _handleEvent,
      onError: (Object error, StackTrace stackTrace) {
        _receiveFailures++;
        _report(error, stackTrace);
      },
      onDone: () {
        NetworkLog.record('udp.done', {'expected': _closed, 'port': port});
        if (!_closed) {
          unexpectedlyEnded = true;
          _receiveFailures++;
          _report(StateError('UDP socket 意外结束'), null);
        }
      },
    );
    _interfaces = await _listInterfaces();
    NetworkLog.record('udp.interfaces', {
      'interfaces': [
        for (final i in _interfaces)
          {
            'name': i.name,
            'index': i.index,
            'addresses': i.addresses.map((a) => a.address).toList(),
          },
      ],
    });
    _joinMulticastOnAllInterfaces(socket);
  }

  /// 向所有网卡的广播地址与组播组各发一份。
  SendReport broadcast(Uint8List bytes) {
    final SendReport report = SendReport();
    final RawDatagramSocket? socket = _socket;
    if (socket == null) {
      report.failures.add('通道未绑定，无法发送');
      return report;
    }
    final InternetAddress multicast = InternetAddress(multicastGroup);
    final InternetAddress broadcast = InternetAddress(broadcastAddress);

    final List<NetworkInterface> targets = _interfaces.isEmpty
        ? <NetworkInterface>[]
        : _interfaces;
    if (targets.isEmpty) {
      if (Platform.isAndroid) {
        report.failures.add('未连接 Wi-Fi 或以太网，暂不发送局域网公告');
        return report;
      }
      // 没有任何非环回网卡（离线机器/受限沙箱）：仍尝试一次，不让局域网静默失联。
      _sendOne(socket, bytes, broadcast, report, '广播');
      _sendOne(socket, bytes, multicast, report, '组播');
      return report;
    }
    for (final NetworkInterface interface in targets) {
      _sendOne(socket, bytes, broadcast, report, '广播(${interface.name})');
      _sendOne(socket, bytes, multicast, report, '组播(${interface.name})');
    }
    return report;
  }

  void _sendOne(
    RawDatagramSocket socket,
    Uint8List bytes,
    InternetAddress target,
    SendReport report,
    String label,
  ) {
    try {
      final int written = socket.send(bytes, target, port);
      NetworkLog.record('udp.send', {
        'target': target.address,
        'port': port,
        'label': label,
        'bytes': bytes.length,
        'written': written,
        'binding': socket.address.address,
      });
      if (written <= 0) {
        _sendFailures++;
        report.failures.add('$label 系统未接收（返回 $written）');
        return;
      }
      report.bytesSent += written;
      if (target.isMulticast) {
        report.multicastTargets++;
      } else {
        report.broadcastTargets++;
      }
    } on SocketException catch (error) {
      _sendFailures++;
      report.failures.add('$label 失败: ${error.message}');
      NetworkLog.record('udp.send_error', {
        'target': target.address,
        'port': port,
        'label': label,
        ...NetworkLog.errorFields(error),
      });
    }
  }

  /// 向一个具体地址单播发送（测试与定向 probe 用）。
  bool sendTo(Uint8List bytes, InternetAddress address, int targetPort) {
    final RawDatagramSocket? socket = _socket;
    if (socket == null) {
      _sendFailures++;
      return false;
    }
    try {
      final written = socket.send(bytes, address, targetPort);
      NetworkLog.record('udp.unicast', {
        'target': address.address,
        'port': targetPort,
        'bytes': bytes.length,
        'written': written,
      });
      return written > 0;
    } on SocketException catch (error) {
      _sendFailures++;
      NetworkLog.record('udp.unicast_error', {
        'target': address.address,
        'port': targetPort,
        ...NetworkLog.errorFields(error),
      });
      _report(error, null);
      return false;
    }
  }

  /// 关闭通道；幂等。
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    NetworkLog.record('udp.close', {'port': port});
    final RawDatagramSocket? socket = _socket;
    _socket = null;
    if (_joinedInterfaces.isNotEmpty) {
      try {
        socket?.leaveMulticast(InternetAddress(multicastGroup));
      } on SocketException {
        // 关闭阶段不因 leave 失败而阻断，socket 随后整体 close。
      }
    }
    _joinedInterfaces.clear();
    _interfaces = const <NetworkInterface>[];
    socket?.close();
  }

  void _handleEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) {
      return;
    }
    final RawDatagramSocket? socket = _socket;
    if (socket == null) {
      return;
    }
    final Datagram? datagram = socket.receive();
    if (datagram == null) {
      return;
    }
    NetworkLog.record('udp.receive', {
      'source': datagram.address.address,
      'port': datagram.port,
      'bytes': datagram.data.length,
    });
    try {
      onDatagram?.call(datagram.data, datagram.address, datagram.port);
    } catch (error, stackTrace) {
      _receiveFailures++;
      _report(error, stackTrace);
    }
  }

  Future<List<NetworkInterface>> _listInterfaces() async {
    try {
      final List<NetworkInterface> all = await lanInterfaces(
        await NetworkInterface.list(
          includeLoopback: false,
          type: InternetAddressType.IPv4,
        ),
      );
      return all
          .where(
            (NetworkInterface i) =>
                i.addresses.any((InternetAddress a) => !a.isLoopback),
          )
          .toList(growable: false);
    } on SocketException catch (error) {
      _report(error, null);
      return const <NetworkInterface>[];
    }
  }

  void _joinMulticastOnAllInterfaces(RawDatagramSocket socket) {
    final InternetAddress group = InternetAddress(multicastGroup);
    for (final NetworkInterface interface in _interfaces) {
      try {
        socket.joinMulticast(group, interface);
        NetworkLog.record('udp.join', {
          'group': multicastGroup,
          'interface': interface.name,
        });
        if (interface.addresses.isNotEmpty) {
          _joinedInterfaces.add(interface.addresses.first);
        }
      } on SocketException catch (error) {
        // 单块网卡 join 失败不拖垮整个通道：记录并继续。
        _report(error, null);
      }
    }
    if (_joinedInterfaces.isEmpty && !Platform.isAndroid) {
      try {
        socket.joinMulticast(group);
        _joinedInterfaces.add(InternetAddress.anyIPv4);
      } on SocketException catch (error) {
        _report(error, null);
      }
    }
  }

  void _report(Object error, StackTrace? stackTrace) {
    NetworkLog.record('udp.channel_error', {
      'port': port,
      ...NetworkLog.errorFields(error),
    });
    final UdpErrorReporter? handler = onError;
    if (handler != null) {
      handler(error, stackTrace);
      return;
    }
    stderr.writeln('[discovery/udp] $error');
    if (stackTrace != null) {
      stderr.writeln(stackTrace);
    }
  }
}
