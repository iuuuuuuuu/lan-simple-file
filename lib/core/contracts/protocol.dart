// SPDX-License-Identifier: GPL-3.0-only

/// 线上协议契约：公告、offer、事件帧的编解码与字段名冻结于此。
///
/// 字段名一旦发布不得更改；新增字段必须可选且带默认值。
library;

import 'dart:convert';

import 'errors.dart';
import 'types.dart' hide OfferOrigin;
export 'types.dart' show OfferOrigin;

/// 发现公告，v2。
final class AnnouncePacket {
  const AnnouncePacket({
    required this.version,
    required this.peerId,
    required this.name,
    required this.avatarHash,
    required this.port,
    required this.ip,
    required this.shareCount,
    required this.capabilities,
    required this.mode,
    required this.timestamp,
    required this.signature,
  });

  /// 从 wire 值域解析；缺字段或类型不符抛 LanFileException。
  factory AnnouncePacket.fromJson(Map<String, Object?> json) {
    final version = json['v'];
    final id = json['id'];
    final port = json['port'];
    final ts = json['ts'];
    final sig = json['sig'];
    if (version is! int ||
        id is! String ||
        port is! int ||
        ts is! int ||
        sig is! String) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        '公告缺少必需字段',
      );
    }
    final peerId = PeerId.tryParse(id);
    if (peerId == null) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        '公告中的 peerId 非法',
      );
    }
    return AnnouncePacket(
      version: version,
      peerId: peerId,
      name: (json['name'] as String?) ?? '',
      avatarHash: (json['av'] as String?) ?? '',
      port: port,
      ip: (json['ip'] as String?) ?? '',
      shareCount: (json['shareCount'] as int?) ?? 0,
      capabilities: ((json['caps'] as List<Object?>?) ?? const [])
          .whereType<String>()
          .toSet(),
      mode: (json['mode'] as String?) ?? 'idle',
      timestamp: ts,
      signature: sig,
    );
  }

  final int version;
  final PeerId peerId;
  final String name;
  final String avatarHash;
  final int port;
  final String ip;
  final int shareCount;
  final Set<String> capabilities;
  final String mode;
  final int timestamp;
  final String signature;

  /// 参与签名的规范化 JSON：除 sig 外全部字段，键序固定。
  Map<String, Object?> signablePayload() => <String, Object?>{
        'v': version,
        'id': peerId.value,
        'name': name,
        'av': avatarHash,
        'port': port,
        'ip': ip,
        'shareCount': shareCount,
        'caps': capabilities.toList()..sort(),
        'mode': mode,
        'ts': timestamp,
      };

  /// 线上形式（含 sig）。
  Map<String, Object?> toJson() => <String, Object?>{
        ...signablePayload(),
        'sig': signature,
      };

  /// 规范化字节，供验签使用。
  List<int> signableBytes() => utf8.encode(jsonEncode(signablePayload()));

  /// 带上新的签名字段。
  AnnouncePacket withSignature(String newSignature) => AnnouncePacket(
        version: version,
        peerId: peerId,
        name: name,
        avatarHash: avatarHash,
        port: port,
        ip: ip,
        shareCount: shareCount,
        capabilities: capabilities,
        mode: mode,
        timestamp: timestamp,
        signature: newSignature,
      );
}

/// offer 的生命周期状态。
enum OfferStatus { pending, accepted, rejected, expired, cancelled }
/// WebSocket 事件帧：节点间实时通道的线上格式。
///
/// 每一帧都是 `{t: <类型>, ...}`。类型一旦发布不得更改语义，只能新增。
final class WsFrame {
  const WsFrame(this.type, this.payload);

  /// 从 wire 值域解析；t 缺失抛 invalidArgument。
  factory WsFrame.fromJson(Map<String, Object?> json) {
    final Object? t = json['t'];
    if (t is! String || t.isEmpty) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        'WS 帧缺少 t 字段',
      );
    }
    final Map<String, Object?> rest = Map<String, Object?>.from(json)..remove('t');
    return WsFrame(t, rest);
  }

  final String type;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => <String, Object?>{'t': type, ...payload};

  /// 已知帧类型常量，实现方不得自造字符串字面量。
  static const String hello = 'hello';
  static const String msg = 'msg';
  static const String ack = 'ack';
  static const String revoke = 'revoke';
  static const String offer = 'offer';
  static const String offerDecision = 'offer-decision';
  static const String presence = 'presence';
  static const String pull = 'pull';
  static const String progress = 'progress';
  static const String typing = 'typing';

  /// 本机支持的帧类型全集，握手时用于协商。
  static const Set<String> all = <String>{
    hello,
    msg,
    ack,
    revoke,
    offer,
    offerDecision,
    presence,
    pull,
    progress,
    typing,
  };
}
