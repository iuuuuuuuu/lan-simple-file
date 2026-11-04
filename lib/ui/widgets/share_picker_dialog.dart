// SPDX-License-Identifier: GPL-3.0-only

import 'package:flutter/material.dart';

import '../../core/contracts/contracts.dart';
import 'share_row.dart';

bool matchesShare(ShareRecord share, String query) {
  final text = query.trim().toLowerCase();
  return text.isEmpty ||
      share.displayName.toLowerCase().contains(text) ||
      shareLocationLabel(share).toLowerCase().contains(text);
}

class SharePickerDialog extends StatefulWidget {
  const SharePickerDialog({super.key, required this.shares});
  final List<ShareRecord> shares;
  @override
  State<SharePickerDialog> createState() => _SharePickerDialogState();
}

class _SharePickerDialogState extends State<SharePickerDialog> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final filtered = widget.shares
        .where((s) => matchesShare(s, _query))
        .toList();
    return AlertDialog(
      title: const Text('发送文件分享'),
      content: SizedBox(
        width: 480,
        height: 400,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('share-picker-search'),
              onChanged: (text) => setState(() => _query = text),
              decoration: const InputDecoration(
                hintText: '搜索分享名称或文件位置',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        widget.shares.isEmpty ? '请先在“我的分享”中添加文件' : '没有匹配的分享',
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, index) {
                        final share = filtered[index];
                        return ListTile(
                          key: ValueKey('pick-share-${share.id.value}'),
                          leading: Icon(
                            share.kind == 'file'
                                ? Icons.insert_drive_file_outlined
                                : Icons.folder_outlined,
                          ),
                          title: Text(
                            share.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            shareLocationLabel(share),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.pop(context, share.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
