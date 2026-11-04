// SPDX-License-Identifier: GPL-3.0-only

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/net/lan_address.dart';
import 'package:lan_simple_file/core/net/local_domain.dart';
import 'package:lan_simple_file/core/platform/windows_firewall.dart';

void main() {
  test('mDNS 放行脚本只覆盖当前应用及本地子网，PowerShell 语法有效', () async {
    final script = buildWindowsFirewallScript(
      // 用中性的安装路径，别把开发机的目录结构写进公开仓库。
      executablePath: r'C:\Program Files\lan-simple-file\lan_simple_file.exe',
      port: 47778,
      includeMdns: true,
      includeBrowserPort: true,
    );
    expect(script, contains("LocalPorts = '5353'"));
    expect(script, contains("LocalPorts = '80'"));
    expect(script, contains('Protocol = 17'));
    expect(script, contains("RemoteAddresses = 'LocalSubnet'"));
    expect(script, contains('Profiles = 3'));
    if (Platform.isWindows) {
      final file = File('build/enable-local-domain.ps1');
      await file.writeAsString(script);
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-Command',
        [
          r'$tokens=$null; $errors=$null; '
              r'[System.Management.Automation.Language.Parser]::ParseFile(',
          "'${file.absolute.path}',",
          r'[ref]$tokens,[ref]$errors) | Out-Null; '
              r'if($errors.Count -gt 0){ $errors | Out-String; exit 1 }',
        ].join(),
      ]);
      expect(
        result.exitCode,
        0,
        reason: result.stdout.toString() + result.stderr.toString(),
      );
    }
  });
  test('昵称转成浏览器 DNS 标签，中文使用 IDNA，长名字和空名字仍有稳定地址', () {
    expect(localDomainLabel('Alice', 'p_device123456'), 'alice');
    expect(localDomainLabel('我的电脑', 'p_device123456'), 'xn--wnuz93by2az6x');
    expect(localDomainLabel('bücher', 'p_device123456'), 'xn--bcher-kva');
    expect(localDomainLabel('hello world', 'p_device123456'), 'hello-world');
    expect(localDomainLabel('', 'p_device123456'), 'user-ce123456');
    expect(localDomainLabel('a' * 80, 'p_device123456'), 'user-ce123456');
  });

  test('域名链接仍验证本机 IP，不放行公网或任意后缀', () {
    final id = ShareId.parse('share123');
    expect(
      buildWebShareUrl(
        host: '10.1.1.2',
        port: 47778,
        shareId: id,
        localDomain: 'alice.local',
      ).host,
      'alice.local',
    );
    expect(
      () => buildWebShareUrl(
        host: '8.8.8.8',
        port: 47778,
        shareId: id,
        localDomain: 'alice.local',
      ),
      throwsA(isA<LanFileException>()),
    );
    expect(
      () => buildWebShareUrl(
        host: '10.1.1.2',
        port: 47778,
        shareId: id,
        localDomain: 'alice.example.com',
      ),
      throwsA(isA<LanFileException>()),
    );
  });

  test('默认 HTTP 端口从网页链接及二维码地址中省略，路径和令牌保留', () {
    final url = buildWebShareUrl(
      host: '10.1.1.2',
      port: 80,
      shareId: ShareId.parse('share123'),
      localDomain: 'alice.local',
      token: 'abc',
    );
    expect(url.toString(), 'http://alice.local/s/share123?k=abc');
    expect(url.hasPort, isFalse);
  });

  test('真实 DNS 压缩名称能够解码，循环指针及截断报文必须丢弃', () {
    // One question and one A answer whose owner uses a pointer to the question.
    final bytes = Uint8List.fromList([
      0,
      0,
      0x84,
      0,
      0,
      1,
      0,
      1,
      0,
      0,
      0,
      0,
      5,
      97,
      108,
      105,
      99,
      101,
      5,
      108,
      111,
      99,
      97,
      108,
      0,
      0,
      1,
      0,
      1,
      0xc0,
      12,
      0,
      1,
      0x80,
      1,
      0,
      0,
      0,
      120,
      0,
      4,
      10,
      1,
      1,
      2,
    ]);
    final packet = DnsPacket.decode(bytes)!;
    expect(packet.answers.single.name, 'alice.local');
    expect(packet.answers.single.data, [10, 1, 1, 2]);
    expect(DnsPacket.decode(Uint8List.fromList([0, 0])), isNull);
    expect(
      DnsPacket.decode(
        Uint8List.fromList([
          0,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          0,
          0,
          0,
          0xc0,
          12,
          0,
          1,
          0,
          1,
        ]),
      ),
      isNull,
    );
    expect(DnsPacket.decode(bytes.sublist(0, bytes.length - 1)), isNull);
  });

  late LocalDomainService service;
  late RawDatagramSocket client;
  late StreamSubscription<RawSocketEvent> subscription;
  late StreamController<DnsPacket> packets;
  var username = 'alice';
  String? ip = '10.1.1.2';
  Future<void> boot() async {
    service = LocalDomainService(
      username: () => username,
      deviceId: 'p_device123456',
      address: () async => ip,
      listenPort: 0,
      multicast: false,
    );
    await service.start();
    expect(service.error, isNull);
    client = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    packets = StreamController<DnsPacket>.broadcast();
    subscription = client.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? datagram;
      while ((datagram = client.receive()) != null) {
        final packet = DnsPacket.decode(datagram!.data);
        if (packet != null) packets.add(packet);
      }
    });
    addTearDown(() async {
      await service.stop();
      await subscription.cancel();
      client.close();
      await packets.close();
    });
  }

  Future<DnsPacket> query(String name, {int type = 1}) {
    final reply = packets.stream.first.timeout(const Duration(seconds: 2));
    client.send(
      DnsPacket(id: 42, questions: [DnsQuestion(name, type)]).encode(),
      InternetAddress.loopbackIPv4,
      service.port!,
    );
    return reply;
  }

  test('UDP 查询返回本机地址，保留 legacy ID，AAAA 给出 NSEC 而非伪造 IPv6', () async {
    await boot();
    expect(service.ready, isTrue);
    final reply = await query('alice.local');
    expect(reply.id, 42);
    expect(reply.questions.single.name, 'alice.local');
    expect(reply.answers.single.data, [10, 1, 1, 2]);
    expect(reply.answers.single.ttl, 10);
    final ipv6 = await query('alice.local', type: 28);
    expect(ipv6.answers.single.type, 47);
    expect(ipv6.answers.single.data.last, 0x40);
    await expectLater(
      query('someone-else.local'),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('改昵称及 IP 变化后旧名称停止响应，离线不继续发布过期地址', () async {
    await boot();
    username = 'alice-beta';
    await service.refresh();
    expect(service.host, 'alice-beta.local');
    username = 'alice';
    await service.refresh();
    expect(service.host, 'alice.local');
    username = 'bob';
    ip = '10.1.1.3';
    await service.refresh();
    expect(service.host, 'bob.local');
    expect((await query('bob.local')).answers.single.data, [10, 1, 1, 3]);
    ip = null;
    await service.refresh();
    expect(service.ready, isFalse);
    expect(service.error, '未连接局域网');
    username = 'alice';
    ip = '10.1.1.2';
  });

  test('已发布名称遇到持续冲突后自动换名，不覆盖另一个设备', () async {
    await boot();
    final conflict = DnsPacket(
      response: true,
      answers: [
        DnsRecord('alice.local', 1, Uint8List.fromList([10, 1, 1, 3])),
      ],
    ).encode();
    client.send(conflict, InternetAddress.loopbackIPv4, service.port!);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    client.send(conflict, InternetAddress.loopbackIPv4, service.port!);
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    expect(service.ready, isTrue);
    expect(service.host, 'alice-123456.local');
    expect((await query(service.host!)).answers.single.data, [10, 1, 1, 2]);
  });
}
