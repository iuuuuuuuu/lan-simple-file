// SPDX-License-Identifier: GPL-3.0-only

/// 安卓会话级前台服务：状态机的 Dart 侧，加上一条 MethodChannel 桥。
///
/// 产品硬约束（见 .agents/notes/implemented/feature/2026-11-04-android-session-scoped-sharing.md）：
/// 有活跃共享才起服务，无共享立即停止；Android 14+ 必须声明 dataSync 类型。
/// MulticastLock 只在共享期间持有，不常驻。
///
/// 本文件的分工：
/// - [ForegroundServiceState] 是**纯函数状态机**，不碰通道，可完整单测；
/// - [ForegroundServiceBridge] 只负责把「期望状态」推给 Kotlin，并把失败归类。
library;

import 'package:flutter/services.dart';

/// 前台服务通道名，与 Kotlin 侧 kForegroundChannelName 必须一致。
const String kForegroundChannelName = 'lan.simple.file/foreground';

/// 通知栏文案里的条目数/连接数上限，避免超长文本。
const int kForegroundMaxCount = 999999;

/// 前台服务的期望状态。
///
/// [shareCount] 是**条目数**（文件与目录合计），[connectedPeers] 是当前连着的设备数。
final class ForegroundServiceState {
  const ForegroundServiceState({
    required this.running,
    this.shareCount = 0,
    this.connectedPeers = 0,
  });

  /// 不起服务时的空状态。
  static const ForegroundServiceState stopped = ForegroundServiceState(
    running: false,
  );

  /// 是否应当有前台服务在跑。
  final bool running;

  /// 活跃共享里的条目数。
  final int shareCount;

  /// 已连接的对端数。
  final int connectedPeers;

  /// 是否持有 MulticastLock。与 [running] 严格同步：不常驻持锁。
  bool get holdsMulticastLock => running;

  /// 是否维持了会话级 WakeLock（仅在有传输时才需要，由调用方显式开关）。
  bool get isActive => running;

  /// 通知栏标题。
  String get notificationTitle => running ? '共享中' : '已停止共享';

  /// 通知栏正文：N 个文件 · 已连接 X 台。
  String get notificationBody =>
      '${_clampCount(shareCount)} 个文件 · 已连接 ${_clampCount(connectedPeers)} 台';

  /// 停止共享按钮的文案（通知栏 action 用）。
  String get stopActionLabel => '停止共享';

  /// 转为推送载荷。字段名与 Kotlin 侧解析保持一一对应。
  Map<String, Object?> toChannelArguments() => <String, Object?>{
    'running': running,
    'shareCount': _clampCount(shareCount),
    'connectedPeers': _clampCount(connectedPeers),
  };

  ForegroundServiceState copyWith({
    bool? running,
    int? shareCount,
    int? connectedPeers,
  }) {
    return ForegroundServiceState(
      running: running ?? this.running,
      shareCount: shareCount ?? this.shareCount,
      connectedPeers: connectedPeers ?? this.connectedPeers,
    );
  }

  @override
  String toString() =>
      'ForegroundServiceState(running: $running, '
      'shares: $shareCount, peers: $connectedPeers)';

  @override
  bool operator ==(Object other) =>
      other is ForegroundServiceState &&
      other.running == running &&
      other.shareCount == shareCount &&
      other.connectedPeers == connectedPeers;

  @override
  int get hashCode => Object.hash(running, shareCount, connectedPeers);

  static int _clampCount(int value) {
    if (value < 0) {
      return 0;
    }
    if (value > kForegroundMaxCount) {
      return kForegroundMaxCount;
    }
    return value;
  }
}

/// 「该不该起服务」的判定结果，附带原因以便 UI 与日志解释。
final class ForegroundDecision {
  const ForegroundDecision({
    required this.shouldRun,
    required this.reason,
    required this.nextState,
  });

  final bool shouldRun;

  /// 给人看的原因，不得为空串。
  final String reason;

  /// 判定之后应当推给平台的状态。
  final ForegroundServiceState nextState;

  @override
  String toString() =>
      'ForegroundDecision(shouldRun: $shouldRun, reason: $reason)';
}

/// 会话级前台服务的状态机。
///
/// 唯一输入是「当前活跃共享数与已连接数」，输出是「该不该起服务」。
/// 这里刻意不读任何全局状态、不碰通道，因此可以在纯 Dart 测试里跑满分支。
final class ForegroundServiceMachine {
  ForegroundServiceMachine({
    this.shareCount = 0,
    this.connectedPeers = 0,
  });

