// SPDX-License-Identifier: GPL-3.0-only

/// 自绘标题栏：去掉系统原生标题栏，改用应用内的可拖拽条。
///
/// 为什么自绘：系统标题栏（Windows 默认那条）是「工具/系统软件」最强烈的视觉信号，
/// 也是上一轮评审里「像系统工具而不是 QQ」的主要原因之一。
/// QQ / 微信桌面端都是无边框 + 自绘标题栏。
///
/// 跨平台：窗口 API 通过条件导入隔离（window_manager 只声明了 windows），
/// 否则 Android 会因找不到插件而打包失败。
library;

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../app/branding/app_logo.dart';
import 'window_control_stub.dart'
    if (dart.library.io) 'window_control_desktop.dart'
    as wc;

/// 自绘标题栏。
class CustomTitleBar extends StatefulWidget {
  const CustomTitleBar({
    super.key,
    this.title = '局域网简易文件',
    this.trailing,
    this.height = 36,
  });

  final String title;
  final Widget? trailing;
  final double height;

  /// 是否可用自定义窗口（桌面且已初始化）。
  ///
  /// 抽成静态开关而不是硬判 Platform：widget test 里没有真实窗口，
  /// 硬判会让测试直接崩。
  static bool enabled = false;

  @override
  State<CustomTitleBar> createState() => _CustomTitleBarState();
}

class _CustomTitleBarState extends State<CustomTitleBar> {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    if (CustomTitleBar.enabled) {
      wc
          .isWindowMaximized()
          .then((bool v) {
            if (mounted) setState(() => _maximized = v);
          })
          .catchError((Object _) {});
    }
  }

  Future<void> _toggleMaximize() async {
    await wc.toggleMaximizeWindow();
    final bool v = await wc.isWindowMaximized();
    if (mounted) setState(() => _maximized = v);
  }

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    final Widget content = SizedBox(
      height: widget.height,
      child: Row(
        children: <Widget>[
          const SizedBox(width: 12),
          const AppLogoImage(size: 20),
          const SizedBox(width: 8),
          Text(
            widget.title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: tokens.fgDim,
            ),
          ),
          const Spacer(),
          if (widget.trailing != null) widget.trailing!,
          if (CustomTitleBar.enabled) ...<Widget>[
            const SizedBox(width: 4),
            CaptionButton(
              icon: Icons.remove,
              tooltip: '最小化',
              onTap: wc.minimizeWindow,
            ),
            CaptionButton(
              icon: _maximized ? Icons.filter_none : Icons.crop_square,
              tooltip: _maximized ? '还原' : '最大化',
              onTap: _toggleMaximize,
            ),
            CaptionButton(
              icon: Icons.close,
              tooltip: '关闭',
              danger: true,
              onTap: wc.closeWindow,
            ),
          ] else
            const SizedBox(width: 8),
        ],
      ),
    );

    if (!CustomTitleBar.enabled) {
      return DecoratedBox(
        decoration: BoxDecoration(color: tokens.surfaceSunken),
        child: content,
      );
    }

    return GestureDetector(
      // 双击标题栏 = 最大化/还原，Windows 用户的肌肉记忆。
      onDoubleTap: _toggleMaximize,
      child: DragToMoveAreaImpl(tokens: tokens, child: content),
    );
  }
}

/// 可拖拽区域。
///
/// 桌面实现用 window_manager 的 DragToMoveArea；非桌面退化成普通容器。
/// 这样 GestureDetector 的双击与拖拽在两端都不报错。
class DragToMoveAreaImpl extends StatelessWidget {
  const DragToMoveAreaImpl({
    super.key,
    required this.tokens,
    required this.child,
  });

  final LanFileTokens tokens;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Widget decorated = DecoratedBox(
      decoration: BoxDecoration(color: tokens.surfaceSunken),
      child: child,
    );
    // 拖拽只对真实桌面生效；这里用 enabled 开关而不是 import 具体类，
    // 避免把 window_manager 的符号泄漏到 UI 层。
    return wc.windowControlAvailable
        ? wc.DragToMoveAreaWrapper(child: decorated)
        : decorated;
  }
}

/// 窗口与主题按钮：悬浮使用浅底色，选中或按下使用主色背景，
/// 关闭键悬浮时用主色图标强调操作。
class CaptionButton extends StatefulWidget {
  const CaptionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final Future<void> Function() onTap;
  final bool danger;
  final bool selected;

  @override
  State<CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<CaptionButton> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;
    final Color bg = _pressed || widget.selected
        ? tokens.accentSoft
        : _hover
        ? tokens.hoverSoft
        : Colors.transparent;
    final Color fg = widget.selected || (_hover && widget.danger)
        ? tokens.accent
        : _hover
        ? tokens.fg
        : tokens.fgDim;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() {
          _hover = false;
          _pressed = false;
        }),
        child: GestureDetector(
          onTap: () => widget.onTap(),
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: Container(
            key: ValueKey('caption-${widget.tooltip}'),
            width: 44,
            height: 28,
            alignment: Alignment.center,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: widget.selected
                    ? tokens.accent.withValues(alpha: .16)
                    : Colors.transparent,
              ),
            ),
            child: Icon(widget.icon, size: 14, color: fg),
          ),
        ),
      ),
    );
  }
}

/// 桌面窗口初始化（main 里在非 Android 时调用）。
Future<void> initDesktopWindow() async {
  if (!wc.windowControlAvailable) {
    return;
  }
  await wc.initDesktopWindowImpl();
  CustomTitleBar.enabled = true;
}
