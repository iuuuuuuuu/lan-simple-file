// SPDX-License-Identifier: GPL-3.0-only

/// offer 的线上编解码与本地字段投影。
///
/// 关键约定（产品硬约束，写在这里防漂移）：
/// 1. offer 里**只有元数据**：name / size / mime / itemKey。
///    绝不内联文件内容字节——「接受前零字节」是从编码层就守住的，
///    不能只靠调用方自觉。
/// 2. `OfferRecord.filesJson` 是唯一载体：契约没有给 offer 单独的 files 表，
///    也不允许改契约，因此列表编解码在这里集中，别处不得自拼 JSON。
/// 3. 拒绝理由也存进同一列（见 [OfferEnvelope]），因为契约的 OfferRecord
///    没有 rejectReason 字段；用独立字段会静默丢失发起方最需要的那条信息。
/// 4. 解析严格：缺字段一律抛 invalidArgument，不静默补默认值。
///    否则缺 size 的条目会以 0 字节入库，接收方会做出错误的磁盘余量判断。
library;

import 'dart:convert';

import '../contracts/contracts.dart';

/// offer 里的一个文件条目（**不含内容**）。
final class OfferFile {
  const OfferFile({
    required this.itemKey,
    required this.name,
    required this.size,
    this.mime,
    this.isDir = false,
  });

  /// 发起方本地的稳定键；接收方只用它来请求内容，不据此访问磁盘。
  final String itemKey;

  final String name;

  /// 字节数；目录为 0。
  final int size;

  final String? mime;

  final bool isDir;

  Map<String, Object?> toJson() => <String, Object?>{
        'itemKey': itemKey,
        'name': name,
        'size': size,
        'mime': ?mime,
        'isDir': isDir,
      };

  static OfferFile fromJson(Map<String, Object?> json) {
    final Object? name = json['name'];
    final Object? size = json['size'];
    final Object? itemKey = json['itemKey'];
    if (name is! String || between(name) || itemKey is! String) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        'offer 文件条目缺少 name 或 itemKey',
      );
    }
    if (size is! int || size < 0) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        'offer 文件条目的 size 必须是非负整数',
      );
    }
    final Object? mime = json['mime'];
    if (mime != null && mime is! String) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        'offer 文件条目的 mime 必须是字符串',
      );
    }
    final Object? isDir = json['isDir'];
    if (isDir != null && isDir is! bool) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        'offer 文件条目的 isDir 必须是布尔',
      );
    }
    return OfferFile(
      itemKey: itemKey,
      name: name,
      size: size,
      mime: mime as String?,
      isDir: (isDir as bool?) ?? false,
    );
  }

  /// 名字是否为空（抽出来只为让上面的条件读起来不费劲）。
  static bool between(String value) => value.trim().isEmpty;
}

/// `filesJson` 列的完整结构：文件列表 + 可选的拒绝理由。
///
/// 为什么把拒绝理由塞进同一列：契约 OfferRecord 没有 rejectReason，
/// 而任务要求「发起方可见拒绝与理由」。不改契约的前提下，这是唯一不丢信息的做法。
final class OfferEnvelope {
  const OfferEnvelope({required this.files, this.rejectReason});

  final List<OfferFile> files;

  /// 接收方拒绝时填写；其它状态为 null。
  final String? rejectReason;

  int get sizeTotal =>
      files.fold<int>(0, (int sum, OfferFile f) => sum + f.size);

  String encode() => jsonEncode(<String, Object?>{
        'files': files.map((OfferFile f) => f.toJson()).toList(growable: false),
        'rejectReason': ?rejectReason,
      });

  static OfferEnvelope decode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        'offer 的 filesJson 不是合法 JSON',
        cause: error,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        'offer 的 filesJson 顶层必须是对象',
      );
    }
    final Object? filesRaw = decoded['files'];
    if (filesRaw is! List<Object?>) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        'offer 的 filesJson 缺少 files 数组',
      );
    }
    final List<OfferFile> files = filesRaw.map((Object? item) {
      if (item is! Map<String, Object?>) {
        throw const LanFileException(
          LanFileErrorCode.invalidArgument,
          'offer 的 files 里出现了非对象条目',
        );
      }
      return OfferFile.fromJson(item);
    }).toList(growable: false);

    final Object? reason = decoded['rejectReason'];
    if (reason != null && reason is! String) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        'offer 的 rejectReason 必须是字符串',
      );
    }
    return OfferEnvelope(files: files, rejectReason: reason as String?);
  }

  /// 带上新的拒绝理由（其余字段不变）。
  OfferEnvelope withRejectReason(String? reason) =>
      OfferEnvelope(files: files, rejectReason: reason);
}

/// 发往对端的 offer 请求体。
Map<String, Object?> encodeProposeFrame({
  required String offerId,
  required PeerId fromPeer,
  required PeerId toPeer,
  required List<OfferFile> files,
  required DateTime createdAt,
  required DateTime expireAt,
  String? note,
}) =>
    <String, Object?>{
      'offerId': offerId,
      'from': fromPeer.value,
      'to': toPeer.value,
      'files': files.map((OfferFile f) => f.toJson()).toList(growable: false),
      'createdAt': createdAt.toUtc().millisecondsSinceEpoch,
      'expireAt': expireAt.toUtc().millisecondsSinceEpoch,
      'note': ?note,
    };

/// 接收方的决策帧。
Map<String, Object?> encodeDecisionFrame({
  required String offerId,
  required bool accepted,
  String? reason,
  String? shareId,
  String? token,
}) =>
    <String, Object?>{
      'offerId': offerId,
      'accepted': accepted,
      'reason': ?reason,
      'shareId': ?shareId,
      'token': ?token,
    };
