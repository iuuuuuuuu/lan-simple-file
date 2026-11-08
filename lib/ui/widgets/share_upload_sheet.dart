// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';

import 'app_controls.dart';

enum ShareUploadKind { file, folder, photo }

Future<ShareUploadKind?> showShareUploadSheet(BuildContext context) async {
  return showAppDialog<ShareUploadKind>(
    context: context,
    builder: (_) => const _ShareUploadSheet(),
  );
}

class _ShareUploadSheet extends StatefulWidget {
  const _ShareUploadSheet();

  @override
  State<_ShareUploadSheet> createState() => _ShareUploadSheetState();
}

class _ShareUploadSheetState extends State<_ShareUploadSheet> {
  bool _submitted = false;

  void _choose(ShareUploadKind kind) {
    if (_submitted) return;
    setState(() => _submitted = true);
    Navigator.of(context).pop(kind);
  }

  @override
  Widget build(BuildContext context) => MiuixOverlayBottomSheet(
    show: true,
    renderInRootScaffold: false,
    allowDismiss: !_submitted,
    onDismissRequest: () => Navigator.of(context).pop(),
    content: AbsorbPointer(
      absorbing: _submitted,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppListTile(
              title: Text('上传到我的分享'),
              subtitle: Text('文件保存在本机，局域网设备通过分享链接读取'),
            ),
            AppListTile(
              key: const ValueKey('share-upload-file'),
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text('选择文件'),
              onTap: () => _choose(ShareUploadKind.file),
            ),
            AppListTile(
              key: const ValueKey('share-upload-folder'),
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('选择文件夹'),
              onTap: () => _choose(ShareUploadKind.folder),
            ),
            AppListTile(
              key: const ValueKey('share-upload-photo'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('选择照片'),
              onTap: () => _choose(ShareUploadKind.photo),
            ),
          ],
        ),
      ),
    ),
  );
}