  /// 活跃共享的条目数；0 表示没有任何共享。
  int shareCount;

  /// 已连接的对端数。
  int connectedPeers;

  ForegroundServiceState _state = ForegroundServiceState.stopped;

  /// 当前状态。
  ForegroundServiceState get state => _state;

  /// 有共享才起服务：shareCount > 0 是唯一条件。
  ///
  /// 已连接数为 0 时仍然要起服务——共享是「可被访问」的承诺，
  /// 没人连着不代表没人会来取件。
  ForegroundDecision evaluate() {
    final bool shouldRun = shareCount > 0;
    final ForegroundServiceState next = shouldRun
        ? ForegroundServiceState(
            running: true,
            shareCount: shareCount,
            connectedPeers: connectedPeers,
          )
        : ForegroundServiceState.stopped;
    final String reason = shouldRun
        ? '有 $shareCount 个条目在共享，需要维持会话级前台服务'
        : '没有活跃共享，立即停止服务并释放组播锁';
    return ForegroundDecision(
      shouldRun: shouldRun,
      reason: reason,
      nextState: next,
    );
  }

  /// 更新计数并返回判定。负数按 0 处理，不抛异常（UI 抖动不该炸服务）。
  ForegroundDecision update({required int shareCount, int? connectedPeers}) {
    this.shareCount = shareCount < 0 ? 0 : shareCount;
    if (connectedPeers != null) {
      this.connectedPeers = connectedPeers < 0 ? 0 : connectedPeers;
    }
    final ForegroundDecision decision = evaluate();
    _state = decision.nextState;
    return decision;
  }

  /// 共享全部停止。
  ForegroundDecision clear() => update(shareCount: 0, connectedPeers: 0);

  @override
  String toString() => 'ForegroundServiceMachine($_state)';
}

/// 前台服务的错误码映射目标。
enum ForegroundFailureKind {
  /// 当前不是安卓运行时（通道不存在）。
  notAndroid,

  /// Android 13+ 未授予通知权限，前台服务无法显示通知。
  notificationDenied,

  /// 系统拒绝启动前台服务（后台限制、类型缺失等）。
  startRejected,

  /// 其它未归类的失败。
  unknown,
}

/// 一次前台服务调用失败的可判定描述。
final class ForegroundServiceFailure implements Exception {
  const ForegroundServiceFailure(this.kind, this.message, {this.cause});

  final ForegroundFailureKind kind;
  final String message;
  final Object? cause;

  /// 给用户看的文案；UI 直接展示，不解析 message。
  String get userMessage => switch (kind) {
    ForegroundFailureKind.notAndroid => '当前设备不是安卓，前台服务不可用',
    ForegroundFailureKind.notificationDenied =>
      '缺少通知权限，系统不允许显示"共享中"通知。请在设置里允许通知后重试',
    ForegroundFailureKind.startRejected =>
      '系统拒绝了前台服务启动，可能是后台限制。请允许后台运行后重试',
    ForegroundFailureKind.unknown => '前台服务调用失败：$message',
  };

  @override
  String toString() => 'ForegroundServiceFailure(${kind.name}): $message';
}

/// MethodChannel 桥：把状态机结论推给 Kotlin 侧。
///
/// 生产环境留空 channel 即用默认通道；测试可注入 mock channel。
final class ForegroundServiceBridge {
  // 私有字段与公开命名参数同名冲突，无法用 initializing formal。
  // ignore: prefer_initializing_formals
  const ForegroundServiceBridge({MethodChannel? channel}) : _channel = channel;

  final MethodChannel? _channel;

  MethodChannel get _resolved =>
      _channel ?? const MethodChannel(kForegroundChannelName);

  /// 把期望状态推给平台；幂等（重复推同一状态是安全的）。
  ///
  /// [state] 为 running=false 时，Kotlin 侧必须停止服务并释放 MulticastLock。
  Future<void> apply(ForegroundServiceState state) async {
    try {
      await _resolved.invokeMethod<void>('apply', state.toChannelArguments());
    } on MissingPluginException catch (error) {
      throw ForegroundServiceFailure(
        ForegroundFailureKind.notAndroid,
        '前台服务通道不可用',
        cause: error,
      );
    } on PlatformException catch (error) {
      throw _mapPlatformException(error);
    }
  }

