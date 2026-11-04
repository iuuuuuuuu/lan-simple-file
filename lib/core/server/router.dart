// SPDX-License-Identifier: GPL-3.0-only

/// 最小路由表：精确段匹配、路径参数、HEAD 回退 GET、405 判定。
///
/// 只做分派，不做响应；响应的形状由 [Handler] 自己决定。
library;

import 'dart:async';
import 'dart:io';

/// 一个可执行的请求处理器。
typedef Handler = Future<void> Function(HttpRequest request);

/// 一条路由的匹配结果。
final class RouteMatch {
  const RouteMatch({required this.handler, this.params = const <String, String>{}});

  final Handler handler;

  /// 路径参数，键为路由里 `:name` 的 name 部分。
  final Map<String, String> params;
}

final class _Route {
  _Route(this.method, this.segments, this.handler);

  final String method;
  final List<String> segments;
  final Handler handler;
}

/// 方法与路径到处理器的映射表。
///
/// 路径按 `/` 切段比较，因此 `/a/b`、`/a/b/`、`//a//b` 等价；
/// 末段为 `*` 时匹配任意剩余段；段以 `:` 开头时匹配单个非空段并作为路径参数。
final class Router {
  Router({this.caseSensitive = true});

  /// 路径比较是否区分大小写。
  final bool caseSensitive;

  final List<_Route> _routes = <_Route>[];

  /// 已注册的路由条数。
  int get length => _routes.length;

  /// 注册一条路由；同一 method + path 重复注册视为编码错误，直接抛出。
  void add(String method, String path, Handler handler) {
    final String upper = method.toUpperCase();
    if (!path.startsWith('/')) {
      throw ArgumentError.value(path, 'path', '路由必须以 / 开头');
    }
    // `/` 切出来是空段列表，它正是根路径的合法表示。
    final List<String> segments = splitPath(path);
    final bool duplicated = _routes.any(
      (_Route route) =>
          route.method == upper &&
          route.segments.length == segments.length &&
          _sameShape(route.segments, segments),
    );
    if (duplicated) {
      throw ArgumentError.value(path, 'path', '路由重复注册: $upper $path');
    }
    _routes.add(_Route(upper, segments, handler));
  }

  void get(String path, Handler handler) => add('GET', path, handler);

  void put(String path, Handler handler) => add('PUT', path, handler);

  void post(String path, Handler handler) => add('POST', path, handler);

  void delete(String path, Handler handler) => add('DELETE', path, handler);

  void head(String path, Handler handler) => add('HEAD', path, handler);

  /// 匹配路由；找不到返回 null。
  ///
  /// [method] 为 HEAD 且没有显式 HEAD 路由时回退到 GET（HTTP 语义要求）。
  RouteMatch? match(String method, String path) {
    final String upper = method.toUpperCase();
    final List<String> segments = splitPath(path);
    final RouteMatch? direct = _matchWith(upper, segments);
    if (direct != null) return direct;
    if (upper == 'HEAD') return _matchWith('GET', segments);
    return null;
  }

  /// 冻结的公开入口：只要处理器，不关心路径参数。
  Handler? handlerFor(String method, String path) => match(method, path)?.handler;

  /// 该路径存在路由、但方法不匹配时返回允许的方法集合（供 405 + Allow 使用）。
  ///
  /// 路径本身没有注册任何方法时返回空集合，调用方据此回 404。
  Set<String> allowedMethods(String path) {
    final List<String> segments = splitPath(path);
    final Set<String> allowed = <String>{};
    for (final _Route route in _routes) {
      if (_matchSegments(route.segments, segments) != null) {
        allowed.add(route.method);
      }
    }
    if (allowed.contains('GET')) {
      allowed.add('HEAD');
    }
    return allowed;
  }

  RouteMatch? _matchWith(String method, List<String> segments) {
    for (final _Route route in _routes) {
      if (route.method != method) continue;
      final Map<String, String>? params = _matchSegments(route.segments, segments);
      if (params != null) {
        return RouteMatch(handler: route.handler, params: params);
      }
    }
    return null;
  }

  Map<String, String>? _matchSegments(List<String> pattern, List<String> actual) {
    final Map<String, String> params = <String, String>{};
    for (int i = 0; i < pattern.length; i++) {
      final String expected = pattern[i];
      if (expected == '*') {
        if (i != pattern.length - 1) return null;
        return params;
      }
      if (i >= actual.length) return null;
      final String segment = actual[i];
      if (expected.startsWith(':')) {
        if (segment.isEmpty) return null;
        params[expected.substring(1)] = segment;
        continue;
      }
      final String left = caseSensitive ? expected : expected.toLowerCase();
      final String right = caseSensitive ? segment : segment.toLowerCase();
      if (left != right) return null;
    }
    if (pattern.length != actual.length) return null;
    return params;
  }

  bool _sameShape(List<String> left, List<String> right) {
    for (int i = 0; i < left.length; i++) {
      final String a = left[i];
      final String b = right[i];
      final bool aParam = a.startsWith(':');
      final bool bParam = b.startsWith(':');
      if (aParam != bParam) return false;
      if (!aParam && a != b) return false;
    }
    return true;
  }

  /// 把路径切成段，丢弃空段，兼容末尾斜杠与重复斜杠。
  static List<String> splitPath(String path) {
    final List<String> segments = <String>[];
    for (final String segment in path.split('/')) {
      if (segment.isEmpty) continue;
      segments.add(segment);
    }
    return segments;
  }
}
