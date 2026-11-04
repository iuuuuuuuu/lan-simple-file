// SPDX-License-Identifier: GPL-3.0-only

import 'package:flutter/material.dart';

enum AppLogo {
  folderLink('A · 文件夹与连接', 'a'),
  transfer('B · 双向互传', 'b'),
  chatFolder('C · 聊天与文件', 'c');

  const AppLogo(this.label, this.fileName);
  final String label;
  final String fileName;
  String get imageAsset => 'assets/logos/$fileName.png';
  String get iconAsset => 'assets/logos/$fileName.ico';
}

class LogoController extends ValueNotifier<AppLogo> {
  LogoController({this.read, this.write, this.apply})
    : super(AppLogo.chatFolder);
  static const settingKey = 'appearance.logo';
  final Future<String?> Function()? read;
  final Future<void> Function(String)? write;
  final Future<void> Function(AppLogo)? apply;
  bool _saving = false;
  bool _disposed = false;

  Future<void> hydrate() async {
    final saved = await read?.call();
    if (_disposed) return;
    value =
        AppLogo.values.where((logo) => logo.name == saved).firstOrNull ??
        AppLogo.chatFolder;
    await apply?.call(value);
  }

  Future<void> select(AppLogo logo) async {
    if (_disposed || _saving || logo == value) return;
    _saving = true;
    final previous = value;
    try {
      await write?.call(logo.name);
      await apply?.call(logo);
      if (!_disposed) value = logo;
    } on Object {
      await write?.call(previous.name);
      rethrow;
    } finally {
      _saving = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class LogoScope extends InheritedNotifier<LogoController> {
  const LogoScope({
    super.key,
    required LogoController controller,
    required super.child,
  }) : super(notifier: controller);
  static LogoController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LogoScope>()?.notifier;
}

class AppLogoImage extends StatelessWidget {
  const AppLogoImage({super.key, this.logo, this.size = 24});
  final AppLogo? logo;
  final double size;
  @override
  Widget build(BuildContext context) => Image.asset(
    (logo ?? LogoScope.maybeOf(context)?.value ?? AppLogo.chatFolder)
        .imageAsset,
    width: size,
    height: size,
    filterQuality: FilterQuality.high,
  );
}
