// SPDX-License-Identifier: GPL-3.0-only

/// 许可头门禁（Flutter test 形式）。
///
/// 为什么从 `dart run tool/check_license_headers.dart` 改成测试：
/// 本机 `dart run` 会触发包的 build hooks（cnativeapi 要解析 vswhere 的 JSON），
/// 而 vswhere 输出的 VS 中文 description 在当前代码页下损坏，
/// 导致 `FormatException: Control character in string` —— 即使脚本本身
/// 不依赖任何包也会在脚本执行**之前**崩掉（EXIT=255）。
/// `flutter test` 不走那条钩子，因此门禁放到测试里才能真实执行。
///
/// 规则与旧脚本完全一致：
/// - 只查 .dart；
/// - 排除 .dart_tool / build / android / windows / ios / linux / macos / .git / .idea；
/// - 排除 *.g.dart 与 *.freezed.dart（生成物由生成器决定，不手写头）；
/// - 首行必须严格等于 SPDX 串（允许行尾空白）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String kExpectedHeader = '// SPDX-License-Identifier: GPL-3.0-only';

const List<String> kSkipDirs = <String>[
  '.dart_tool',
  '.git',
  '.idea',
  'build',
  'android',
  'windows',
  'ios',
  'linux',
  'macos',
];

/// 收集当前工作目录下所有需要检查的 .dart 文件（相对路径，正斜杠）。
List<String> collectDartFiles(Directory root) {
  final List<String> out = <String>[];
  for (final FileSystemEntity e in root.listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    final String rel =
        e.path.replaceFirst(root.path, '').replaceAll(r'\', '/');
    if (kSkipDirs.any((String d) => rel.startsWith('/$d/'))) continue;
    if (rel.endsWith('.g.dart') || rel.endsWith('.freezed.dart')) continue;
    out.add(rel);
  }
  return out;
}

void main() {
  test('全仓 .dart 文件首行都带 GPL-3.0-only SPDX 头', () {
    final Directory root = Directory.current;
    final List<String> files = collectDartFiles(root);
    // 防空跑：一个文件都没扫到时不能算通过。
    expect(files.length, greaterThan(100),
        reason: '扫描到的文件数异常偏少，门禁可能空跑了');

    final List<String> violations = <String>[];
    for (final String rel in files) {
      final List<String> lines =
          File(root.path + rel).readAsLinesSync();
      final String first = lines.isEmpty ? '' : lines.first.trimRight();
      if (first != kExpectedHeader) {
        violations.add('$rel  ->  "$first"');
      }
    }
    expect(violations, isEmpty,
        reason: '以下文件的 SPDX 头不合规：\n${violations.join('\n')}');
  });

  test('门禁自身能真红：人为造一个缺头的文件必须被抓到', () {
    // 这是门禁的自我校验。没有它，上面的用例可能是恒真的。
    final Directory tmp = Directory.systemTemp.createTempSync('lic_gate_');
    try {
      File('${tmp.path}/good.dart')
          .writeAsStringSync('$kExpectedHeader\n');
      File('${tmp.path}/bad.dart').writeAsStringSync('void main() {}\n');
      final List<String> files = collectDartFiles(tmp);
      expect(files.length, 2);
      final List<String> bad = <String>[];
      for (final String rel in files) {
        final String first = File(tmp.path + rel).readAsLinesSync().first;
        if (first.trimRight() != kExpectedHeader) bad.add(rel);
      }
      expect(bad, <String>['/bad.dart'],
          reason: '必须恰好抓到缺头的那个文件');
    } finally {
      tmp.deleteSync(recursive: true);
    }
  });
}