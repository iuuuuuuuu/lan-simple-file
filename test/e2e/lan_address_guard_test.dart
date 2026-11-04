// SPDX-License-Identifier: GPL-3.0-only

/// 局域网地址判定的真实证据：私有段放行、公网段必须被拒。
///
/// 这条存在的原因：Flutter 的 dart:io 不经过 Android java.net 栈，
/// network_security_config 对 Dart 侧网络完全不生效，
/// 所以「只对局域网明文」必须在 Dart 里真的判，否则那条约束是空的。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/net/lan_address_guard.dart';

void main() {
  group('私有网段必须放行', () {
    const List<String> allowed = <String>[
      '10.0.0.1',
      '10.255.255.254',
      '172.16.0.1',
      '172.31.255.254',
      '192.168.1.100',
      '192.168.0.1',
      '169.254.10.20',
      '127.0.0.1',
      '::1',
      'fe80::1',
      'fc00::1',
    ];
    for (final String addr in allowed) {
      test('$addr 必须允许', () {
        expect(LanAddressGuard.allowsCleartext(addr), isTrue);
      });
    }
  });

  group('公网与越界地址必须拒绝', () {
    const List<String> denied = <String>[
      '8.8.8.8',
      '1.1.1.1',
      '172.15.0.1', // 172.16/12 的下界之外
      '172.32.0.1', // 上界之外
      '192.169.0.1',
      '11.0.0.1',
      '2001:4860:4860::8888', // Google DNS v6
      '2400:cb00::1',
    ];
    for (final String addr in denied) {
      test('$addr 必须拒绝', () {
        expect(LanAddressGuard.allowsCleartext(addr), isFalse);
      });
    }
  });

  test('非法输入必须拒绝（默认拒绝，不是默认放行）', () {
    expect(LanAddressGuard.allowsCleartext('not-an-ip'), isFalse);
    expect(LanAddressGuard.allowsCleartext(''), isFalse);
    expect(LanAddressGuard.allowsCleartext('192.168.1'), isFalse);
    expect(LanAddressGuard.allowsCleartext('999.1.1.1'), isFalse);
  });

  test('requireCleartextAllowed 对公网地址抛 accessDenied', () {
    expect(
      () => LanAddressGuard.requireCleartextAllowed('8.8.8.8'),
      throwsA(
        isA<LanFileException>().having(
          (LanFileException e) => e.code,
          'code',
          LanFileErrorCode.accessDenied,
        ),
      ),
    );
  });

  test('requireCleartextAllowed 对局域网地址不抛', () {
    LanAddressGuard.requireCleartextAllowed('192.168.1.5');
    LanAddressGuard.requireCleartextAllowed('10.1.2.3');
  });

  test('InternetAddress 直传路径与字符串路径结论一致', () {
    for (final String addr in <String>['10.0.0.1', '8.8.8.8', '::1', '2001:db8::1']) {
      final InternetAddress parsed = InternetAddress(addr);
      expect(
        LanAddressGuard.allowsCleartextAddress(parsed),
        LanAddressGuard.allowsCleartext(addr),
        reason: '两条入口不能给出不同结论：$addr',
      );
    }
  });
}
