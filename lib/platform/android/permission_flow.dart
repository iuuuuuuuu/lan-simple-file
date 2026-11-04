// SPDX-License-Identifier: GPL-3.0-only

/// 安卓权限引导流：通知（13+）→ 电池优化白名单 → SAF 授权。
///
/// 三步是有序的，因为后一步的可用性依赖前一步：
/// - 通知被拒 → 前台服务通知不可见，系统会直接把服务降级，共享等于半残；
/// - 电池优化未豁免 → 息屏后进程被冻结，对端取件超时；
/// - SAF 未授权 → 根本没有可共享的目录。
///
/// 与 [ForegroundServiceMachine] 一样，判定逻辑是纯函数，
/// 平台调用收敛在 [PermissionBridge] 一条通道里，便于单测与替换。
library;

import 'package:flutter/services.dart';

/// 权限通道名，与 Kotlin 侧 kPermissionChannelName 必须一致。
const String kPermissionChannelName = 'lan.simple.file/permissions';

/// 权限引导步骤，顺序即 UI 展示顺序。
enum PermissionStep {
  /// Android 13+ 的运行时通知权限。
  notifications('通知权限', '共享中状态需要常驻通知，没有通知权限系统会拒绝前台服务'),

  /// 电池优化白名单（Doze 豁免）。
  batteryOptimization(
    '电池优化',
    '未加入白名单时，息屏几分钟后系统会冻结进程，对方取件会失败',
  ),

  /// SAF 目录授权。
  safGrant('文件访问', '需要选择一个目录或文件授权后，才能对外共享');

  const PermissionStep(this.title, this.explanation);

  /// 步骤标题。
  final String title;

  /// 为什么需要这一步；文案不得为空。
  final String explanation;

  /// 下一步；已是最后一步时返回 null。
  PermissionStep? get next => switch (this) {
    PermissionStep.notifications => PermissionStep.batteryOptimization,
    PermissionStep.batteryOptimization => PermissionStep.safGrant,
    PermissionStep.safGrant => null,
  };
}

/// 单步的授权状态。
enum PermissionGrantState {
  granted,
  denied,

  /// 本次流程里还用不上（例如 Android 12 及以下没有通知运行时权限）。
  notRequired,

  /// 平台说不了（通道缺失等），不能当成已授权。
  unknown,
}

/// 一步的检查结果。
final class PermissionCheck {
  const PermissionCheck({
    required this.step,
    required this.state,
    this.detail,
  });

  final PermissionStep step;
  final PermissionGrantState state;

  /// 额外说明；可为空，非空时不得是空串。
  final String? detail;

  bool get satisfied =>
      state == PermissionGrantState.granted ||
      state == PermissionGrantState.notRequired;

  /// 给用户看的文案。缺项时说清「为什么」与「怎么办」。
  String get userMessage {
    if (satisfied) {
      return '${step.title}：已就绪';
    }
    if (state == PermissionGrantState.unknown) {
      return '${step.title}：无法确认状态（${detail ?? '平台未返回'}）';
    }
    return '${step.title}：未授权。${step.explanation}';
  }

  @override
  String toString() => 'PermissionCheck(${step.name}, ${state.name})';
}

/// 一次完整检查的结论。
final class PermissionReport {
  const PermissionReport({required this.checks, required this.androidSdk});

  /// 按 [PermissionStep] 的声明顺序排列。
  final List<PermissionCheck> checks;

  /// 平台报告的 API level；非安卓时为 0。
  final int androidSdk;

  /// 第一个未满足的步骤；全部满足时为 null。
  PermissionStep? get firstBlocking {
    for (final PermissionCheck check in checks) {
      if (!check.satisfied) {
        return check.step;
      }
    }
    return null;
  }

  /// 是否全部就绪。
  bool get allSatisfied => firstBlocking == null;

  /// 未满足的步骤，按顺序。
  List<PermissionStep> get blockingSteps => <PermissionStep>[
    for (final PermissionCheck check in checks)
      if (!check.satisfied) check.step,
  ];

  /// 可直接展示的逐条文案。
  List<String> get userMessages => <String>[
    for (final PermissionCheck check in checks) check.userMessage,
  ];

  PermissionCheck? checkFor(PermissionStep step) {
    for (final PermissionCheck check in checks) {
      if (check.step == step) {
        return check;
      }
    }
    return null;
  }
}

/// 权限检查的平台桥。
final class PermissionBridge {
  // 私有字段与公开命名参数同名冲突，无法用 initializing formal。
  // ignore: prefer_initializing_formals
  const PermissionBridge({MethodChannel? channel}) : _channel = channel;

  final MethodChannel? _channel;

  MethodChannel get _resolved =>
      _channel ?? const MethodChannel(kPermissionChannelName);

