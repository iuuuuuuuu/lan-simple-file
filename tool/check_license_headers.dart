// SPDX-License-Identifier: GPL-3.0-only

/// 许可头门禁：校验所有 Dart 源文件首行携带 GPL-3.0-only 的 SPDX 标识。
///
/// 用法：dart run tool/check_license_headers.dart
/// 退出码 0 表示全部合规，1 表示存在缺失并逐条打印。
///
/// **本机（Windows + 中文 locale）当前跑不了，但这不是本脚本的问题。**
/// 现象：EXIT=255，栈为
/// `cnativeapi` build hook -> `VisualStudioResolver.parseVswhere` ->
/// `FormatException: Control character in string`。
/// 根因：`dart run` 会先跑所有包的 build hooks，其中 native_toolchain_c 调
/// `vswhere.exe -format json` 拿 VS 安装信息，而 VS 的中文 description 在当前
/// 代码页下编码损坏，产出非法控制字符。
/// **证据**：一个只有 print 的纯 dart 文件 `dart run` 同样 EXIT=255——
/// 失败发生在脚本执行之前。
///
/// 替代门禁（本机请用这个）：`flutter test test/tool/license_header_gate_test.dart`
/// 它走 flutter test 的路径，不触发上述 build hook，规则与本脚本完全一致。
/// 本脚本保留，供没有这个问题（非中文 locale / 无 VS）的机器直接使用。
library;

import 'dart:io';

const String _expectedHeader = '// SPDX-License-Identifier: GPL-3.0-only';

/// 不参与检查的目录（生成物、第三方、构建产物）。
const List<String> _skipDirs = <String>[
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

void main(List<String> args) {
  final Directory root = Directory.current;
  final List<String> violations = <String>[];
  int checked = 0;

  for (final FileSystemEntity entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    final String relative =
        entity.path.replaceFirst(root.path, '').replaceAll('\\', '/');
    if (_skipDirs.any((String d) => relative.startsWith('/$d/'))) {
      continue;
    }
    if (relative.endsWith('.g.dart') || relative.endsWith('.freezed.dart')) {
      continue;
    }
    checked++;
    final List<String> lines = entity.readAsLinesSync();
    final String first = lines.isEmpty ? '' : lines.first.trimRight();
    if (first != _expectedHeader) {
      violations.add('$relative  →  首行: "$first"');
    }
  }

  if (violations.isEmpty) {
    stdout.writeln('ok: $checked dart file(s) carry the GPL-3.0-only header');
    exit(0);
  }

  stderr.writeln('违规 ${violations.length} 个文件（检查 $checked 个）：');
  for (final String v in violations) {
    stderr.writeln('  $v');
  }
  exit(1);
}
