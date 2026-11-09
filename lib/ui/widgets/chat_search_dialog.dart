// SPDX-License-Identifier: GPL-3.0-only

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/messaging/chat_search.dart';
import 'app_controls.dart';

class ChatSearchDialog extends StatefulWidget {
  const ChatSearchDialog({super.key, required this.source, this.threadId});
  final ChatSearchSource source;
  final String? threadId;

  @override
  State<ChatSearchDialog> createState() => _ChatSearchDialogState();
}

class _ChatSearchDialogState extends State<ChatSearchDialog> {
  Timer? _debounce;
  String _query = '';
  ChatSearchKind _kind = ChatSearchKind.all;
  List<ChatSearchHit> _hits = [];
  bool _loading = false;
  String? _error;
  int _revision = 0;

  void _changed(String value) {
    _query = value;
    _debounce?.cancel();
    _revision++;
    setState(() {
      _loading = true;
      _hits = [];
      _error = null;
    });
    _debounce = Timer(const Duration(milliseconds: 200), _search);
  }

  Future<void> _search() async {
    _debounce?.cancel();
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final hits = await widget.source.search(
        _query,
        kind: _kind,
        threadId: widget.threadId,
      );
      if (mounted && revision == _revision) setState(() => _hits = hits);
    } on Object catch (error) {
      if (mounted && revision == _revision) {
        setState(() => _error = '搜索失败：$error');
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    maxWidth: 720,
    title: Text(widget.threadId == null ? '聊天记录和文件' : '搜索当前聊天'),
    content: SizedBox(
      width: 640,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            key: const ValueKey('chat-history-search'),
            label: '搜索文字或文件名',
            placeholder: true,
            leading: const Icon(Icons.search),
            onChanged: _changed,
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 8),
          MiuixTabRow(
            tabs: const ['全部', '文字', '文件'],
            selectedTabIndex: _kind.index,
            onTabSelected: (index) {
              setState(() => _kind = ChatSearchKind.values[index]);
              _search();
            },
          ),
          SizedBox(
            height: min(340, MediaQuery.sizeOf(context).height * .36),
            child: _loading
                ? const Center(child: MiuixCircularProgressIndicator())
                : _error != null
                ? Center(child: Text(_error!))
                : _hits.isEmpty
                ? Center(
                    child: Text(
                      _query.trim().isEmpty && _kind != ChatSearchKind.files
                          ? '搜索聊天记录或查看文件'
                          : '没有匹配的记录',
                    ),
                  )
                : ListView.builder(
                    itemCount: _hits.length,
                    itemBuilder: (context, index) {
                      final hit = _hits[index];
                      final time = hit.message.ts.toLocal();
                      return AppListTile(
                        key: ValueKey('search-message-${hit.message.id}'),
                        leading: Icon(
                          isFileMessage(hit.message)
                              ? Icons.description_outlined
                              : Icons.chat_bubble_outline,
                        ),
                        title: Text(
                          hit.text,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${hit.thread.title} · ${time.year}/${time.month}/${time.day}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.of(context).pop(hit),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
    actions: [
      AppButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
}
