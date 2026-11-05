// SPDX-License-Identifier: GPL-3.0-only

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/net/lan_address.dart';
import 'package:lan_simple_file/core/platform/browser_link_policy.dart';

void main() {
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

  test('未知代理状态和已绕过 local 时仍保留原域名', () async {
    final unknown = BrowserLinkPolicy(proxyQuery: () async => null);
    expect(await unknown.domainFor('alice.local'), 'alice.local');
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
}
