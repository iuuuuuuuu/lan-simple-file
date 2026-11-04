// SPDX-License-Identifier: GPL-3.0-only

/// 真实接线测试用的最小探针。
///
/// 只实现设置页真正用到的方法，其余一律抛 UnimplementedError：
/// 这样「误用到没实现的存储/公告能力」会当场炸，而不是静默返回空值。
library;

import 'package:lan_simple_file/core/contracts/contracts.dart';

/// 可记账的存储探针：只实现 settings 两个方法。
final class RecordingSettingsStore implements LanFileStore {
  RecordingSettingsStore();

  /// 键 -> 值。
  final Map<String, String> values = <String, String>{};

  /// 每次 setSetting 的调用记录。
  final List<({String key, String value})> writes =
      <({String key, String value})>[];

  @override
  Future<String?> getSetting(String key) async => values[key];

  @override
  Future<void> setSetting(String key, String value) async {
    values[key] = value;
    writes.add((key: key, value: value));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('设置页不应调用这个存储方法');
}

/// 可记账的公告探针：只关心 probe 次数与丢弃计数。
final class RecordingAnnounce implements AnnounceService {
  RecordingAnnounce({this.degraded, RejectedDatagramCounter? counter})
      : rejected = counter ?? EmptyRejectedCounter();

  /// probe 被调用次数。
  int probes = 0;

  /// 降级原因。
  final String? degraded;

  @override
  final RejectedDatagramCounter rejected;

  @override
  Future<void> probe() async {
    probes++;
  }

  @override
  String? get degradedReason => degraded;

  @override
  bool get isSendOnly => degraded != null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('设置页不应调用这个公告方法');
}

/// 全零的丢弃计数。
final class EmptyRejectedCounter implements RejectedDatagramCounter {
  @override
  int get badSignature => 0;

  @override
  int get malformed => 0;

  @override
  int get fromSelf => 0;

  @override
  int get unknownPeerId => 0;

  @override
  List<String> get recentReasons => const <String>[];
}
