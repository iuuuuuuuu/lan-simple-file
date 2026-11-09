// SPDX-License-Identifier: GPL-3.0-only
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'app_controls.dart';

import 'package:flutter/services.dart';

import '../../app/theme/tokens.dart';
import '../../core/contracts/contracts.dart';
import 'avatar_badge.dart';
import 'app_toast.dart';
import 'drop_share_overlay.dart';

class ChatPane extends StatefulWidget {
  const ChatPane({
    super.key,
    required this.threadId,
    required this.title,
    required this.self,
    required this.avatarSeed,
    this.messaging,
    this.avatarBytes,
    this.selfAvatarBytes,
    this.subtitle = '',
    this.senderNames = const {},
    this.senderAvatars = const {},
    this.onRead,
    this.sharePicker,
    this.shareLinkResolver,
    this.shareCreator,
    this.enableDragDrop = false,
    this.onUpload,
    this.onBack,
    this.peer,
    this.onShowShares,
    this.focusMessageId,
    this.onClearFocus,
    this.onSearch,
  });
  final String threadId;
  final String title;
  final PeerId self;
  final String avatarSeed;
  final MessagingService? messaging;
  final Uint8List? avatarBytes;
  final Uint8List? selfAvatarBytes;
  final String subtitle;
  final Map<String, String> senderNames;
  final Map<String, Uint8List?> senderAvatars;
  final Future<void> Function()? onRead;
  final Future<ShareId?> Function()? sharePicker;
  final Future<Uri> Function(PeerId, ShareId)? shareLinkResolver;
  final Future<ShareId> Function(String)? shareCreator;
  final bool enableDragDrop;
  final VoidCallback? onUpload;
  final VoidCallback? onBack;
  final PeerId? peer;
  final ValueChanged<PeerId>? onShowShares;
  final String? focusMessageId;
  final VoidCallback? onClearFocus;
  final VoidCallback? onSearch;

