// SPDX-License-Identifier: GPL-3.0-only

/// 在系统文件管理器中定位一个文件/目录（「打开文件所在位置」）。
///
/// 用 dart:io 的 Process.start 直接调系统命令，不引入额外依赖：
/// - Windows: explorer /select,<文件路径>（会选中该文件，正是「所在位置」的语义）；
/// - macOS:   open -R <路径>；
/// - Linux:   xdg-open <父目录>（不同桌面没有统一的「选中」参数，退回打开目录）。
///
/// 失败返回可读原因，不抛裸异常：用户点了按钮就该知道为什么没打开。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// 在系统文件管理器里定位 [absolutePath]。
///
/// 返回 null 表示成功；否则返回一句可读的错误原因。
Future<String?> revealInFileManager(String absolutePath) async {
  if (absolutePath.trim().isEmpty) {
    return '路径为空，无法定位';
  }
  try {
    if (Platform.isWindows) {
      // explorer 的 /select 参数是「选中该文件」而不是「打开该文件」，
      // 这正是「打开文件所在位置」的语义。
      final String normalized = p.normalize(absolutePath).replaceAll('/', r'\');
      await Process.start('explorer', <String>[
        '/select,',
        normalized,
      ], runInShell: true);
    } else if (Platform.isMacOS) {
      await Process.start('open', <String>[
        '-R',
        p.normalize(absolutePath),
      ], runInShell: true);
    } else {
      // Linux 没有跨桌面的「选中文件」标准，退回打开父目录。
      final String dir =
          File(absolutePath).existsSync() ||
              Directory(absolutePath).existsSync()
          ? p.dirname(p.normalize(absolutePath))
          : p.normalize(absolutePath);
      await Process.start('xdg-open', <String>[dir], runInShell: true);
    }
    return null;
  } on Object catch (error) {
    return '无法打开文件管理器：$error';
  }
}

/// 由「分享根 + 条目的 itemKey」拼出绝对路径。
///
/// 桌面分享的 rootUri 是绝对路径，itemKey 是相对 root 的 POSIX 路径。
/// 安卓 SAF 的 rootUri 是 treeUri（不是磁盘路径），无法在文件管理器里定位，
/// 因此那种情况由调用方判定并给提示。
String? joinShareItemPath({
  required String rootKind,
  required String rootUri,
  required String itemKey,
}) {
  if (rootKind != 'localPath') return null;
  final List<String> segments = itemKey
      .split('/')
      .where((String s) => s.isNotEmpty)
      .toList();
  return p.joinAll(<String>[rootUri, ...segments]);
}
