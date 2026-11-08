// SPDX-License-Identifier: GPL-3.0-only

/// 应用根组件：装配双色主题、三态主题模式与外壳。
///
/// 这里只做三件事：选主题、装配 MaterialApp、挂外壳。
/// 业务状态一律走 provider，不在本文件里持有。
library;

import 'package:flutter/material.dart';

import '../ui/widgets/app_controls.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/pages/home_page.dart';
import '../ui/shell/close_behavior.dart';
import '../ui/shell/custom_title_bar.dart';
import '../ui/shell/startup_behavior.dart';
import '../ui/shell/window_control_stub.dart'
    if (dart.library.io) '../ui/shell/window_control_desktop.dart'
    as wc;
import 'assembly.dart';
import 'branding/app_logo.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';

/// 应用根组件。
class LanFileApp extends ConsumerStatefulWidget {
  /// 可选初始 tab，便于 widget 测试直接落到某一页。
  ///
  /// [services] 为装配好的服务栈；widget 测试可传 null（不启动真实服务）。
  const LanFileApp({
    super.key,
    this.initialTab = HomeTab.nearby,
    this.services,
    this.startupArguments = const [],
  });

  /// 已装配的服务栈；null 表示纯 UI 测试模式。
  final AppServices? services;
  final List<String> startupArguments;

  /// 初始 tab。
  final HomeTab initialTab;

  @override
  ConsumerState<LanFileApp> createState() => _LanFileAppState();
}

class _LanFileAppState extends ConsumerState<LanFileApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  CloseBehavior? _closeBehavior;
  StartupBehavior? _startupBehavior;
  late final LogoController _logo;
  @override
  void initState() {
    super.initState();
    final services = widget.services;
    _logo = LogoController(
      read: services == null
          ? null
          : () => services.store.getSetting(LogoController.settingKey),
      write: services == null
          ? null
          : (value) =>
                services.store.setSetting(LogoController.settingKey, value),
      apply: !CustomTitleBar.enabled
          ? null
          : (logo) => wc.setDesktopLogo(logo.imageAsset, logo.iconAsset),
    );
    if (services != null && CustomTitleBar.enabled) {
      final behavior = CloseBehavior(
        read: () => services.store.getSetting(CloseBehavior.settingKey),
        write: (value) =>
            services.store.setSetting(CloseBehavior.settingKey, value),
        choose: _chooseClose,
        hide: wc.hideDesktopWindow,
        exit: () async {
          await services.stop();
          await wc.destroyDesktopWindow();
        },
        reportError: _reportCloseError,
      );
      _closeBehavior = behavior;
      final startup = StartupBehavior(
        read: () => services.store.getSetting(StartupBehavior.settingKey),
        write: (value) =>
            services.store.setSetting(StartupBehavior.settingKey, value),
      );
      _startupBehavior = startup;
      Future<void>(() async {
        try {
          await startup.launch(
            arguments: widget.startupArguments,
            show: wc.showDesktopWindow,
            initializeTray: () async {
              await _logo.hydrate();
              await behavior.hydrate();
              behavior.trayReady = await wc.installDesktopLifecycle(
                onClose: behavior.requestClose,
                onExit: () => behavior.requestClose(forceExit: true),
                logoAsset: _logo.value.iconAsset,
              );
              return behavior.trayReady;
            },
          );
        } on Object catch (error) {
          _reportCloseError(error, title: '窗口初始化失败');
        }
      });
    } else {
      _logo.hydrate().catchError((Object _) {});
    }
    // 读取已保存的主题模式；失败不阻断启动，回落到跟随系统。
    Future<void>(() async {
      try {
        await ref
            .read(themeModeProvider.notifier)
            .hydrate(ref.read(themeModeStoreProvider));
      } on Object {
        // 骨架阶段存储实现可缺省，保持跟随系统即可。
      }
    });
  }

  Future<CloseAction?> _chooseClose() async {
    final context = _navigatorKey.currentContext;
    if (context == null) return null;
    return showAppDialog<CloseAction>(
      context: context,
      builder: (context) => AppDialog(
        title: const Text('关闭客户端'),
        content: const Text(
          '缩回托盘后，分享与附近的人扫描会继续运行。\n'
          '将记住本次选择，你可以在设置中修改。',
        ),
        actions: [
          AppButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          AppButton(
            onPressed: () => Navigator.pop(context, CloseAction.exit),
            child: const Text('彻底退出'),
          ),
          AppButton.primary(
            onPressed: _closeBehavior?.trayReady == true
                ? () => Navigator.pop(context, CloseAction.tray)
                : null,
            child: const Text('缩回托盘'),
          ),
        ],
      ),
    );
  }

  void _reportCloseError(Object error, {String title = '无法关闭窗口'}) {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    showAppDialog<void>(
      context: context,
      builder: (context) => AppDialog(
        title: Text(title),
        content: Text(error.toString()),
        actions: [
          AppButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _closeBehavior?.dispose();
    _startupBehavior?.dispose();
    _logo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppThemeMode mode = ref.watch(themeModeProvider);
    return MaterialApp(
      navigatorKey: _navigatorKey,
      builder: (context, child) => AppMiuixTheme(
        child: LogoScope(
          controller: _logo,
          child: _closeBehavior == null
              ? child!
              : StartupBehaviorScope(
                  behavior: _startupBehavior!,
                  child: CloseBehaviorScope(
                    behavior: _closeBehavior!,
                    child: child!,
                  ),
                ),
        ),
      ),
      title: '局域网文件共享',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: mode.themeMode,
      themeAnimationDuration: const Duration(milliseconds: 180),
      themeAnimationCurve: Curves.easeOutCubic,
      home: HomePage(initialTab: widget.initialTab, services: widget.services),
    );
  }
}

/// 供测试与调试直接取用的 token：从当前 context 取，缺失时按亮度回落。
LanFileTokens tokensOf(BuildContext context) {
  final ThemeData theme = Theme.of(context);
  return theme.extension<LanFileTokens>() ??
      LanFilePalette.of(theme.brightness);
}
