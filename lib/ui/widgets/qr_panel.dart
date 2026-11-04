// SPDX-License-Identifier: GPL-3.0-only

/// 分享链接二维码面板。
///
/// 约束（docs/plan.md §7.1 双色主题）：
/// - 只有一套中性灰阶 + 一个主色，不引入第二个色相；
/// - 二维码必须保证可扫：前景用 [LanFileTokens.fg]、底色用
///   [LanFileTokens.surface]，对比度在明暗两套 token 下都足够；
/// - 桌面显示大图（默认 240），窄屏按可用宽度收紧，最小不低于 160；
/// - 链接文本一并展示并可选中，扫码失败时还能手动复制。
///
/// 本文件不依赖 qr_flutter 之外的任何第三方包，widget test 可直接 pump。
library;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/theme/tokens.dart';

/// 二维码面板的尺寸策略。
enum QrPanelLayout {
  /// 桌面：固定大方块。
  large,

  /// 窄屏：跟随可用宽度自适应。
  compact,
}

/// 分享链接二维码面板。
final class QrPanel extends StatelessWidget {
  const QrPanel({
    super.key,
    required this.linkText,
    this.caption,
    this.layout = QrPanelLayout.large,
    this.largeSize = 240,
    this.minSize = 160,
    this.maxSize = 320,
  });

  /// 要编码进二维码的链接文本（通常是 `lsf://open?share=..&k=..`）。
  final String linkText;

  /// 可选说明文字（例如分享名）。
  final String? caption;

  /// 尺寸策略。
  final QrPanelLayout layout;

  /// [QrPanelLayout.large] 下的边长。
  final double largeSize;

  /// 自适应时的最小边长。
  final double minSize;

  /// 自适应时的最大边长。
  final double maxSize;

  /// 从当前 Theme 取 token；没装扩展时回落到明色。
  static LanFileTokens tokensOf(BuildContext context) {
    return Theme.of(context).extension<LanFileTokens>() ?? LanFilePalette.light;
  }

  @override
  Widget build(BuildContext context) {
    final LanFileTokens t = tokensOf(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double side = _sideFor(constraints);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            if (caption != null && caption!.isNotEmpty) ...<Widget>[
              Text(
                caption!,
                style: TextStyle(
                  color: t.fg,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
            ],
            DecoratedBox(
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.line),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: QrImageView(
                  data: linkText,
                  size: side,
                  // 二维码本体只用 fg / surface：双色约束下对比度最高的一对。
                  backgroundColor: t.surface,
                  eyeStyle: QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: t.fg,
                  ),
                  dataModuleStyle: QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: t.fg,
                  ),
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                  semanticsLabel: '分享链接二维码',
                ),
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              linkText,
              key: const ValueKey<String>('qr-panel-link-text'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.fgDim,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        );
      },
    );
  }

  double _sideFor(BoxConstraints constraints) {
    if (layout == QrPanelLayout.large) {
      // 容器已经比大图还窄时也要收缩，避免溢出。
      final double available = constraints.maxWidth.isFinite
          ? constraints.maxWidth - 16
          : largeSize;
      return _clamp(available < largeSize ? available : largeSize);
    }
    final double available = constraints.maxWidth.isFinite
        ? constraints.maxWidth - 16
        : maxSize;
    return _clamp(available.clamp(minSize, maxSize));
  }

  double _clamp(double value) {
    if (value < minSize) return minSize;
    if (value > maxSize) return maxSize;
    return value;
  }
}