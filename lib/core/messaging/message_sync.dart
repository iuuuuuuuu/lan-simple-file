// SPDX-License-Identifier: GPL-3.0-only

/// 消息同步的线上编解码：msg / pull / revoke / ack 四种帧的对称实现。
///
/// 单独抽出来的理由：帧格式是最容易两边写歧的地方，把它收敛成
/// 「对象 <-> Map」的纯函数后，可以脱离网络直接对拍测试，
/// 也让 ws_hub 只关心收发与路由，不关心字段拼装。
///
/// 帧类型常量一律取自契约 WsFrame，本文件不出现裸字符串字面量。
library;

import 'dart:convert';

import '../contracts/contracts.dart';

/// 一条消息的线上形态。
///
/// 字段名与契约 WsFrame.msg 的 payload 一致；body/attach 直接放明文，
/// 不做二次编码——JSON 已经负责转义。
Map<String, Object?> encodeMessage(MessageRecord record) => <String, Object?>{
      'id': record.id,
      'thread': record.threadId,
      'from': record.senderPeerId.value,
      'kind': record.kind.name,
      'hlc': record.hlc.encode(),
      'ts': record.ts.toUtc().millisecondsSinceEpoch,
      'body': record.body,
      'attach': record.attachJson,
      'sig': record.sig,
      if (record.revokedAt != null)
        'revokedAt': record.revokedAt!.toUtc().millisecondsSinceEpoch,
      if (record.revokeReason != null) 'revokeReason': record.revokeReason,
      if (record.editedAt != null)
        'editedAt': record.editedAt!.toUtc().millisecondsSinceEpoch,
    };

/// 解析对端发来的消息；缺字段抛 invalidArgument，绝不静默补默认值。
///
/// 之所以严格：消息一旦用默认值填平，缺 id 或 hlc 的消息会以错误形状入库，
/// 后续补拉与去重都会跟着错，比直接拒绝难查得多。
MessageRecord decodeMessage(Map<String, Object?> json) {
  final String id = _requireString(json, 'id');
  final String thread = _requireString(json, 'thread');
  final String from = _requireString(json, 'from');
  final String kindName = _requireString(json, 'kind');
  final String hlcText = _requireString(json, 'hlc');
  final int ts = _requireInt(json, 'ts');

  final MessageKind kind = MessageKind.values.firstWhere(
    (MessageKind value) => value.name == kindName,
    orElse: () => throw LanFileException(
      LanFileErrorCode.invalidArgument,
      '消息 kind 非法: $kindName',
    ),
  );
  final PeerId sender = PeerId.tryParse(from) ??
      (throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '消息 sender 不是合法 peerId: $from',
      ));
  final Hlc hlc;
  try {
    hlc = Hlc.parse(hlcText);
  } on FormatException catch (error) {
    throw LanFileException(
      LanFileErrorCode.invalidArgument,
      '消息 hlc 非法: $hlcText',
      cause: error,
    );
  }

  return MessageRecord(
    id: id,
    threadId: thread,
    senderPeerId: sender,
    kind: kind,
    hlc: hlc,
    ts: DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true),
    body: (json['body'] as String?) ?? '',
    attachJson: (json['attach'] as String?) ?? '',
    sig: (json['sig'] as String?) ?? '',
    revokedAt: _optionalDate(json['revokedAt']),
    revokeReason: json['revokeReason'] as String?,
    editedAt: _optionalDate(json['editedAt']),
  );
}

/// 补拉请求：thread + 可选 sinceHlc。
///
/// since 为 null 表示「我没有这个线程的任何消息，请给全部」。
Map<String, Object?> encodePull(String threadId, Hlc? since) =>
    <String, Object?>{
      'thread': threadId,
      if (since != null) 'sinceHlc': since.encode(),
    };

/// 解析补拉请求，返回 (threadId, since)。
PullRequest decodePull(Map<String, Object?> payload) {
  final String thread = _requireString(payload, 'thread');
  final Object? sinceRaw = payload['sinceHlc'];
  if (sinceRaw == null) {
    return PullRequest(threadId: thread, since: null);
  }
  if (sinceRaw is! String) {
    throw const LanFileException(
      LanFileErrorCode.invalidArgument,
      'pull 帧的 sinceHlc 必须是字符串',
    );
  }
  final Hlc since;
  try {
    since = Hlc.parse(sinceRaw);
  } on FormatException catch (error) {
    throw LanFileException(
      LanFileErrorCode.invalidArgument,
      'pull 帧的 sinceHlc 非法: $sinceRaw',
      cause: error,
    );
  }
  return PullRequest(threadId: thread, since: since);
}