  /// 读平台 API level；非安卓返回 0（不抛错，让引导流能在桌面跑通）。
  Future<int> androidSdk() async {
    try {
      final Object? value = await _resolved.invokeMethod<Object?>('androidSdk');
      if (value is int) {
        return value;
      }
      return 0;
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }

  /// 查询各步骤的授权状态。
  ///
  /// 返回 Map<步骤名, 状态名>；缺失的键按 unknown 处理，不当成已授权。
  Future<Map<String, String>> queryStates() async {
    try {
      final Object? value = await _resolved.invokeMethod<Object?>(
        'queryStates',
      );
      if (value is Map) {
        return <String, String>{
          for (final MapEntry<Object?, Object?> entry in value.entries)
            if (entry.key is String && entry.value is String)
              entry.key! as String: entry.value! as String,
        };
      }
      return const <String, String>{};
    } on MissingPluginException {
      return const <String, String>{};
    } on PlatformException {
      return const <String, String>{};
    }
  }

  /// 发起某一步的授权请求；返回平台是否认为已授权。
  ///
  /// 失败上抛 [PermissionFlowFailure]，不静默返回 false——否则「用户拒绝」与
  /// 「通道坏了」会混为一谈。
  Future<bool> request(PermissionStep step) async {
    try {
      final Object? value = await _resolved.invokeMethod<Object?>(
        'request',
        <String, Object?>{'step': step.name},
      );
      return value == true;
    } on MissingPluginException catch (error) {
      throw PermissionFlowFailure(
        PermissionFailureKind.notAndroid,
        '权限通道不可用',
        cause: error,
      );
    } on PlatformException catch (error) {
      throw PermissionFlowFailure(
        PermissionFailureKind.requestFailed,
        '${error.code}: ${error.message ?? '(无消息)'}',
        cause: error,
      );
    }
  }
}

/// 权限引导失败的可判定类型。
enum PermissionFailureKind { notAndroid, requestFailed }

/// 权限引导的失败载体。
final class PermissionFlowFailure implements Exception {
  const PermissionFlowFailure(this.kind, this.message, {this.cause});

  final PermissionFailureKind kind;
  final String message;
  final Object? cause;

  String get userMessage => switch (kind) {
    PermissionFailureKind.notAndroid => '当前设备不是安卓，不需要这套权限引导',
    PermissionFailureKind.requestFailed => '授权请求失败：$message',
  };

  @override
  String toString() => 'PermissionFlowFailure(${kind.name}): $message';
}

/// 权限引导控制器：把「查状态 → 找第一个缺项 → 请求」串起来。
final class PermissionFlow {
  PermissionFlow({required this.bridge});

  final PermissionBridge bridge;

  /// 跑一次完整检查并按需修补。
  ///
  /// [interactive] 为 false 时只查询不请求（用于首页静默展示缺项）。
  Future<PermissionReport> run({bool interactive = true}) async {
    final int sdk = await bridge.androidSdk();
    Map<String, String> states = await bridge.queryStates();

    // 通知权限在 Android 13 (API 33) 以下不是运行时权限，标 notRequired。
    // sdk 为 0 表示非安卓或平台没答，此时不动状态，让它如实停在 unknown/denied。
    final bool notificationIsRuntimePermission = sdk >= 33;
    if (!notificationIsRuntimePermission &&
        sdk > 0 &&
        _stateOf(states, PermissionStep.notifications) != 'granted') {
      states = <String, String>{
        ...states,
        PermissionStep.notifications.name: 'notRequired',
      };
    }

    if (!interactive) {
      return _reportOf(states, sdk);
    }

    // 按顺序修补第一个缺项；一次只推进一步，避免同时弹多个系统对话框。
    final PermissionStep? blocking = _reportOf(states, sdk).firstBlocking;
    if (blocking != null) {
      final bool granted = await bridge.request(blocking);
      states = <String, String>{
        ...states,
        blocking.name: granted ? 'granted' : 'denied',
      };
    }
    return _reportOf(states, sdk);
  }

  /// 只查询，不请求。
  Future<PermissionReport> inspect() => run(interactive: false);

  PermissionReport _reportOf(Map<String, String> states, int sdk) {
    return PermissionReport(
      androidSdk: sdk,
      checks: <PermissionCheck>[
        for (final PermissionStep step in PermissionStep.values)
          PermissionCheck(
            step: step,
            state: _grantOf(_stateOf(states, step)),
            detail: states[step.name],
          ),
      ],
    );
  }

  static String? _stateOf(Map<String, String> states, PermissionStep step) =>
      states[step.name];

  static PermissionGrantState _grantOf(String? raw) => switch (raw) {
    'granted' => PermissionGrantState.granted,
    'denied' => PermissionGrantState.denied,
    'notRequired' => PermissionGrantState.notRequired,
    _ => PermissionGrantState.unknown,
  };
}

/// 退出前置校验：有未完成传输或被他人下载时要求二次确认。
final class ExitGuardDecision {
  const ExitGuardDecision({
    required this.needsConfirmation,
    required this.unfinishedTransfers,
    required this.activeDownloads,
  });

  final bool needsConfirmation;

  /// 未完成的传输数（上传与下载合计）。
  final int unfinishedTransfers;

  /// 正在被他人下载的会话数。
  final int activeDownloads;

  /// 二次确认对话框的正文；不需要确认时为空串。
  String get confirmationMessage {
    if (!needsConfirmation) {
      return '';
    }
    final List<String> parts = <String>[];
    if (unfinishedTransfers > 0) {
      parts.add('$unfinishedTransfers 个传输进行中');
    }
    if (activeDownloads > 0) {
      parts.add('$activeDownloads 台设备正在下载');
    }
    return '退出后这些都会中断：${parts.join('，')}。确定要退出吗？';
  }

  @override
  String toString() =>
      'ExitGuardDecision(confirm: $needsConfirmation, '
      'transfers: $unfinishedTransfers, downloads: $activeDownloads)';
}

/// 判定退出是否需要二次确认。
///
/// 纯函数：负数按 0 处理，任一计数不为 0 即需要确认。
ExitGuardDecision evaluateExitGuard({
  required int unfinishedTransfers,
  required int activeDownloads,
}) {
  final int transfers = unfinishedTransfers < 0 ? 0 : unfinishedTransfers;
  final int downloads = activeDownloads < 0 ? 0 : activeDownloads;
  return ExitGuardDecision(
    needsConfirmation: transfers > 0 || downloads > 0,
    unfinishedTransfers: transfers,
    activeDownloads: downloads,
  );
}
