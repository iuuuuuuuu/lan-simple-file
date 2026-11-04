// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/widgets.dart';

enum CloseAction {
  ask('每次询问'),
  tray('缩回托盘'),
  exit('彻底退出');

  const CloseAction(this.label);
  final String label;
}

/// 所有关闭入口共用的策略；先保存选择，再隐藏或退出。
class CloseBehavior extends ValueNotifier<CloseAction> {
  CloseBehavior({
    required this.read,
    required this.write,
    required this.choose,
    required this.hide,
    required this.exit,
    required this.reportError,
  }) : super(CloseAction.ask);

  static const settingKey = 'window.closeAction';
  final Future<String?> Function() read;
  final Future<void> Function(String) write;
  final Future<CloseAction?> Function() choose;
  final Future<void> Function() hide;
  final Future<void> Function() exit;
  final void Function(Object) reportError;
  bool trayReady = false;
  bool _closing = false;
  bool _exited = false;

  Future<void> hydrate() async {
    final saved = await read();
    value = CloseAction.values.firstWhere(
      (action) => action.name == saved,
      orElse: () => CloseAction.ask,
    );
  }

  Future<void> setAction(CloseAction action) async {
    await write(action.name);
    value = action;
  }

  Future<void> requestClose({bool forceExit = false}) async {
    if (_closing || _exited) return;
    _closing = true;
    try {
      var action = forceExit ? CloseAction.exit : value;
      if (action == CloseAction.ask) {
        final selected = await choose();
        if (selected == null) return;
        action = selected;
        if (action == CloseAction.tray && !trayReady) {
          throw StateError('托盘未能注册，窗口将保持打开。请稍后重试或选择彻底退出。');
        }
        await setAction(action);
      }
      if (action == CloseAction.tray) {
        if (!trayReady) {
          throw StateError('托盘未能注册，无法缩回托盘。请在设置中改为彻底退出。');
        }
        await hide();
      } else {
        await exit();
        _exited = true;
      }
    } on Object catch (error) {
      reportError(error);
    } finally {
      _closing = false;
    }
  }
}

class CloseBehaviorScope extends InheritedWidget {
  const CloseBehaviorScope({
    super.key,
    required this.behavior,
    required super.child,
  });

  final CloseBehavior behavior;
  static CloseBehavior? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<CloseBehaviorScope>()
      ?.behavior;

  @override
  bool updateShouldNotify(CloseBehaviorScope oldWidget) =>
      behavior != oldWidget.behavior;
}
