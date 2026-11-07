// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/widgets.dart';

/// Keep the window hidden until preferences and the tray are ready.
class StartupBehavior extends ValueNotifier<bool> {
  StartupBehavior({required this.read, required this.write}) : super(false);

  static const settingKey = 'window.silentStartup';
  final Future<String?> Function() read;
  final Future<void> Function(String) write;

  Future<void> setEnabled(bool enabled) async {
    await write(enabled.toString());
    value = enabled;
  }

  Future<void> launch({
    required List<String> arguments,
    required Future<bool> Function() initializeTray,
    required Future<void> Function() show,
  }) async {
    bool trayReady;
    try {
      value = await read() == 'true';
      trayReady = await initializeTray();
    } on Object {
      await show();
      rethrow;
    }
    // Command-line overrides are temporary; --show always permits recovery.
    final silent =
        !arguments.contains('--show') &&
        (arguments.contains('--silent') || value);
    if (!silent || !trayReady) await show();
  }
}

class StartupBehaviorScope extends InheritedWidget {
  const StartupBehaviorScope({
    super.key,
    required this.behavior,
    required super.child,
  });

  final StartupBehavior behavior;

  static StartupBehavior? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<StartupBehaviorScope>()
      ?.behavior;

  @override
  bool updateShouldNotify(StartupBehaviorScope oldWidget) =>
      behavior != oldWidget.behavior;
}
