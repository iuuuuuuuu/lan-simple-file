// SPDX-License-Identifier: GPL-3.0-only

/// 应用外壳入口：把 QQ 风格三栏 shell 接到服务栈上。
///
/// 这里只做装配与主题切换（右上角三态按钮），布局细节全部在 ui/shell 内。
/// 保留 [HomeTab] 枚举作为对外兼容的入口参数（旧调用点仍在用），
/// 内部映射到 [ShellSection]。
library;

import 'package:flutter/material.dart';

import '../widgets/app_controls.dart';

import 'package:flutter/services.dart';

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/assembly.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.dart';
import '../shell/custom_title_bar.dart';
import '../shell/qq_shell.dart';
import '../shell/session_rail.dart';
import '../widgets/drop_share_overlay.dart';

/// 五个一级入口（对外兼容保留）。
enum HomeTab {
  /// 附近的人。
  nearby('附近', Icons.chat_bubble_outline, Icons.chat_bubble),

  /// 我的分享。
  shares('我的分享', Icons.folder_outlined, Icons.folder),

  /// 群组。
  groups('群组', Icons.groups_outlined, Icons.groups),

  /// 传输。
  transfers('传输', Icons.swap_vert_circle_outlined, Icons.swap_vert_circle),

  /// 设置。
  settings('设置', Icons.settings_outlined, Icons.settings);

  const HomeTab(this.label, this.icon, this.selectedIcon);

  /// tab 文案。
  final String label;

  /// 未选中图标。
  final IconData icon;

  /// 选中图标。
  final IconData selectedIcon;

  /// 映射到 shell 的 section。
  ShellSection get section => switch (this) {
    HomeTab.nearby => ShellSection.nearby,
    HomeTab.shares => ShellSection.shares,
    HomeTab.groups => ShellSection.groups,
    HomeTab.transfers => ShellSection.transfers,
    HomeTab.settings => ShellSection.settings,
  };
}

/// 外壳页面。
class HomePage extends ConsumerStatefulWidget {
  /// [services] 为装配好的服务栈；widget 测试可传 null（纯 UI 模式）。
  ///
  /// [enableDragDrop] 由组装层按平台传入：桌面 true，**Android false**。
  const HomePage({
    super.key,
    this.initialTab = HomeTab.nearby,
    this.services,
    this.enableDragDrop = true,
    this.sessionSource,
    this.dropHandler,
    this.currentUserName,
  });

  /// 初始选中的 tab。
  final HomeTab initialTab;

  /// 已装配的服务栈。
  final AppServices? services;

  /// 是否启用拖入建共享（Android 必须 false）。
  final bool enableDragDrop;

  /// 可注入的会话来源（测试用）。
  final ShellSessionSource? sessionSource;

  /// 拖入处理端口（测试用）。
  final DropShareHandler? dropHandler;

  /// 本机登录账户名（设置页昵称初始值）。null 时设置页自行回落。
  final String? currentUserName;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  Widget build(BuildContext context) {
    final LanFileTokens tokens =
        Theme.of(context).extension<LanFileTokens>() ??
        LanFilePalette.of(Theme.of(context).brightness);

    final mobile = Platform.isAndroid || MediaQuery.sizeOf(context).width < 600;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: tokens.isDark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: tokens.isDark
            ? Brightness.light
            : Brightness.dark,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarContrastEnforced: false,
      ),
      child: AppScaffold(
        backgroundColor: tokens.bg,
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          top: !mobile,
          child: Column(
            children: <Widget>[
              // 自绘标题栏：替掉系统那条（系统标题栏是最强烈的「工具软件」信号）。
              // 主题切换放在它的右侧 actions 区。
              if (!mobile)
                CustomTitleBar(
                  title: '局域网简易文件',
                  trailing: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[_ThemeModeButton(), SizedBox(width: 6)],
                  ),
                ),
              Expanded(
                child: QqShell(
                  services: widget.services,
                  sessionSource: widget.sessionSource,
                  enableDragDrop: widget.enableDragDrop && !Platform.isAndroid,
                  // 没注入 handler 时，从真实服务栈造一个。
                  // 之前这里一直是 null，导致拖入必定「0 个共享，1 个失败」——
                  // 那是功能缺失，不是用户操作问题。
                  dropHandler:
                      widget.dropHandler ??
                      (widget.services == null
                          ? null
                          : ServiceDropShareHandler(
                              create: widget.services!.sharePath,
                            )),
                  initialSection: widget.initialTab.section,
                  currentUserName: widget.currentUserName,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 三态主题切换按钮：system → dark → light → system。
class _ThemeModeButton extends ConsumerWidget {
  const _ThemeModeButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppThemeMode mode = ref.watch(themeModeProvider);
    final IconData icon = switch (mode) {
      AppThemeMode.system => Icons.brightness_auto_outlined,
      AppThemeMode.light => Icons.light_mode_outlined,
      AppThemeMode.dark => Icons.dark_mode_outlined,
    };
    return CaptionButton(
      key: const ValueKey<String>('theme-mode-button'),
      tooltip: '主题：${mode.label}（点击切换）',
      icon: icon,
      selected: mode != AppThemeMode.system,
      onTap: () async => ref.read(themeModeProvider.notifier).cycle(),
    );
  }
}
