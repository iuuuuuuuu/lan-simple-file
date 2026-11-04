// SPDX-License-Identifier: GPL-3.0-only

/// 窗口控制的空实现：非桌面平台（Android 等）编译这个文件。
///
/// 存在的理由：window_manager 只声明了 windows 平台，Android 直接 import
/// 会让 APK 打包失败。条件导入保证同一份 UI 代码在两端都能编译。
library;

import 'package:flutter/widgets.dart';

/// 窗口是否已被本实现接管（非桌面恒为 false）。
bool get windowControlAvailable => false;

/// 可拖拽区域包装：非桌面退化成直接返回 child。
///
/// 存在的理由：桌面用 window_manager 的 DragToMoveArea，
/// 而那个符号只在该插件的桌面实现里存在，不能泄漏到 UI 层。
class DragToMoveAreaWrapper extends StatelessWidget {
  const DragToMoveAreaWrapper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// 初始化窗口；非桌面直接返回。
Future<void> initDesktopWindowImpl() async {}

/// 最小化。
Future<void> minimizeWindow() async {}

/// 最大化 / 还原。
Future<void> toggleMaximizeWindow() async {}

/// 关闭。
Future<void> closeWindow() async {}

/// 当前是否最大化。
Future<bool> isWindowMaximized() async => false;

Future<bool> installDesktopLifecycle({
  required Future<void> Function() onClose,
  required Future<void> Function() onExit,
  String logoAsset = 'assets/logos/c.ico',
}) async => false;
Future<void> setDesktopLogo(String imageAsset, String iconAsset) async {}
Future<void> hideDesktopWindow() async {}
Future<void> showDesktopWindow() async {}
Future<void> destroyDesktopWindow() async {}