  @override
  State<ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends State<ChatPane> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<List<MessageRecord>>? _subscription;
  List<MessageRecord> _messages = [];
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _subscription = widget.messaging
        ?.watchMessages(widget.threadId)
        .listen(
          (messages) {
            if (!mounted) return;
            final nearBottom =
                !_scroll.hasClients ||
                _scroll.position.maxScrollExtent - _scroll.offset < 100;
            setState(() {
              _messages = messages
                  .where((m) => m.revokeReason != 'deletedLocal')
                  .toList();
              _error = null;
            });
            unawaited(
              widget.onRead?.call().catchError((Object _) {}) ??
                  Future<void>.value(),
            );
            if (nearBottom && widget.focusMessageId == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _scroll.hasClients) {
                  _scroll.jumpTo(_scroll.position.maxScrollExtent);
                }
              });
            }
          },
          onError: (Object error) {
            if (mounted) setState(() => _error = '读取消息失败：$error');
          },
        );
  }

  @override
  void didUpdateWidget(covariant ChatPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusMessageId != widget.focusMessageId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(
            widget.focusMessageId == null
                ? _scroll.position.maxScrollExtent
                : 0,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final messaging = widget.messaging;
    final text = _text.text.trim();
    if (_sending || text.isEmpty || messaging == null) return;
    setState(() => _sending = true);
    try {
      await messaging.sendText(widget.threadId, text);
      if (mounted && _text.text.trim() == text) _text.clear();
    } on Object catch (error) {
      if (mounted) setState(() => _error = '发送失败：$error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendShare() async {
    if (_sending || widget.messaging == null) return;
    final share = await widget.sharePicker?.call();
    if (share == null || !mounted) return;
    setState(() => _sending = true);
    try {
      await widget.messaging!.sendFile(widget.threadId, share);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '分享发送失败：$error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _copyShareLink(MessageRecord message) async {
    try {
      final data = jsonDecode(message.attachJson) as Map<String, dynamic>;
      final link = await widget.shareLinkResolver!(
        PeerId.parse(data['owner'] as String),
        ShareId.parse(data['shareId'] as String),
      );
      await Clipboard.setData(ClipboardData(text: link.toString()));
      if (mounted) {
        AppToast.show(context, '取件链接已复制');
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = '复制取件链接失败：$error');
    }
  }

  Future<int> _sendDroppedFiles(List<String> paths) async {
    if (_sending || widget.messaging == null || widget.shareCreator == null) {
      return 0;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    int sent = 0;
    final failures = <String>[];
    try {
      for (final path in paths) {
        try {
          final share = await widget.shareCreator!(path);
          await widget.messaging!.sendFile(widget.threadId, share);
          sent++;
        } on Object catch (error) {
          failures.add('$path：$error');
        }
      }
      if (mounted && failures.isNotEmpty) {
        setState(
          () => _error = '已发送 $sent/${paths.length} 项，${failures.first}',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    return sent;
  }

  Future<void> _revoke(MessageRecord message) async {
    try {
      await widget.messaging?.revoke(message.id);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '撤回失败：$error');
    }
  }

  Future<void> _messageMenu(MessageRecord message, Offset position) async {
    final items = <AppMenuItem<String>>[
      if (message.kind == MessageKind.text && !message.isRevoked)
        const AppMenuItem(value: 'copy', label: '复制文字'),
      if (message.senderPeerId == widget.self &&
          !message.isRevoked &&
          widget.messaging != null)
        const AppMenuItem(value: 'revoke', label: '撤回消息'),
    ];
    if (items.isEmpty) return;
    final action = await showAppMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: items,
    );
    if (!mounted) return;
    if (action == 'revoke') await _revoke(message);
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: message.body));
    }
  }

  Widget _message(MessageRecord message, LanFileTokens tokens) {
    final mine = message.senderPeerId == widget.self;
    final time = message.ts.toLocal();
    String text = message.body;
    if (message.kind == MessageKind.share) {
      try {
        final data = jsonDecode(message.attachJson) as Map<String, dynamic>;
        text = (data['name'] as String?) ?? '文件分享';
      } on Object {
        text = '文件分享';
      }
    }
    final bubble = Flexible(
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (!mine && widget.threadId.startsWith('g_'))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                widget.senderNames[message.senderPeerId.value] ??
                    message.senderPeerId.value,
                style: TextStyle(fontSize: 11, color: tokens.fgDim),
              ),
            ),
          GestureDetector(
            onSecondaryTapDown: message.isRevoked
                ? null
                : (details) => _messageMenu(message, details.globalPosition),
            onLongPressStart: message.isRevoked
                ? null
                : (details) => _messageMenu(message, details.globalPosition),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: MiuixCard(
                insideMargin: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                colors: MiuixCardColors(
                  color: mine ? tokens.accentSoft : tokens.surface,
                  contentColor: tokens.fg,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.kind == MessageKind.share && !message.isRevoked)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Icon(
                          LucideIcons.folder,
                          size: 24,
                          color: tokens.accent,
                        ),
                      ),
                    SelectableText(
                      message.isRevoked ? '消息已撤回' : text,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: message.isRevoked ? tokens.fgDim : tokens.fg,
                      ),
                    ),
                    if (message.kind == MessageKind.share &&
                        !message.isRevoked &&
                        widget.shareLinkResolver != null)
                      AppButton(
                        onPressed: () => _copyShareLink(message),
                        child: const Text('复制取件链接'),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
              style: TextStyle(fontSize: 10, color: tokens.fgDim),
            ),
          ),
          if (mine && !message.isRevoked && widget.messaging != null)
            AppButton(
              key: ValueKey('revoke-message-${message.id}'),
              onPressed: () => _revoke(message),

              child: const Text('撤回'),
            ),
        ],
      ),
    );
    final avatar = _avatar(
      message.senderPeerId,
      key: ValueKey('chat-avatar-${message.id}'),
      child: AvatarBadge(
        peerId: message.senderPeerId.value,
        size: 32,
        avatarBytes: mine
            ? widget.selfAvatarBytes
            : message.senderPeerId == widget.peer
            ? widget.avatarBytes
            : widget.senderAvatars[message.senderPeerId.value],
      ),
    );
    return Container(
      key: ValueKey('chat-message-${message.id}'),
      color: widget.focusMessageId == message.id
          ? tokens.accent.withValues(alpha: .12)
          : null,
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: mine
            ? [bubble, const SizedBox(width: 10), avatar]
            : [avatar, const SizedBox(width: 10), bubble],
      ),
    );
  }

  Widget _avatar(PeerId? peer, {Key? key, required Widget child}) {
    if (peer == null || widget.onShowShares == null) return child;
    return AppIconButton(
      key: key,
      tooltip: '查看分享',
      padding: EdgeInsets.zero,
      onPressed: () => widget.onShowShares!(peer),
      icon: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LanFileTokens>()!;
    final focused = _messages.indexWhere(
      (m) => m.id == widget.focusMessageId && !m.isRevoked,
    );
    return DropShareOverlay(
      enableDragDrop: widget.enableDragDrop && widget.shareCreator != null,
      handler: CallbackDropShareHandler(_sendDroppedFiles),
      label: '松开即可发送文件分享',
      description: '文件将添加到“我的分享”并发送到当前聊天',
      child: Column(
        key: const ValueKey('chat-pane'),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: tokens.surface,
              border: Border(bottom: BorderSide(color: tokens.line)),
            ),
            child: Row(
              children: [
                if (widget.onBack != null)
                  AppIconButton(
                    tooltip: '返回联系人',
                    onPressed: widget.onBack,
                    icon: const Icon(LucideIcons.arrowLeft),
                  ),
                _avatar(
                  widget.peer,
                  key: const ValueKey('chat-header-avatar'),
                  child: AvatarBadge(
                    peerId: widget.avatarSeed,
                    avatarBytes: widget.avatarBytes,
                    size: 36,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: tokens.fg,
                        ),
                      ),
                      if (widget.subtitle.isNotEmpty)
                        Text(
                          widget.subtitle,
                          style: TextStyle(fontSize: 11, color: tokens.fgDim),
                        ),
                    ],
                  ),
                ),
                if (widget.onSearch != null)
                  AppIconButton(
                    tooltip: '搜索当前聊天',
                    onPressed: widget.onSearch,
                    icon: const Icon(LucideIcons.search),
                  ),
              ],
            ),
          ),
          if (widget.focusMessageId != null)
            Row(
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    focused >= 0 ? '已定位搜索结果' : '这条消息已不可用',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                AppIconButton(
                  tooltip: '返回最新消息',
                  onPressed: widget.onClearFocus,
                  icon: const Icon(LucideIcons.x),
                ),
              ],
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _error!,
                style: TextStyle(color: tokens.accent, fontSize: 12),
              ),
            ),
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      widget.messaging == null ? '聊天服务未启动' : '还没有消息，打个招呼吧',
                      style: TextStyle(color: tokens.fgDim, fontSize: 13),
                    ),
                  )
                : focused >= 0
                ? CustomScrollView(
                    controller: _scroll,
                    center: const ValueKey('chat-focus-anchor'),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        sliver: SliverList.builder(
                          itemCount: focused,
                          itemBuilder: (_, index) =>
                              _message(_messages[focused - index - 1], tokens),
                        ),
                      ),
                      SliverPadding(
                        key: const ValueKey('chat-focus-anchor'),
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        sliver: SliverList.builder(
                          itemCount: _messages.length - focused,
                          itemBuilder: (_, index) =>
                              _message(_messages[focused + index], tokens),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    itemCount: _messages.length,
                    itemBuilder: (_, index) =>
                        _message(_messages[index], tokens),
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(
              color: tokens.surface,
              border: Border(top: BorderSide(color: tokens.line)),
            ),
            child: Column(
              children: [
                Focus(
                  onKeyEvent: (_, event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.enter &&
                        !HardwareKeyboard.instance.isShiftPressed) {
                      unawaited(_send());
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: AppTextField(
                    key: const ValueKey('chat-input'),
                    controller: _text,
                    enabled: widget.messaging != null,
                    minLines: 2,
                    maxLines: 5,
                    maxLength: 16000,
                    style: TextStyle(fontSize: 14, color: tokens.fg),
                    label: '输入消息…',
                    placeholder: true,
                  ),
                ),
                Row(
                  children: [
                    if (widget.sharePicker != null)
                      AppIconButton(
                        tooltip: '发送文件分享',
                        onPressed: _sending ? null : _sendShare,
                        icon: Icon(
                          LucideIcons.folder,
                          size: 20,
                          color: tokens.fgDim,
                        ),
                      ),
                    if (widget.onUpload != null)
                      AppIconButton(
                        key: const ValueKey('chat-upload'),
                        tooltip: '上传并发送文件',
                        onPressed: _sending ? null : widget.onUpload,
                        icon: Icon(
                          LucideIcons.circlePlus,
                          color: tokens.accent,
                        ),
                      ),
                    Expanded(
                      child: Text(
                        MediaQuery.sizeOf(context).width < 600
                            ? '发送到当前聊天'
                            : 'Enter 发送 · Shift+Enter 换行',
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: tokens.fgDim),
                      ),
                    ),
                    const SizedBox(width: 14),
                    AppButton.primary(
                      key: const ValueKey('chat-send'),
                      onPressed: _sending || widget.messaging == null
                          ? null
                          : _send,

                      child: Text(_sending ? '发送中…' : '发送'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
