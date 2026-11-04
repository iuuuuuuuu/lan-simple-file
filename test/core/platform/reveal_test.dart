// SPDX-License-Identifier: GPL-3.0-only

/// 「打开文件所在位置」的路径拼接规则。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/platform/reveal_in_file_manager.dart';

void main() {
  group('joinShareItemPath', () {
    test('桌面分享：root + 相对 itemKey 拼成绝对路径', () {
      final String? result = joinShareItemPath(
        rootKind: 'localPath',
        rootUri: 'D:/shared/photos',
        itemKey: 'a/b.txt',
      );
      expect(result, isNotNull);
      expect(result!, contains('a'));
      expect(result.contains('b.txt'), isTrue);
      // 根目录本身要在路径里，否则定位不到。
      expect(result.contains('photos'), isTrue);
    });

    test('安卓 SAF 分享：没有磁盘路径，返回 null 而不是编一个', () {
      final String? result = joinShareItemPath(
        rootKind: 'safTree',
        rootUri: 'content://com.android.externalstorage.documents/tree/primary%3ADCIM',
        itemKey: 'primary:DCIM/Camera/a.jpg',
      );
      expect(result, isNull, reason: 'SAF 的 treeUri 不是磁盘路径，不能拿去 explorer');
    });

    test('空 itemKey 时返回根本身', () {
      final String? result = joinShareItemPath(
        rootKind: 'localPath',
        rootUri: 'D:/shared',
        itemKey: '',
      );
      expect(result, isNotNull);
      expect(result!.contains('shared'), isTrue);
    });
  });

  group('revealInFileManager', () {
    test('空路径必须给可读错误，不调系统命令', () async {
      final String? error = await revealInFileManager('');
      expect(error, isNotNull);
      expect(error!, contains('路径为空'));
    });
  });
}
