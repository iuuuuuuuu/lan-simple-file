// SPDX-License-Identifier: GPL-3.0-only

/// 应用入口：真实装配服务栈并启动外壳。
///
/// 装配失败（端口被占满、数据库损坏、身份文件损坏）不静默降级：
/// 直接把错误展示出来，否则用户只会看到「附近的人一直空着」。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'dart:io';

import 'app/app.dart';
import 'app/assembly.dart';
import 'app/network_diagnostics.dart';
import 'core/diagnostics/network_log.dart';
import 'ui/widgets/network_diagnostics_setting.dart';
import 'app/theme/app_theme.dart';
import 'core/platform/default_nickname.dart';
import 'ui/shell/custom_title_bar.dart';
import 'ui/widgets/app_controls.dart';
import 'ui/shell/window_control_stub.dart'
    if (dart.library.io) 'ui/shell/window_control_desktop.dart'
    as wc;

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  try {
    // Keep the native window hidden until saved startup and tray setup finish.
    await initDesktopWindow();
    final String dataDirPath = (await getApplicationSupportDirectory()).path;
    await NetworkDiagnostics.initialize(Directory(dataDirPath));
    // enableDiscovery 打开后本机会真实广播；离线环境（无网卡）会降级为只发不收，
    // 由 AnnounceService.degradedReason 暴露原因，不阻断启动。
    final AppServices services = await AppAssembler.assemble(
      dataDir: Directory(dataDirPath),
      // Android uses its configured device name; desktop uses the account name.
      name: await loadDefaultNickname(),
      enableLocalDomains: true,
    );
    NetworkDiagnostics.active?.attach(services);
    runApp(
      ProviderScope(
        child: LanFileApp(services: services, startupArguments: arguments),
      ),
    );
  } catch (error, stack) {
    NetworkLog.record('app.startup_error', NetworkLog.errorFields(error));
    await NetworkLog.active?.flush();
    runApp(_StartupFailureApp(error: error, stack: stack));
    if (wc.windowControlAvailable) await wc.showDesktopWindow();
  }
}

/// 装配失败时的降级界面：把原因说清楚，而不是白屏或假成功。
class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp({required this.error, required this.stack});

  final Object error;
  final StackTrace stack;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '启动失败',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      builder: (context, child) => AppMiuixTheme(child: child!),
      home: AppScaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Text(
                '启动失败',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text('服务没能装配起来。这通常意味着端口被占满、数据库损坏，或身份文件损坏。'),
              const SizedBox(height: 16),
              SelectableText(
                error.toString(),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 12),
              SelectableText(
                stack.toString().split('\n').take(6).join('\n'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
              if (NetworkDiagnostics.active != null)
                const NetworkDiagnosticsSetting(),
            ],
          ),
        ),
      ),
    );
  }
}
