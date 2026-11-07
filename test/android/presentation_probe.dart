// SPDX-License-Identifier: GPL-3.0-only
// Build only with -PlanProbe=true; the control server belongs to the probe APK.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:lan_simple_file/app/app.dart';
import 'package:lan_simple_file/app/assembly.dart';
import 'package:lan_simple_file/app/theme/app_theme.dart';
import 'package:lan_simple_file/core/platform/default_nickname.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final support = await getApplicationSupportDirectory();
  if (!support.path.contains('com.lansimplefile.lan_simple_file.probe/')) {
    throw StateError('This probe requires the isolated Android package.');
  }
  final defaultName = await loadDefaultNickname();
  final services = await AppAssembler.assemble(
    dataDir: Directory('${support.path}/presentation'),
    name: defaultName,
    enableLocalDomains: true,
  );
  final sample = File('${support.path}/domain-probe.txt');
  await sample.writeAsString('Android domain download verified');
  final shares = await services.store.listShares(
    owner: services.identity.peerId,
  );
  final share = shares.isEmpty
      ? await services.sharePath(sample.path)
      : shares.first;
  final container = ProviderContainer();
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: LanFileApp(services: services),
    ),
  );
  final control = await HttpServer.bind(InternetAddress.loopbackIPv4, 49865);
  control.listen((request) async {
    try {
      if (request.uri.path == '/theme') {
        await container
            .read(themeModeProvider.notifier)
            .setMode(AppThemeModeX.parse(request.uri.queryParameters['mode']));
      }
      if (request.uri.path == '/rename') {
        await services.renameSelf(request.uri.queryParameters['name']!);
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'defaultName': defaultName,
          'name': services.profile.name,
          'peerId': services.identity.peerId.value,
          'port': services.port,
          'browserPort': services.browserPort,
          'domain': services.localDomain?.host,
          'ready': services.localDomain?.ready,
          'shareId': share.id.value,
          'theme': container.read(themeModeProvider).name,
        }),
      );
    } on Object catch (error) {
      request.response.statusCode = 500;
      request.response.write('$error');
    } finally {
      await request.response.close();
    }
  });
}
