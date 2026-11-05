// SPDX-License-Identifier: GPL-3.0-only
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/platform/windows_startup.dart';

void main() {
  test('实际启动项保存路径、重新读取并禁用，隔离测试名称', () async {
    if (!Platform.isWindows) return;
    final service = WindowsStartup(
      executable: Platform.resolvedExecutable,
      valueName: 'LanSimpleFile-Test-${DateTime.now().microsecondsSinceEpoch}',
    );
    addTearDown(() => service.setEnabled(false));
    expect(await service.enabled(), false);
    await service.setEnabled(true);
    expect(await service.enabled(), true);
    final reopened = WindowsStartup(
      executable: Platform.resolvedExecutable,
      valueName: service.valueName,
    );
    expect(await reopened.enabled(), true);
    await reopened.setEnabled(false);
    expect(await service.enabled(), false);
  });
}
