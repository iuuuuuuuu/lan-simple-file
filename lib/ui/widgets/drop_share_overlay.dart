// SPDX-License-Identifier: GPL-3.0-only

/// 拖入建共享：全屏半透明遮罩 + 松开后调 [DropShareHandler]。
///
/// **Android 完全跳过**：用可注入的 [enableDragDrop] 而不是硬判 Platform，
/// 因为 widget test 里 Platform 恒为桌面，硬判会让「Android 分支」永远测不到。
/// 生产侧在组装层按真实平台传入该 bool 即可。
///
/// 遮罩用 accent 描边 + 半透明底色表达「可投放」，
/// 不新增色相（QQ 的拖入态也是用品牌色描边）。
library;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/tokens.dart';
import '../../core/contracts/contracts.dart';
import '../shell/design.dart';

/// 一条失败记录：哪条路径、为什么失败。
///
/// 存在的理由：只报「N 个失败」而不给原因，用户既无法判断是权限、越界
/// 还是文件被移走，也无法针对性重试——那等于没有提示。
final class DropShareFailure {
  /// 构造一条失败记录。
  const DropShareFailure({required this.path, required this.message});

  /// 失败的文件/目录路径。
  final String path;

  /// 可读的失败原因（来自 LanFileException.message 或原始异常）。
  final String message;

  /// 展示用文件名（取路径最后一段）。
  String get shortName {
    final List<String> parts = path.split(RegExp(r'[\\\\/]'));
    final List<String> kept = parts
        .where((String s) => s.isNotEmpty)
        .toList(growable: false);
    return kept.isEmpty ? path : kept.last;
  }
}

/// 拖入结果的处理端口：把被拖入的路径变成一次 create 调用。
///
/// 抽成接口是为了让「拖入 N 个文件调用 N 次 create」这件事可被测试断言，
/// 而不必真的起 ShareService（它需要 store + FileRefFactory + 在线探测）。
abstract interface class DropShareHandler {
  /// 处理一批被拖入的路径；每个路径对应一次共享创建。
  ///
  /// 返回成功创建的条数；失败项应在实现内记录并可被读回。
  Future<int> createFromPaths(List<String> paths);
}

class CallbackDropShareHandler implements DropShareHandler {
  const CallbackDropShareHandler(this.callback);
  final Future<int> Function(List<String>) callback;
  @override
  Future<int> createFromPaths(List<String> paths) => callback(paths);
}

/// 用真实 ShareService 建共享的实现。
final class ServiceDropShareHandler implements DropShareHandler {
  /// [create] 是把单个路径变成分享的回调（由组装层注入），
  /// 这样本文件不必知道 CreateShareRequest 的构造细节。
  const ServiceDropShareHandler({required this.create});

  /// 单个路径 -> 创建一次共享。
  final Future<void> Function(String path) create;

  /// 上一次失败的原因（供 UI 提示；空表示全部成功）。
  ///
  /// 记录**路径 + 真实错误**，不是只记路径。只记路径的话用户看到
  /// 「1 个失败」却不知道是权限、越界还是文件已不存在，等于没有提示。
  static final List<DropShareFailure> lastFailures = <DropShareFailure>[];

  @override
  Future<int> createFromPaths(List<String> paths) async {
    lastFailures.clear();
    int ok = 0;
    for (final String path in paths) {
      try {
        await create(path);
        ok++;
      } on Object catch (error) {
        // 单个文件失败不能中断整批：用户拖了 10 个，不能因为 1 个失败全丢。
        lastFailures.add(
          DropShareFailure(path: path, message: _describe(error)),
        );
      }
    }
    return ok;
  }

  /// 把异常翻成用户能懂的一句话；不吞掉原始信息。
  static String _describe(Object error) {
    if (error is LanFileException) {
      return error.message;
    }
    return error.toString();
  }
}

/// 拖入共享遮罩。
///
/// 用法：把页面 body 包进本组件；[enableDragDrop] 为 false 时完全退化为透传
/// （不注册监听、不显示遮罩），因此 Android 上等同于不存在。
class DropShareOverlay extends StatefulWidget {
  /// [handler] 为 null 时即使 enable 为 true 也不会建共享（会提示未连接）。
  const DropShareOverlay({
    super.key,
    required this.enableDragDrop,
    this.handler,
    required this.child,
    this.onResult,
    this.label = '松开即可共享',
    this.description = '共享只记录文件位置，不复制文件本体',
  });

  /// 是否启用拖入（桌面 true，Android false）。
  final bool enableDragDrop;

  /// 拖入结果处理；为 null 表示服务未连接。
  final DropShareHandler? handler;

  /// 被包裹的内容。
  final Widget child;

  /// 一次拖入处理完成后的回调（成功数 / 总数），供上层提示。
  final void Function(int created, int total)? onResult;
  final String label;
  final String description;

  @override
  State<DropShareOverlay> createState() => _DropShareOverlayState();
}

class _DropShareOverlayState extends State<DropShareOverlay> {
  /// 当前是否处于拖入悬停态。
  bool _dragging = false;

  /// 正在处理的文件数（悬停时未知，显示拖动中的项数只能等 done；
  /// 因此悬停阶段显示通用文案，done 后显示实际数量）。
  int _hoverCount = 0;

  @override
  Widget build(BuildContext context) {
    if (!widget.enableDragDrop) {
      // Android / 未启用：完全不加监听层，行为与没有本组件一致。
      return widget.child;
    }

    final LanFileTokens tokens = Theme.of(context).extension<LanFileTokens>()!;

    return DropTarget(
      onDragEntered: (DropEventDetails details) {
        setState(() {
          _dragging = true;
          _hoverCount = 0;
        });
      },
      onDragExited: (DropEventDetails details) {
        setState(() {
          _dragging = false;
          _hoverCount = 0;
        });
      },
      onDragDone: (DropDoneDetails details) async {
        final List<String> paths = <String>[
          for (final DropItem item in details.files) item.path,
        ];
        setState(() {
          _dragging = false;
          _hoverCount = paths.length;
        });
        final DropShareHandler? handler = widget.handler;
        if (handler == null) {
          widget.onResult?.call(0, paths.length);
          return;
        }
        final int created = await handler.createFromPaths(paths);
        widget.onResult?.call(created, paths.length);
      },
      child: Stack(
        children: <Widget>[
          widget.child,
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  // 半透明主色底：明暗两套都能看出「可投放」。
                  color: tokens.accent.withValues(alpha: 0.18),
                  child: Center(
                    child: Container(
                      key: const ValueKey<String>('drop-share-mask'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 20,
                      ),
                      decoration: overlayDecoration(tokens),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            LucideIcons.folderUp,
                            size: 36,
                            color: tokens.accent,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _hoverCount > 0
                                ? '${widget.label} · $_hoverCount 项'
                                : widget.label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: tokens.fg,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.description,
                            style: TextStyle(fontSize: 12, color: tokens.fgDim),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
