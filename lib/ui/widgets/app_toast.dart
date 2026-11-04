// SPDX-License-Identifier: GPL-3.0-only

/// 浮层 Toast：失败/成功提示从顶部条改成浮在内容之上的临时提示。
///
/// 用户原话：「报错还是等等提示，弹一个 message 或者 toast 就行了，
/// 不要上面显示个内个啥」——顶部固定条已被否掉，本类是其替代。
///
/// 设计约束（守住单主色）：
/// - 成功与失败**只靠图标与字重区分**，不引入红/绿；两者底色、描边、
///   文字色完全一致，只有左侧图标（对勾 vs 感叹号）与标题字重不同。
/// - 浮层用 OverlayEntry，**不改变布局**：内容区不会被顶走或压缩。
///
/// 连续多条策略：**替换上一条**（新的立刻顶掉旧的）。
/// 理由：本产品的提示都是「刚做了一件事的结果」，旧的已经过期；
/// 排队会让用户看到过时结果（例如先报失败、再报成功，两个都显示会误导）。
/// 替换同时天然限流，不会堆出一列遮罩。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';

/// 成功提示的停留时长。
const Duration kToastSuccessDuration = Duration(milliseconds: 2500);

/// 失败提示的停留时长（比成功长，留给用户读完原因）。
const Duration kToastErrorDuration = Duration(seconds: 5);

/// Toast 距屏幕底部的距离。
const double kToastBottomInset = 48;

/// 浮层 Toast 的静态入口。
abstract final class AppToast {
  /// 当前显示的 OverlayEntry；新提示会替换它（策略见库注释）。
  static OverlayEntry? _current;

  /// 当前条目自己的到期回调由 AppToastEntry 内部的 Ticker 驱动，
  /// 不在这里持有 Timer：静态 Timer 会在 widget 被移除后仍挂着，
  /// 在 widget test 里表现为 pending timer，且可能误删后来插入的新提示。

  /// 当前是否正在显示（测试与调试用）。
  static bool get isShowing => _current != null;

  /// 显示一条提示。
  ///
  /// [message] 应带足信息量：失败时写清原因（例如「照片.jpg — 路径不存在」），
  /// 只说「失败」等于没说。
  /// [isError] 决定图标、字重与停留时长。
  static void show(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    // 立刻清掉上一条：替换策略，避免两条叠在一起。
    dismiss();

    final OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      // 没有 Overlay 说明调用点不在 MaterialApp 之下；
      // 静默吞掉会让调用方以为提示已显示，因此这里明确报出来。
      debugPrint('AppToast.show 失败：当前 context 之上没有 Overlay');
      return;
    }

    final AppToastEntry entry = AppToastEntry(
      message: message,
      isError: isError,
      onDismiss: dismiss,
      lifetime: isError ? kToastErrorDuration : kToastSuccessDuration,
    );
    final OverlayEntry overlayEntry = OverlayEntry(
      builder: (BuildContext ctx) => entry,
    );
    _current = overlayEntry;
    overlay.insert(overlayEntry);

    // 到期自动关闭由条目内部的 Ticker 完成（随 widget dispose 一并停止）。
  }

  /// 关闭当前提示（幂等：没有提示时调用安全）。
  static void dismiss() {
    final OverlayEntry? entry = _current;
    _current = null;
    if (entry == null) return;
    if (!entry.mounted) return;
    // remove() 是**异步**的：Overlay 在下一帧才真正卸载该 entry，
    // 在此之前调用 dispose() 会触发 Flutter 断言
    // （OverlayEntry must first be removed from the Overlay before dispose）。
    // 因此先 remove，再安排到卸载之后 dispose。
    entry.remove();
    scheduleMicrotask(entry.dispose);
  }
}

/// 一条 Toast 的实际渲染体。
///
/// 单独成 Widget 便于测试直接 pump（不必走静态入口）。
class AppToastEntry extends StatefulWidget {
  /// [onDismiss] 由关闭按钮触发；[lifetime] 到期后条目自己调用它。
  const AppToastEntry({
    super.key,
    required this.message,
    required this.isError,
    required this.onDismiss,
    this.lifetime,
  });

  /// 提示正文。
  final String message;

  /// 是否为失败提示。
  final bool isError;

  /// 关闭回调。
  final VoidCallback onDismiss;

  /// 自动关闭时长；null 表示不自动关（仅用于测试或常驻场景）。
  final Duration? lifetime;

  @override
  State<AppToastEntry> createState() => _AppToastEntryState();
}

class _AppToastEntryState extends State<AppToastEntry>
    with TickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  );

  /// 生命周期定时器。
  ///
  /// 为什么用 Timer 而不是 AnimationController：
  /// AnimationController 会被 `pumpAndSettle` 一路推进到结束，
  /// 于是**任何一次界面动画收尾都会顺手把提示关掉**——这在真实使用里同样成立
  /// （用户还在读，别处一个动画结束就把它顶没了）。Timer 按真实时间走，
  /// 不受动画帧驱动，行为与用户感知一致。
  ///
  /// 唯一的代价是：widget test 里若不让它到期，会残留 pending timer。
  /// 因此每个用例都必须在结尾 dismiss（本库的 tearDown 已统一处理）。
  Timer? _life;

  @override
  void initState() {
    super.initState();
    _controller.forward();

    final Duration? lifetime = widget.lifetime;
    if (lifetime != null) {
      _life = Timer(lifetime, () {
        // 被替换时本条目已 unmounted，此时不能再动静态入口（否则会关掉新提示）。
        if (mounted) widget.onDismiss();
      });
    }
  }

  @override
  void dispose() {
    _life?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LanFileTokens t = Theme.of(context).extension<LanFileTokens>() ??
        LanFilePalette.of(
          MediaQuery.maybePlatformBrightnessOf(context) == Brightness.dark
              ? Brightness.dark
              : Brightness.light,
        );

    return Positioned(
      left: 0,
      right: 0,
      bottom: kToastBottomInset,
      child: Center(
        child: FadeTransition(
          opacity: CurvedAnimation(
            parent: _controller,
            curve: Curves.easeOut,
          ),
          child: Semantics(
            liveRegion: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Material(
                  key: const ValueKey<String>('app-toast'),
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius:
                          BorderRadius.circular(LanFileMetrics.radiusPanel),
                      border: Border.all(
                        color: t.cardLine,
                        width: LanFileMetrics.hairline,
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: t.shadowColor,
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        // 成功/失败唯一的差异来源是图标形状与字重，
                        // 颜色都取自同一套 token，不新增色相。
                        Icon(
                          widget.isError
                              ? Icons.error_outline
                              : Icons.check_circle_outline,
                          size: 18,
                          color: widget.isError ? t.fgDim : t.accent,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            widget.message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              fontWeight: widget.isError
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: t.fg,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          key: const ValueKey<String>('app-toast-close'),
                          tooltip: '关闭提示',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 26,
                            minHeight: 26,
                          ),
                          icon: Icon(Icons.close, size: 14, color: t.fgDim),
                          onPressed: widget.onDismiss,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}