/// 补拉响应：一段消息列表。
///
/// 不带「是否还有更多」标志：调用方按返回集合里最大 HLC 继续拉，
/// 直到返回空集合为止。这样无需协商页大小，也不依赖对端实现细节。
Map<String, Object?> encodePullResponse(
  String threadId,
  List<MessageRecord> messages,
) =>
    <String, Object?>{
      'thread': threadId,
      'messages': messages.map(encodeMessage).toList(growable: false),
    };

/// 解析补拉响应。
List<MessageRecord> decodePullResponse(Map<String, Object?> payload) {
  final Object? raw = payload['messages'];
  if (raw is! List<Object?>) {
    throw const LanFileException(
      LanFileErrorCode.invalidArgument,
      'pull 响应的 messages 必须是数组',
    );
  }
  return raw
      .map((Object? item) {
        if (item is! Map<String, Object?>) {
          throw const LanFileException(
            LanFileErrorCode.invalidArgument,
            'pull 响应里出现了非对象消息',
          );
        }
        return decodeMessage(item);
      })
      .toList(growable: false);
}

/// 撤回帧：msgId + ts + 可选 reason。
Map<String, Object?> encodeRevoke(
  String messageId,
  DateTime at, {
  String? reason,
}) =>
    <String, Object?>{
      'msgId': messageId,
      'ts': at.toUtc().millisecondsSinceEpoch,
      'reason': ?reason,
    };

/// 解析撤回帧。
RevokeRequest decodeRevoke(Map<String, Object?> payload) {
  final String msgId = _requireString(payload, 'msgId');
  final int ts = _requireInt(payload, 'ts');
  return RevokeRequest(
    messageId: msgId,
    at: DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true),
    reason: payload['reason'] as String?,
  );
}

/// ack 帧：确认已收到哪些消息 id（用于发送侧清理离线队列）。
Map<String, Object?> encodeAck(List<String> messageIds) => <String, Object?>{
      'msgIds': messageIds,
    };

/// 解析 ack 帧。
List<String> decodeAck(Map<String, Object?> payload) {
  final Object? raw = payload['msgIds'];
  if (raw is! List<Object?>) {
    throw const LanFileException(
      LanFileErrorCode.invalidArgument,
      'ack 帧的 msgIds 必须是数组',
    );
  }
  return raw.map((Object? item) {
    if (item is! String) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        'ack 帧的 msgIds 里出现了非字符串',
      );
    }
    return item;
  }).toList(growable: false);
}

/// 解析后的补拉请求。
final class PullRequest {
  const PullRequest({required this.threadId, required this.since});

  final String threadId;
  final Hlc? since;
}

/// 解析后的撤回请求。
final class RevokeRequest {
  const RevokeRequest({
    required this.messageId,
    required this.at,
    this.reason,
  });

  final String messageId;
  final DateTime at;
  final String? reason;
}

/// 把这些帧编码成 JSON 文本（WS 文本帧）。
String encodeFrame(WsFrame frame) => jsonEncode(frame.toJson());

/// 从 WS 文本帧解析；非 JSON 或非对象一律抛 invalidArgument。
WsFrame decodeFrame(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (error) {
    throw LanFileException(
      LanFileErrorCode.invalidArgument,
      'WS 帧不是合法 JSON',
      cause: error,
    );
  }
  if (decoded is! Map<String, Object?>) {
    throw const LanFileException(
      LanFileErrorCode.invalidArgument,
      'WS 帧的顶层必须是 JSON 对象',
    );
  }
  return WsFrame.fromJson(decoded);
}

String _requireString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! String || value.isEmpty) {
    throw LanFileException(
      LanFileErrorCode.invalidArgument,
      '帧缺少必需字段 $key',
    );
  }
  return value;
}

int _requireInt(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! int) {
    throw LanFileException(
      LanFileErrorCode.invalidArgument,
      '帧缺少必需字段 $key 或类型不是整数',
    );
  }
  return value;
}

DateTime? _optionalDate(Object? raw) {
  if (raw == null) return null;
  if (raw is! int) {
    throw const LanFileException(
      LanFileErrorCode.invalidArgument,
      '时间字段必须是毫秒整数',
    );
  }
  return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
}
