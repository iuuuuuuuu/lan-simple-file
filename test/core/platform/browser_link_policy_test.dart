// SPDX-License-Identifier: GPL-3.0-only

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/net/lan_address.dart';
import 'package:lan_simple_file/core/platform/browser_link_policy.dart';

void main() {
  test('nested device domains are repaired without widening proxy bypass', () async {
    const domain = 'alice.p-aaaaaaaaaaaaa.local';
    final repaired = <String>[];
    final policy = BrowserLinkPolicy(
      proxyQuery: () async => const WindowsBrowserProxy(enabled: true, server: '127.0.0.1:7890', bypass: '<local>'),
      proxyRepair: (host) async {
        repaired.add(host);
        return WindowsBrowserProxy(enabled: true, server: '127.0.0.1:7890', bypass: '<local>;$host');
      },
    );
    expect(await policy.domainFor(domain), domain);
    expect(repaired, [domain]);
    expect(await policy.domainFor('$domain.example'), isNull);
    expect(repaired, [domain]);
  });
  test('local 绕过只匹配无点主机，不能误认为包含 mDNS 域名', () {
    const proxy = WindowsBrowserProxy(
      enabled: true,
      server: '127.0.0.1:7890',
      bypass: 'localhost;127.*;10.*;<local>',
    );
    expect(proxy.usesProxyFor('alice.local'), true);
    expect(proxy.usesProxyFor('alice'), false);
    expect(proxy.usesProxyFor('10.1.2.3'), false);
  });

  test('支持大小写和通配符绕过，不把相似域名当成绕过规则', () {
    const proxy = WindowsBrowserProxy(
      enabled: true,
      server: 'http=127.0.0.1:7890;https=127.0.0.1:7890',
      bypass: '*.LOCAL;host?.example;localhost',
    );
    expect(proxy.usesProxyFor('alice.local'), false);
    expect(proxy.usesProxyFor('host1.example'), false);
    expect(proxy.usesProxyFor('alice.local.example'), true);
  });

  test('关闭代理、缺少服务器或只代理 HTTPS 时不改变 HTTP 链接', () {
    for (final proxy in [
      const WindowsBrowserProxy(enabled: false, server: 'proxy', bypass: ''),
      const WindowsBrowserProxy(enabled: true, server: '', bypass: ''),
      const WindowsBrowserProxy(
        enabled: true,
        server: 'https=proxy',
        bypass: '',
      ),
    ]) {
      expect(proxy.usesProxyFor('alice.local'), false);
    }
  });

  test('代理不绕过 local 时生成可直连的局域网 IP 链接，保持端口和凭证', () async {
    final policy = BrowserLinkPolicy(
      proxyRepair: null,
      proxyQuery: () async => const WindowsBrowserProxy(
        enabled: true,
        server: '127.0.0.1:7890',
        bypass: '10.*;<local>',
      ),
    );
    final domain = await policy.domainFor('alice.local');
    expect(domain, isNull);
    final uri = buildWebShareUrl(
      host: '10.1.2.3',
      port: 47778,
      shareId: ShareId.parse('Sabc'),
      token: 'signed-token',
      localDomain: domain,
    );
    expect(uri.host, '10.1.2.3');
    expect(uri.port, 47778);
    expect(uri.queryParameters['k'], 'signed-token');
  });

  test('未知代理状态回退 IP，已绕过 local 时保留原域名', () async {
    final unknown = BrowserLinkPolicy(proxyQuery: () async => null);
    expect(await unknown.domainFor('alice.local'), isNull);
    final bypassed = BrowserLinkPolicy(
      proxyQuery: () async => const WindowsBrowserProxy(
        enabled: true,
        server: 'proxy',
        bypass: '*.local',
      ),
    );
    expect(await bypassed.domainFor('alice.local'), 'alice.local');
    expect(await bypassed.domainFor(null), isNull);
  });

  test('代理查询抛错时仍能生成 IP 链接', () async {
    final policy = BrowserLinkPolicy(
      proxyQuery: () async =>
          throw const ProcessException('powershell.exe', []),
    );
    expect(await policy.domainFor('alice.local'), isNull);
  });

  test('PAC 规则未知时不把 local 链接交给浏览器代理', () async {
    const proxy = WindowsBrowserProxy(
      enabled: false,
      server: '',
      bypass: '',
      autoConfigUrl: 'http://127.0.0.1:7890/proxy.pac',
    );
    expect(proxy.usesProxyFor('alice.local'), isTrue);
  });

  test('修复代理绕过后使用域名，保留端口和凭证', () async {
    final repairedDomains = <String>[];
    final policy = BrowserLinkPolicy(
      proxyQuery: () async => const WindowsBrowserProxy(
        enabled: true,
        server: '127.0.0.1:7890',
        bypass: '10.*;<local>',
      ),
      proxyRepair: (domain) async {
        repairedDomains.add(domain);
        return WindowsBrowserProxy(
          enabled: true,
          server: '127.0.0.1:7890',
          bypass: '10.*;<local>;$domain',
        );
      },
    );
    final domain = await policy.domainFor('alice.local');
    final uri = buildWebShareUrl(
      host: '10.1.2.3',
      port: 47778,
      shareId: ShareId.parse('Sabc'),
      token: 'signed-token',
      localDomain: domain,
    );
    expect(repairedDomains, ['alice.local']);
    expect(uri.host, 'alice.local');
    expect(uri.port, 47778);
    expect(uri.queryParameters['k'], 'signed-token');
    final home = buildWebHomeUrl(
      host: '10.1.2.3',
      port: 80,
      localDomain: domain,
    );
    expect(home.toString(), 'http://alice.local/');
    expect(home.queryParameters, isEmpty);
  });

  test('修复失败或未真正绕过时仍回退 IP', () async {
    for (final repair in <Future<WindowsBrowserProxy?> Function(String)>[
      (_) async => null,
      (_) async => throw const ProcessException('powershell.exe', []),
      (_) async => const WindowsBrowserProxy(
        enabled: true,
        server: 'proxy',
        bypass: '10.*',
      ),
    ]) {
      final policy = BrowserLinkPolicy(
        proxyQuery: () async => const WindowsBrowserProxy(
          enabled: true,
          server: 'proxy',
          bypass: '',
        ),
        proxyRepair: repair,
      );
      expect(await policy.domainFor('alice.local'), isNull);
    }
  });

  test('PAC、未知配置和非法域名不改写代理设置', () async {
    var repairs = 0;
    Future<WindowsBrowserProxy?> repair(String _) async {
      repairs++;
      return null;
    }

    final pac = BrowserLinkPolicy(
      proxyQuery: () async => const WindowsBrowserProxy(
        enabled: true,
        server: 'proxy',
        bypass: '',
        autoConfigUrl: 'http://proxy/pac',
      ),
      proxyRepair: repair,
    );
    expect(await pac.domainFor('alice.local'), isNull);
    final unknown = BrowserLinkPolicy(
      proxyQuery: () async => null,
      proxyRepair: repair,
    );
    expect(await unknown.domainFor('alice.local'), isNull);
    final manual = BrowserLinkPolicy(
      proxyQuery: () async =>
          const WindowsBrowserProxy(enabled: true, server: 'proxy', bypass: ''),
      proxyRepair: repair,
    );
    expect(await manual.domainFor('alice.local.example'), isNull);
    expect(await manual.domainFor('alice.local;evil'), isNull);
    expect(repairs, 0);
  });
}
