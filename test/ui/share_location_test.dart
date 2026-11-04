// SPDX-License-Identifier: GPL-3.0-only

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/ui/widgets/share_row.dart';

import 'support/ui_fakes.dart';

void main() {
  test('文件与文件夹都显示完整源路径，名称可独立修改', () {
    expect(
      shareLocationLabel(
        shareRecord(
          id: 'file01',
          kind: 'file',
          displayName: '旅行照片',
          rootUri: r'D:\共享文件\照片.jpg',
        ),
      ),
      r'D:\共享文件\照片.jpg',
    );
    expect(
      shareLocationLabel(
        shareRecord(
          id: 'folder01',
          displayName: '自定义名称',
          rootUri: r'D:\共享文件\相册',
        ),
      ),
      r'D:\共享文件\相册',
    );
  });

  test('保留 POSIX、网络共享和 SAF 的真实位置', () {
    expect(
      shareLocationLabel(
        shareRecord(
          id: 'posix01',
          kind: 'file',
          displayName: 'a.txt',
          rootUri: '/home/user/share/a.txt',
        ),
      ),
      '/home/user/share/a.txt',
    );
    expect(
      shareLocationLabel(
        shareRecord(id: 'unc01', rootUri: r'\\server\shared\photos'),
      ),
      r'\\server\shared\photos',
    );
    const String uri = 'content://documents/tree/primary%3ADCIM';
    expect(
      shareLocationLabel(
        shareRecord(id: 'saf01', rootKind: 'safTree', rootUri: uri),
      ),
      uri,
    );
  });

  testWidgets('长路径在窄行中不溢出，并保留完整悬浮提示', (tester) async {
    const String path = r'D:\非常长的父目录\包含空格的文件夹\第二级目录\第三级目录\相册';
    await tester.pumpWidget(
      wrapWithTheme(
        Center(
          child: SizedBox(
            width: 280,
            child: ShareRow(
              share: shareRecord(id: 'long01', rootUri: path),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(path), findsOneWidget);
    expect(find.byTooltip(path), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
