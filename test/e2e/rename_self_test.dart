// SPDX-License-Identifier: GPL-3.0-only

/// Lead 侧端到端：改名必须真的对别的节点可见。
///
/// 这条盯的是装配层最容易漏的一处：昵称只写进 store、没有回灌 /api/v1/ping 时，
/// 「本地改了、别人看到的还是旧名」——用户改完名字以为生效了，实际没有。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/assembly.dart';
import 'package:lan_simple_file/core/platform/default_nickname.dart';
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lsf_rename_');
  });
  tearDown(() {
    for (int i = 0; i < 8; i++) {
      try {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        sleep(const Duration(milliseconds: 150));
      }
    }
  });

  Future<Map<String, Object?>> ping(AppServices s) async {
    final HttpClient c = HttpClient();
    final HttpClientRequest req = await c.getUrl(
      Uri.parse('http://127.0.0.1:${s.port}/api/v1/ping'),
    );
    final HttpClientResponse res = await req.close();
    final String text = await res.transform(utf8.decoder).join();
    c.close();
    return jsonDecode(text) as Map<String, Object?>;
  }

  test('登录账户名是默认昵称（不是机器名）', () {
    final String resolved = resolveDefaultNickname();
    expect(resolved.trim(), isNotEmpty, reason: '绝不能返回空串');
    final String? user = Platform.environment['USERNAME'] ??
        Platform.environment['USER'] ??
        Platform.environment['LOGNAME'];
    if (user != null && user.trim().isNotEmpty) {
      expect(resolved, user.trim(),
          reason: '有账户名时必须用它，不能用机器名顶替');
    }
    expect(resolved, isNot(Platform.localHostname),
        reason: '机器名区分不了「谁」，不该作为默认昵称');
  });

  test('改名后 ping 立刻返回新名字（三个写入点都生效）', () async {
    final AppServices a = await AppAssembler.assemble(
      dataDir: Directory('${tmp.path}${Platform.pathSeparator}a'),
      httpPortOverride: 0,
      udpPortOverride: 0,
      enableDiscovery: false,
      name: '初始名',
    );
    try {
      expect((await ping(a))['name'], '初始名');

      await a.renameSelf('小明');
      expect((await ping(a))['name'], '小明',
          reason: '改名必须回灌 profile，否则别的节点读到的还是旧名');

      // peers 表里的本机记录也要更新（「附近的人」里显示的是它）
      final self = await a.store.findDevice(a.identity.peerId);
      expect(self, isNotNull);
      expect(self!.name, '小明');

      // 持久化：store 里的设置也写了
      expect(await a.store.getSetting('profile.name'), '小明');
    } finally {
      await a.stop();
    }
  });

  test('改完名重启，昵称不会被默认值覆盖回去', () async {
    final Directory dir = Directory('${tmp.path}${Platform.pathSeparator}b');

    final AppServices first = await AppAssembler.assemble(
      dataDir: dir,
      httpPortOverride: 0,
      udpPortOverride: 0,
      enableDiscovery: false,
      name: '初始名',
    );
    await first.renameSelf('老板娘');
    final String pid = first.identity.peerId.value;
    await first.stop();

    final AppServices second = await AppAssembler.assemble(
      dataDir: dir,
      httpPortOverride: 0,
      udpPortOverride: 0,
      enableDiscovery: false,
      name: '初始名', // 同样的默认值，但 store 里有用户改过的名字
    );
    try {
      expect(second.identity.peerId.value, pid, reason: '身份必须稳定');
      expect((await ping(second))['name'], '老板娘',
          reason: '用户改过的名字优先于启动默认值');
    } finally {
      await second.stop();
    }
  });

  test('空昵称必须被拒（不能把名字清成空）', () async {
    final AppServices a = await AppAssembler.assemble(
      dataDir: Directory('${tmp.path}${Platform.pathSeparator}c'),
      httpPortOverride: 0,
      udpPortOverride: 0,
      enableDiscovery: false,
    );
    try {
      await expectLater(a.renameSelf('   '), throwsA(anything));
      expect((await ping(a))['name'], isNotEmpty);
    } finally {
      await a.stop();
    }
  });
}