// SPDX-License-Identifier: GPL-3.0-only

/// 帧编解码测试：对称性、字段严格性、坏帧拒绝。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/messaging/message_sync.dart';

MessageRecord _msg({
  String id = 'p_kzdvvj2umndua:1',
  DateTime? revokedAt,
  String? revokeReason,
}) {
  return MessageRecord(
    id: id,
    threadId: 'd_a_b',
    senderPeerId: PeerId.parse('p_kzdvvj2umndua'),
    kind: MessageKind.text,
    hlc: Hlc(millis: 1767225600000, counter: 3, origin: 'p_kzdvvj2umndua'),
    ts: DateTime.utc(2026, 11, 4, 7, 0, 0),
    body: '你好，世界',
    attachJson: '{}',
    sig: 'sig',
    revokedAt: revokedAt,
    revokeReason: revokeReason,
  );
}

void main() {
  group('消息往返', () {
    test('encode -> decode 保持全部字段（含中文 body）', () {
      final MessageRecord original = _msg();
      final MessageRecord decoded = decodeMessage(encodeMessage(original));
      expect(decoded.id, original.id);
      expect(decoded.threadId, original.threadId);
      expect(decoded.senderPeerId, original.senderPeerId);
      expect(decoded.kind, original.kind);
      expect(decoded.hlc, original.hlc);
      expect(decoded.ts, original.ts);
      expect(decoded.body, '你好，世界');
      expect(decoded.attachJson, original.attachJson);
      expect(decoded.revokedAt, isNull);
    });

    test('撤回字段往返', () {
      final DateTime at = DateTime.utc(2026, 11, 4, 8, 0, 0);
      final MessageRecord original =
          _msg(revokedAt: at, revokeReason: '误发');
      final MessageRecord decoded = decodeMessage(encodeMessage(original));
      expect(decoded.revokedAt, at);
      expect(decoded.revokeReason, '误发');
      expect(decoded.isRevoked, isTrue);
    });

    test('缺 id 的消息被拒绝，不静默补默认值', () {
      final Map<String, Object?> bad = encodeMessage(_msg())..remove('id');
      expect(() => decodeMessage(bad), throwsA(isA<LanFileException>()));
    });

    test('非法 hlc 被拒绝', () {
      final Map<String, Object?> bad = encodeMessage(_msg());
      bad['hlc'] = 'not-a-hlc';
      expect(() => decodeMessage(bad), throwsA(isA<LanFileException>()));
    });

    test('非法 sender peerId 被拒绝', () {
      final Map<String, Object?> bad = encodeMessage(_msg());
      bad['from'] = 'bad-peer';
      expect(() => decodeMessage(bad), throwsA(isA<LanFileException>()));
    });

    test('未知 kind 被拒绝', () {
      final Map<String, Object?> bad = encodeMessage(_msg());
      bad['kind'] = 'nope';
      expect(() => decodeMessage(bad), throwsA(isA<LanFileException>()));
    });
  });

  group('pull 往返', () {
    test('since 为 null 时不写 sinceHlc 键，解析回来仍是 null', () {
      final Map<String, Object?> payload = encodePull('d_a_b', null);
      expect(payload.containsKey('sinceHlc'), isFalse);
      final PullRequest decoded = decodePull(payload);
      expect(decoded.threadId, 'd_a_b');
      expect(decoded.since, isNull);
    });

    test('带 since 时往返一致', () {
      final Hlc since = Hlc(millis: 1767225600000, counter: 2, origin: 'p_a');
      final PullRequest decoded =
          decodePull(encodePull('d_a_b', since));
      expect(decoded.since, since);
    });

    test('sinceHlc 非法抛 invalidArgument', () {
      expect(
        () => decodePull(<String, Object?>{'thread': 't', 'sinceHlc': 'x'}),
        throwsA(isA<LanFileException>()),
      );
    });

    test('缺 thread 抛错', () {
      expect(
        () => decodePull(<String, Object?>{}),
        throwsA(isA<LanFileException>()),
      );
    });

    test('pull 响应往返一致', () {
      final List<MessageRecord> list = <MessageRecord>[_msg(), _msg(id: 'x:2')];
      final List<MessageRecord> decoded =
          decodePullResponse(encodePullResponse('d_a_b', list));
      expect(decoded.length, 2);
      expect(decoded.first.id, list.first.id);
      expect(decoded.last.id, 'x:2');
    });

    test('pull 响应 messages 非数组抛错', () {
      expect(
        () => decodePullResponse(<String, Object?>{'messages': 'nope'}),
        throwsA(isA<LanFileException>()),
      );
    });
  });

  group('revoke / ack 往返', () {
    test('revoke 往返一致（含 reason）', () {
      final DateTime at = DateTime.utc(2026, 11, 4, 9, 0, 0);
      final RevokeRequest decoded =
          decodeRevoke(encodeRevoke('m1', at, reason: '不想留'));
      expect(decoded.messageId, 'm1');
      expect(decoded.at, at);
      expect(decoded.reason, '不想留');
    });

    test('revoke 不带 reason 时解析为 null', () {
      final RevokeRequest decoded =
          decodeRevoke(encodeRevoke('m1', DateTime.utc(2026, 11, 4)));
      expect(decoded.reason, isNull);
    });

    test('ack 往返一致', () {
      expect(decodeAck(encodeAck(<String>['a', 'b'])), <String>['a', 'b']);
    });

    test('ack 里出现非字符串抛错', () {
      expect(
        () => decodeAck(<String, Object?>{
          'msgIds': <Object?>['a', 42],
        }),
        throwsA(isA<LanFileException>()),
      );
    });
  });

  group('帧编解码', () {
    test('WsFrame 往返与类型常量一致', () {
      final WsFrame frame = WsFrame(
        WsFrame.msg,
        <String, Object?>{'id': 'm1'},
      );
      final WsFrame decoded = decodeFrame(encodeFrame(frame));
      expect(decoded.type, WsFrame.msg);
      expect(decoded.payload['id'], 'm1');
    });

    test('非 JSON 抛 invalidArgument', () {
      expect(() => decodeFrame('not json'), throwsA(isA<LanFileException>()));
    });

    test('顶层非对象抛 invalidArgument', () {
      expect(() => decodeFrame('[1,2,3]'), throwsA(isA<LanFileException>()));
    });

    test('缺 t 字段抛 invalidArgument', () {
      expect(() => decodeFrame('{"a":1}'), throwsA(isA<LanFileException>()));
    });
  });
}