  /// 查询平台当前是否真有服务在跑。
  ///
  /// 用于 App 冷启动后校正状态机：进程被杀过，Dart 侧状态是假的，
  /// 以平台为准。
  Future<bool> isRunning() async {
    try {
      final Object? value = await _resolved.invokeMethod<Object?>('isRunning');
      if (value is! bool) {
        throw ForegroundServiceFailure(
          ForegroundFailureKind.unknown,
          'isRunning 返回类型异常: ${value.runtimeType}',
        );
      }
      return value;
    } on MissingPluginException catch (error) {
      throw ForegroundServiceFailure(
        ForegroundFailureKind.notAndroid,
        '前台服务通道不可用',
        cause: error,
      );
    } on PlatformException catch (error) {
      throw _mapPlatformException(error);
    }
  }

  /// 请求一次组播锁状态同步；返回平台侧是否持有。
  ///
  /// 与 [apply] 分开是为了能在不改变服务状态时单独校正锁。
  Future<bool> syncMulticastLock({required bool shouldHold}) async {
    try {
      final Object? value = await _resolved.invokeMethod<Object?>(
        'syncMulticastLock',
        <String, Object?>{'hold': shouldHold},
      );
      if (value is! bool) {
        throw ForegroundServiceFailure(
          ForegroundFailureKind.unknown,
          'syncMulticastLock 返回类型异常: ${value.runtimeType}',
        );
      }
      return value;
    } on MissingPluginException catch (error) {
      throw ForegroundServiceFailure(
        ForegroundFailureKind.notAndroid,
        '前台服务通道不可用',
        cause: error,
      );
    } on PlatformException catch (error) {
      throw _mapPlatformException(error);
    }
  }

  ForegroundServiceFailure _mapPlatformException(PlatformException error) {
    final ForegroundFailureKind kind = switch (error.code) {
      'notificationDenied' => ForegroundFailureKind.notificationDenied,
      'startRejected' ||
      'foregroundServiceStartNotAllowedException' =>
        ForegroundFailureKind.startRejected,
      _ => ForegroundFailureKind.unknown,
    };
    return ForegroundServiceFailure(
      kind,
      '${error.code}: ${error.message ?? '(无消息)'}',
      cause: error,
    );
  }
}

/// 把状态机与桥接起来的高层门面。
///
/// 调用方只喂「当前共享数与连接数」，门面负责：判状态 → 只在**变化时**推送 →
/// 把失败原样上抛（不吞）。
final class ForegroundServiceController {
  ForegroundServiceController({
    required this.bridge,
    ForegroundServiceMachine? machine,
  }) : _machine = machine ?? ForegroundServiceMachine();

  /// 平台通道桥。
  final ForegroundServiceBridge bridge;

  final ForegroundServiceMachine _machine;

  ForegroundServiceState get state => _machine.state;

  /// 最近一次推送是否真的发生（状态没变就不打扰平台）。
  bool get lastPushWasNoop => _lastPushed == _machine.state;

  ForegroundServiceState? _lastPushed;

  /// 喂入新的共享计数并同步到平台。
  ///
  /// 返回本次的判定；若状态未变化则**不重复调用通道**（减少 IPC 与通知重绘）。
  Future<ForegroundDecision> sync({
    required int shareCount,
    int? connectedPeers,
  }) async {
    final ForegroundDecision decision = _machine.update(
      shareCount: shareCount,
      connectedPeers: connectedPeers,
    );
    if (_lastPushed == decision.nextState) {
      return decision;
    }
    await bridge.apply(decision.nextState);
    _lastPushed = decision.nextState;
    return decision;
  }

  /// 冷启动校正：以平台实际状态为准覆盖本地状态机。
  Future<ForegroundServiceState> reconcile() async {
    final bool running;
    try {
      running = await bridge.isRunning();
    } on ForegroundServiceFailure catch (error) {
      if (error.kind == ForegroundFailureKind.notAndroid) {
        // 非安卓平台不进入前台服务语义，保持 stopped 即可。
        return ForegroundServiceState.stopped;
      }
      rethrow;
    }
    if (!running) {
      _lastPushed = ForegroundServiceState.stopped;
      return _machine.clear().nextState;
    }
    final ForegroundServiceState current = _machine.state.copyWith(
      running: true,
    );
    _lastPushed = current;
    return current;
  }

  /// 清空共享，保证服务停下、锁释放。
  Future<ForegroundDecision> clear() async {
    final ForegroundDecision decision = _machine.clear();
    if (_lastPushed != decision.nextState) {
      await bridge.apply(decision.nextState);
      _lastPushed = decision.nextState;
    }
    return decision;
  }
}
