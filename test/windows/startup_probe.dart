// SPDX-License-Identifier: GPL-3.0-only
// Built as a separate entrypoint; never uses the installed application's data.
// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lan_simple_file/app/app.dart';
import 'package:lan_simple_file/app/assembly.dart';
import 'package:lan_simple_file/ui/pages/home_page.dart';
import 'package:lan_simple_file/ui/shell/close_behavior.dart';
import 'package:lan_simple_file/ui/shell/custom_title_bar.dart';
import 'package:lan_simple_file/ui/shell/startup_behavior.dart';
import 'package:lan_simple_file/ui/shell/window_control_desktop.dart' as wc;
import 'package:window_manager/legacy.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = Directory(arguments[0]);
  final mode = arguments[1];
  AppServices? services;
  try {
    await initDesktopWindow();
    services = await AppAssembler.assemble(
      dataDir: Directory('${dir.path}/data'),
      name: 'Startup probe',
      httpPortOverride: 0,
      udpPortOverride: 0,
      enableDiscovery: false,
      enableLocalDomains: false,
    );
    if (mode == 'saved' || mode == 'show') {
      await services.store.setSetting(StartupBehavior.settingKey, 'true');
    }
    runApp(
      ProviderScope(
        child: LanFileApp(
          services: services,
          startupArguments: [
            if (mode == 'cli') '--silent',
            if (mode == 'show') '--show',
          ],
        ),
      ),
    );
    CloseBehavior? close;
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (close?.trayReady != true && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      void visit(Element element) {
        if (element.widget is HomePage) {
          close = CloseBehaviorScope.maybeOf(element);
        }
        element.visitChildren(visit);
      }

      WidgetsBinding.instance.rootElement?.visitChildren(visit);
    }
    if (close?.trayReady != true) throw StateError('Tray did not initialize');
    await Future<void>.delayed(const Duration(milliseconds: 750));
    final shouldShow = mode == 'normal' || mode == 'show';
    if (await windowManager.isVisible() != shouldShow) {
      throw StateError('Unexpected initial window visibility for $mode');
    }
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    try {
      final response = await (await client.getUrl(
        Uri.parse('http://127.0.0.1:${services.port}/api/v1/ping'),
      )).close();
      final body = jsonDecode(await response.transform(utf8.decoder).join());
      if (response.statusCode != 200 || body['name'] != 'Startup probe') {
        throw StateError('Background HTTP service unavailable');
      }
    } finally {
      client.close(force: true);
    }
    await File('${dir.path}/ready').writeAsString('tray=true;http=200');
    final proceed = File('${dir.path}/continue');
    while (!await proceed.exists()) {
      if (DateTime.now().isAfter(deadline)) throw StateError('Monitor timeout');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    // The same callback used by both tray click and the tray's Open command.
    await wc.showDesktopWindow();
    if (!await windowManager.isVisible()) throw StateError('Cannot reopen');
    await close!.setAction(CloseAction.tray);
    await close!.requestClose();
    if (await windowManager.isVisible()) throw StateError('Cannot hide');
    await File('${dir.path}/passed').writeAsString(
      '$mode: tray ready, HTTP 200, visibility correct, reopen and hide passed',
    );
    await close!.requestClose(forceExit: true);
  } on Object catch (error, stack) {
    await File('${dir.path}/failed').writeAsString('$error\n$stack');
    await services?.stop();
    exit(1);
  }
}
