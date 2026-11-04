// SPDX-License-Identifier: GPL-3.0-only

/// 窗口控制的桌面实现。
///
/// **用 window_manager 的 legacy API，而不是 0.6 新的 nativeapi。** 理由：
/// 新 API 是面向「多窗口 + 事件流」重建的（`Application.instance.getPrimaryWindow()`，
/// 标题/关闭走 `WindowProperty` 与关闭请求事件），本项目只需要
/// 「无边框 + 最小化/最大化/关闭 + 拖拽区」这四件最基础的事；
/// legacy 的全局 `windowManager` 一行一个动作，边界最清楚。
///
/// 代价：legacy 被标记 deprecated，未来会移除。已在决策笔记里记录，
/// 若将来需要多窗口再整体迁到新 API。
///
/// 只在桌面编译；其它平台走 window_control_stub.dart（条件导入）。
library;

import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/legacy.dart';
import 'package:tray_manager/legacy.dart';

// 全文件忽略 deprecated：本文件刻意选择 legacy API（见文件头理由），
// 逐行加 ignore 只会把真正的新告警淹掉。
// ignore_for_file: deprecated_member_use

/// 窗口是否已被本实现接管。
bool get windowControlAvailable =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// 可拖拽区域包装（桌面版：真正能在标题栏上拖窗口）。
class DragToMoveAreaWrapper extends StatelessWidget {
  const DragToMoveAreaWrapper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DragToMoveArea(child: child);
}

/// 初始化窗口：无边框 + 最小尺寸 + 居中。
Future<void> initDesktopWindowImpl() async {
  await windowManager.ensureInitialized();
  const WindowOptions options = WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(900, 600),
    center: true,
    titleBarStyle: TitleBarStyle.hidden,
    title: '局域网简易文件',
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

/// 最小化。
Future<void> minimizeWindow() => windowManager.minimize();

/// 最大化 / 还原切换。
Future<void> toggleMaximizeWindow() async {
  if (await windowManager.isMaximized()) {
    await windowManager.unmaximize();
  } else {
    await windowManager.maximize();
  }
}

/// 关闭。
Future<void> closeWindow() => windowManager.close();

/// 当前是否最大化。
Future<bool> isWindowMaximized() => windowManager.isMaximized();

_DesktopLifecycle? _lifecycle;

Future<bool> installDesktopLifecycle({
  required Future<void> Function() onClose,
  required Future<void> Function() onExit,
  String logoAsset = 'assets/logos/c.ico',
}) async {
  final listener = _DesktopLifecycle(onClose, onExit);
  _lifecycle = listener;
  windowManager.addListener(listener);
  await windowManager.setPreventClose(true);
  trayManager.addListener(listener);
  try {
    await trayManager.setIcon(
      Platform.isWindows ? logoAsset : logoAsset.replaceAll('.ico', '.png'),
    );
    await trayManager.setToolTip('局域网简易文件');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: '打开客户端'),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: '彻底退出'),
        ],
      ),
    );
    return true;
  } on Object {
    return false;
  }
}

Future<void> hideDesktopWindow() => windowManager.hide();

Future<void> setDesktopLogo(String imageAsset, String iconAsset) async {
  if (Platform.isWindows) await windowManager.setIcon(imageAsset);
  if (_lifecycle != null) {
    await trayManager.setIcon(Platform.isWindows ? iconAsset : imageAsset);
  }
}

Future<void> showDesktopWindow() async {
  if (await windowManager.isMinimized()) await windowManager.restore();
  await windowManager.show();
  await windowManager.focus();
}

Future<void> destroyDesktopWindow() async {
  final listener = _lifecycle;
  if (listener != null) {
    windowManager.removeListener(listener);
    trayManager.removeListener(listener);
    _lifecycle = null;
  }
  await trayManager.destroy();
  await windowManager.destroy();
}

class _DesktopLifecycle with WindowListener, TrayListener {
  _DesktopLifecycle(this.close, this.exit);
  final Future<void> Function() close;
  final Future<void> Function() exit;

  @override
  void onWindowClose() => unawaited(close());
  @override
  void onTrayIconMouseUp() => unawaited(showDesktopWindow());
  @override
  void onTrayIconRightMouseUp() => unawaited(trayManager.popUpContextMenu());
  @override
  void onTrayMenuItemClick(MenuItem item) {
    if (item.key == 'show') unawaited(showDesktopWindow());
    if (item.key == 'exit') unawaited(exit());
  }
}
