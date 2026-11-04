// SPDX-License-Identifier: GPL-3.0-only

/// 消息签名的规范化必须抗碰撞：非 ASCII 不得被截断。
///
/// 背景：初版用 joined.codeUnits 塞进 Uint8List，UTF-16 码元被静默截断成低 8 位，
/// 'A'(0x41) 与 'Ł'(0x141) 规范化字节完全相同 → 签名碰撞，
/// 攻击者能替换正文而验签照样通过。这条用例把该缺陷钉死。
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';

Uint8List canonical(String body) => MessageSignature.canonicalBytes(
      messageId: 'p_aaaaaaaaaaaaa:1',
      threadId: 'd_p_aaaaaaaaaaaaa--p_bbbbbbbbbbbbb',
      senderPeerId: 'p_aaaaaaaaaaaaa',
      hlc: '1767225600000:0:p_aaaaaaaaaaaaa',
      tsMillis: 1767225600000,
      kind: 'text',
      body: body,
      attachJson: '{}',
    );

void main() {
  group('规范化字节抗碰撞', () {
    test('A 与 Ł 不得产生相同字节（codeUnits 截断会碰撞）', () {
      final Uint8List a = canonical('A');
      final Uint8List b = canonical('Ł');
      expect(a, isNot(equals(b)), reason: '这两者碰撞即签名可被绕过');
    });

    test('中文正文必须完整保留为 utf8 多字节', () {
      final Uint8List bytes = canonical('你好');
      // '你好' 的 utf8 是 6 字节；若被截断成 2 字节说明又退回了 codeUnits。
      expect(utf8Contains(bytes), isTrue,
          reason: '中文必须出现在规范化字节里，不能被压成单字节');
      expect(bytes.contains(0xE4), isTrue, reason: 'E4 是「你」的 utf8 首字节');
    });

    test('emoji 也必须完整保留', () {
      final Uint8List bytes = canonical('😀');
      expect(bytes.length - canonical('').length, 4,
          reason: 'emoji 的 utf8 是 4 字节；截断会只剩 1 字节');
    });

    test('不同正文必须产生不同字节（取 20 组样本两两不等）', () {
      final List<String> samples = <String>[
        'a', 'b', 'A', 'Ł', '你', '好', '😀', '😁',
        '转账 100 元', '转账 100 圆', '', ' ', '\u0000', 'null', 'false', '0',
        'ﬀ', 'ﬁ', 'Å', 'A\u030A',
      ];
      final Set<String> seen = <String>{};
      for (final String s in samples) {
        seen.add(canonical(s).join(','));
      }
      expect(seen.length, samples.length,
          reason: '任何两个不同正文都不得产生相同规范化字节');
    });

    test('分隔符是 NUL 而不是空格（空格会与正文歧义）', () {
      // 若用空格连接，body='a b' 与 (body='a', attachJson='b') 会撞。
      final Uint8List withSpaceInBody = canonical('a b');
      expect(withSpaceInBody.contains(0x00), isTrue,
          reason: '字段之间必须出现 NUL 分隔符');
    });
  });
}

/// 断言规范化字节里含有可被 utf8 正确解码的中文。
bool utf8Contains(Uint8List bytes) {
  // 直接在字节序列里找「你好」的 utf8 编码。
  const List<int> target = <int>[0xE4, 0xBD, 0xA0, 0xE5, 0xA5, 0xBD];
  for (int i = 0; i + target.length <= bytes.length; i++) {
    bool hit = true;
    for (int j = 0; j < target.length; j++) {
      if (bytes[i + j] != target[j]) {
        hit = false;
        break;
      }
    }
    if (hit) {
      return true;
    }
  }
  return false;
}
