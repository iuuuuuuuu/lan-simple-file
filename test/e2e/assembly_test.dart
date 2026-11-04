// SPDX-License-Identifier: GPL-3.0-only

/// Lead 侧验收：组装层真的把模块接起来了吗。
///
/// 各模块单测全绿不等于能一起工作——这条用例启动真实 HTTP 服务、
/// 真实 sqlite、真实身份，从外部按契约调用。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/assembly.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lsf_assembly_');
  });
  tearDown(() {
    for (int i = 0; i < 6; i++) {
      try {
        if (tmp.existsSync()) {
          tmp.deleteSync(recursive: true);
        }
        return;
      } on FileSystemException {
        sleep(const Duration(milliseconds: 120));
      }
    }
  });

  test('组装起来后：HTTP 服务真实响应，端口是回填的真实值', () async {
    final AppServices svc = await AppAssembler.assemble(
      dataDir: tmp,
      httpPortOverride: 0,
      udpPortOverride: 0,
      enableDiscovery: false,
      name: '组装测试机',
    );
    try {
      expect(svc.port, greaterThan(0), reason: '启动后必须拿得到真实端口');
      final HttpClient client = HttpClient();
      final HttpClientRequest req = await client.getUrl(
        Uri.parse('http://127.0.0.1:${svc.port}${LanFileConstants.apiPrefix}/ping'),
      );
      final HttpClientResponse res = await req.close();
      expect(res.statusCode, 200);
      final Map<String, Object?> body = jsonDecode(
        await res.transform(utf8.decoder).join(),
      ) as Map<String, Object?>;
      expect(body['peerId'], svc.identity.peerId.value);
      expect(body['name'], '组装测试机');
      client.close();
    } finally {
      await svc.stop();
    }
  });

  test('身份与存储接通：本机记录真进了 peers 表', () async {
    final AppServices svc = await AppAssembler.assemble(
      dataDir: tmp,
      httpPortOverride: 0,
      udpPortOverride: 0,
      enableDiscovery: false,
    );
    try {
      final List<DeviceRecord> devices = await svc.store.listDevices();
      expect(devices.length, 1);
      expect(devices.single.peerId.value, svc.identity.peerId.value);
      expect(devices.single.isSelf, isTrue);
      expect(devices.single.publicKey.length, 32);
    } finally {
      await svc.stop();
    }
  });

  test('公钥查表接通：本机公钥能被 codec 查到（凭证验证的前提）', () async {
    final AppServices svc = await AppAssembler.assemble(
      dataDir: tmp,
      httpPortOverride: 0,
      udpPortOverride: 0,
      enableDiscovery: false,
    );
    try {
      final key = await svc.keys.findPublicKey(svc.identity.peerId);
      expect(key, isNotNull);
      expect(key!.length, 32);
      // 未知 peerId 必须返回 null，不能乱给一把钥匙。
      final unknown = await svc.keys.findPublicKey(PeerId.parse('p_zzzzzzzzzzzzz'));
      expect(unknown, isNull);
    } finally {
      await svc.stop();
    }
  });

  test('共享服务接通：本机分享创建后落库，且链接不含网络地址', () async {
    final AppServices svc = await AppAssembler.assemble(
      dataDir: tmp,
      httpPortOverride: 0,
      udpPortOverride: 0,
      enableDiscovery: false,
    );
    try {
      final Directory root = Directory('${tmp.path}${Platform.pathSeparator}shared')
        ..createSync();
      File('${root.path}${Platform.pathSeparator}a.txt').writeAsStringSync('hello');

      final ShareRecord created = await svc.shares.create(
        CreateShareRequest(
          rootKind: ShareRootKind.localPath,
          rootUri: root.path,
          displayName: '相册',
          mode: ShareMode.token,
        ),
      );
      expect(created.displayName, '相册');

      final List<ShareRecord> mine = await svc.shares.listMine();
      expect(mine.map((ShareRecord s) => s.id.value), contains(created.id.value));

      final Uri link = await svc.shares.buildLink(created.id);
      final String linkText = link.toString();
      expect(linkText.contains('192.168'), isFalse);
      expect(linkText.contains('127.0.0.1'), isFalse);
      expect(linkText.contains('http://'), isFalse);
      expect(linkText.contains(created.id.value), isTrue);
    } finally {
      await svc.stop();
    }
  });

  test('重启后数据仍在：同一 dataDir 再组装一次能读到上次的记录', () async {
    final AppServices first = await AppAssembler.assemble(
      dataDir: tmp,
      httpPortOverride: 0,
      udpPortOverride: 0,
      enableDiscovery: false,
      name: '第一轮',
    );
    final String peerId = first.identity.peerId.value;
    await first.stop();

    final AppServices second = await AppAssembler.assemble(
      dataDir: tmp,
      httpPortOverride: 0,
      udpPortOverride: 0,
      enableDiscovery: false,
      name: '第二轮',
    );
    try {
      expect(second.identity.peerId.value, peerId, reason: '同一台机器身份必须稳定');
      final List<DeviceRecord> devices = await second.store.listDevices();
      expect(devices.any((DeviceRecord d) => d.isSelf), isTrue);
    } finally {
      await second.stop();
    }
  });
}
