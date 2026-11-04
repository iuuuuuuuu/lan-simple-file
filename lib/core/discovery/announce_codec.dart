// SPDX-License-Identifier: GPL-3.0-only

/// 发现层的线上编解码：公告帧、probe 帧、信封的编码与解码。
///
/// 线上只有两种 UDP 载荷：
///
/// ```
/// announce : {"k":"a", ...AnnouncePacket.toJson()}     // 含 sig
/// probe    : {"k":"p", "id":"<本机 peerId>", "ts":<毫秒>}
/// ```
///
/// 信封的 `k` 字段让「一个 socket 上同时收公告与探测」成为可能，
/// 又不必解析两次 JSON。未知 `k` 一律当作垃圾包丢弃并计数，
/// 绝不抛异常打断接收循环。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:lan_simple_file/core/contracts/contracts.dart';

/// 信封类型：公告。
const String kFrameKindAnnounce = 'a';

/// 信封类型：探测请求。
const String kFrameKindProbe = 'p';

/// 探测回包的应答类型（与 probe 同形，便于对端区分「这是应答」）。
const String kFrameKindProbeReply = 'r';

/// 一个已经通过信封解析、但尚未验签的公告。
final class AnnounceEnvelope {
  const AnnounceEnvelope(this.packet, this.rawBytes);

  /// 解析出的公告（sig 尚不可信）。
  final AnnouncePacket packet;

  /// 收到时的原始字节，供排障与计数使用。
  final int rawBytes;
}

/// 解析后的探测帧。
final class ProbeFrame {
  const ProbeFrame({
    required this.peerId,
    required this.timestamp,
    required this.isReply,
  });

  final PeerId? peerId;
  final int timestamp;

  /// 是否是对端对我方 probe 的即时应答。
  final bool isReply;
}

/// 把公告编码成 UDP 载荷字节。
Uint8List encodeAnnounceFrame(AnnouncePacket packet) {
  final Map<String, Object?> envelope = <String, Object?>{
    'k': kFrameKindAnnounce,
    ...packet.toJson(),
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
}

/// 把 probe 编码成 UDP 载荷字节。
Uint8List encodeProbeFrame({
  required PeerId peerId,
  required int timestamp,
  bool isReply = false,
}) {
  final Map<String, Object?> envelope = <String, Object?>{
    'k': isReply ? kFrameKindProbeReply : kFrameKindProbe,
    'id': peerId.value,
    'ts': timestamp,
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
}

/// 解码结果分类：调用方据此决定「验签」「回包」还是「丢弃计数」。
sealed class DecodedDatagram {
  const DecodedDatagram();
}

/// 一条待验签的公告。
final class DecodedAnnounce extends DecodedDatagram {
  const DecodedAnnounce(this.envelope);

  final AnnounceEnvelope envelope;
}

/// 一条探测帧。
final class DecodedProbe extends DecodedDatagram {
  const DecodedProbe(this.frame);

  final ProbeFrame frame;
}

/// 无法解析的载荷；[reason] 用于计数与排障，不含用户可见文案。
final class DecodedInvalid extends DecodedDatagram {
  const DecodedInvalid(this.reason);

  final String reason;
}

/// 解码一个 UDP 载荷。
///
/// 本函数**不抛异常**：任何畸形输入都归为 [DecodedInvalid]，
/// 由接收循环统一丢弃并计数。这是「垃圾包不能打断监听」的硬要求。
DecodedDatagram decodeDatagram(Uint8List bytes) {
  if (bytes.isEmpty) {
    return const DecodedInvalid('空载荷');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    return const DecodedInvalid('不是合法 UTF-8 JSON');
  }
  if (decoded is! Map<String, Object?>) {
    return const DecodedInvalid('顶层不是对象');
  }
  final Object? kind = decoded['k'];
  if (kind is! String) {
    return const DecodedInvalid('缺少信封类型 k');
  }

  switch (kind) {
    case kFrameKindAnnounce:
      try {
        final AnnouncePacket packet = AnnouncePacket.fromJson(decoded);
        return DecodedAnnounce(AnnounceEnvelope(packet, bytes.length));
      } on LanFileException {
        return const DecodedInvalid('公告字段非法');
      }
    case kFrameKindProbe:
    case kFrameKindProbeReply:
      final Object? id = decoded['id'];
      final Object? ts = decoded['ts'];
      if (ts is! int) {
        return const DecodedInvalid('探测帧缺少 ts');
      }
      return DecodedProbe(
        ProbeFrame(
          peerId: id is String ? PeerId.tryParse(id) : null,
          timestamp: ts,
          isReply: kind == kFrameKindProbeReply,
        ),
      );
    default:
      return DecodedInvalid('未知信封类型: $kind');
  }
}
