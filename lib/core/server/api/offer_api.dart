// SPDX-License-Identifier: GPL-3.0-only

/// 接收侧路由：/api/v1/offers 与 /api/v1/offers/:id/decision。
///
/// 没有这两条，HttpOfferTransport 投出去的帧会在对端 404——
/// 也就是「发得出、收不到」。
library;

import 'dart:convert';
import 'dart:io';

import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/offers/offer_service_impl.dart';
import 'package:lan_simple_file/core/server/response.dart';
import 'package:lan_simple_file/core/server/router.dart';

/// 读取 JSON 请求体的上限：offer 只有元数据，64KB 足够。
const int kMaxOfferBodyBytes = 64 * 1024;

/// 把 offer 相关路由注册到 [router]。
void registerOfferRoutes(Router router, OfferServiceImpl service) {
  router.post('/api/v1/offers', offerProposeHandler(service));
  router.post('/api/v1/offers/:id/decision', offerDecisionHandler(service));
  router.get('/api/v1/offers', offerListHandler(service));
}
/// POST /api/v1/offers —— 收到别人发来的 offer。
Handler offerProposeHandler(OfferServiceImpl service) {
  return (HttpRequest request) async {
    final Map<String, Object?> body = await _readJsonObject(request);
    try {
      await service.receiveProposeFrame(body);
    } on LanFileException catch (error) {
      await errorResponse(request.response, error);
      return;
    }
    await jsonResponse(request.response, HttpStatus.ok, <String, Object?>{
      'ok': true,
    });
  };
}

/// POST /api/v1/offers/:id/decision —— 收到对方对某个 offer 的决策。
Handler offerDecisionHandler(OfferServiceImpl service) {
  return (HttpRequest request) async {
    final String id = _segmentOrEmpty(request.uri, 3);
    if (id.isEmpty) {
      await errorResponse(
        request.response,
        const LanFileException(LanFileErrorCode.invalidArgument, '缺少 offer id'),
      );
      return;
    }
    final Map<String, Object?> body = await _readJsonObject(request);
    try {
      await service.receiveDecisionFrame(id, body);
    } on LanFileException catch (error) {
      await errorResponse(request.response, error);
      return;
    }
    await jsonResponse(request.response, HttpStatus.ok, <String, Object?>{
      'ok': true,
    });
  };
}

/// GET /api/v1/offers —— 待决策列表（接收方 UI 用它弹窗）。
Handler offerListHandler(OfferServiceImpl service) {
  return (HttpRequest request) async {
    final List<Map<String, Object?>> items = <Map<String, Object?>>[];
    await for (final List<OfferView> batch in service.watchIncoming().take(1)) {
      for (final OfferView v in batch) {
        items.add(<String, Object?>{
          'id': v.id,
          'from': v.fromLabel,
          'origin': v.origin.name,
          'sizeTotal': v.sizeTotal,
          'status': v.status,
          'note': v.note,
          'createdAt': v.createdAt.toUtc().millisecondsSinceEpoch,
          'expireAt': v.expireAt.toUtc().millisecondsSinceEpoch,
          'files': v.files
              .map((OfferViewFile f) => <String, Object?>{
                    'name': f.name,
                    'size': f.size,
                    'mime': f.mime,
                  })
              .toList(growable: false),
        });
      }
    }
    await jsonResponse(request.response, HttpStatus.ok, <String, Object?>{
      'items': items,
    });
  };
}

String _segmentOrEmpty(Uri uri, int index) {
  final List<String> parts = uri.path.split('/');
  return index < parts.length ? parts[index] : '';
}

/// 读 JSON 对象体；超限先排空再抛 413，避免连接被重置。
Future<Map<String, Object?>> _readJsonObject(HttpRequest request) async {
  final List<int> bytes = <int>[];
  bool exceeded = false;
  await for (final List<int> chunk in request) {
    if (exceeded) continue; // 已超限，继续排空但不累积
    bytes.addAll(chunk);
    if (bytes.length > kMaxOfferBodyBytes) {
      exceeded = true;
      bytes.clear();
    }
  }
  if (exceeded) {
    throw const LanFileException(
      LanFileErrorCode.invalidArgument,
      '请求体超过上限',
      httpStatus: HttpStatus.requestEntityTooLarge,
    );
  }
  if (bytes.isEmpty) {
    throw const LanFileException(
      LanFileErrorCode.invalidArgument,
      '请求体为空',
    );
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on FormatException catch (error) {
    throw LanFileException(
      LanFileErrorCode.invalidArgument,
      '请求体不是合法 JSON',
      cause: error,
    );
  }
  if (decoded is! Map<String, Object?>) {
    throw const LanFileException(
      LanFileErrorCode.invalidArgument,
      '请求体必须是 JSON 对象',
    );
  }
  return decoded;
}
