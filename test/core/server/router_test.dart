// SPDX-License-Identifier: GPL-3.0-only

/// Router 的匹配语义测试：纯函数级，不涉及网络。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/server/router.dart';

Future<void> _noop(HttpRequest request) async {}

void main() {
  group('Router', () {
    test('精确匹配并忽略末尾斜杠与重复斜杠', () {
      final Router router = Router();
      router.get('/api/v1/ping', _noop);

      expect(router.handlerFor('GET', '/api/v1/ping'), isNotNull);
      expect(router.handlerFor('GET', '/api/v1/ping/'), isNotNull);
      expect(router.handlerFor('GET', '//api//v1//ping'), isNotNull);
      expect(router.handlerFor('GET', '/api/v1'), isNull);
      expect(router.handlerFor('GET', '/api/v1/ping/extra'), isNull);
    });

    test('方法大小写不敏感', () {
      final Router router = Router();
      router.get('/x', _noop);
      expect(router.handlerFor('get', '/x'), isNotNull);
      expect(router.handlerFor('GET', '/x'), isNotNull);
    });

    test('HEAD 在没有显式 HEAD 路由时回退到 GET', () {
      final Router router = Router();
      router.get('/x', _noop);
      expect(router.handlerFor('HEAD', '/x'), isNotNull);
    });

    test('显式 HEAD 路由优先于 GET 回退', () {
      final Router router = Router();
      Future<void> getHandler(HttpRequest request) async {}
      Future<void> headHandler(HttpRequest request) async {}
      router.get('/x', getHandler);
      router.head('/x', headHandler);

      expect(router.length, 2);
      expect(router.handlerFor('HEAD', '/x'), same(headHandler));
      expect(router.handlerFor('GET', '/x'), same(getHandler));
    });

    test('路径参数按名取出', () {
      final Router router = Router();
      router.get('/s/:shareId/tree', _noop);

      final RouteMatch? match = router.match('GET', '/s/abc123/tree');
      expect(match, isNotNull);
      expect(match!.params['shareId'], 'abc123');

      expect(router.match('GET', '/s//tree'), isNull, reason: '空段不算参数');
      expect(router.match('GET', '/s/abc/tree/extra'), isNull);
    });

    test('通配末段 * 吸收任意剩余路径', () {
      final Router router = Router();
      router.get('/web/*', _noop);

      expect(router.handlerFor('GET', '/web/'), isNotNull);
      expect(router.handlerFor('GET', '/web/a/b/c.css'), isNotNull);
      // `/web` 与 `/web/*` 的段数不同，但通配符允许零剩余段命中。
      expect(router.handlerFor('GET', '/web'), isNotNull);
    });

    test('allowedMethods 反映路径已注册的方法，并补上 HEAD', () {
      final Router router = Router();
      router.get('/api/v1/profile', _noop);
      router.put('/api/v1/profile', _noop);

      expect(router.allowedMethods('/api/v1/profile'), <String>{
        'GET',
        'PUT',
        'HEAD',
      });
      expect(router.allowedMethods('/api/v1/none'), isEmpty);
    });

    test('重复注册同形路由直接抛 ArgumentError', () {
      final Router router = Router();
      router.get('/a/:id', _noop);
      expect(() => router.get('/a/:name', _noop), throwsArgumentError);

      router.get('/', _noop);
      expect(() => router.get('/', _noop), throwsA(isA<ArgumentError>()));
      expect(
        () => router.get('', _noop),
        throwsA(isA<ArgumentError>()),
        reason: '不带前导斜杠的路径不是合法路由',
      );
    });

    test('大小写敏感开关生效', () {
      final Router sensitive = Router();
      sensitive.get('/Ping', _noop);
      expect(sensitive.handlerFor('GET', '/Ping'), isNotNull);
      expect(sensitive.handlerFor('GET', '/ping'), isNull);

      final Router insensitive = Router(caseSensitive: false);
      insensitive.get('/Ping', _noop);
      expect(insensitive.handlerFor('GET', '/ping'), isNotNull);
    });
  });
}
