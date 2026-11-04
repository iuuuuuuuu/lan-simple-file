// SPDX-License-Identifier: GPL-3.0-only

/// 默认头像 identicon：以 sha256(peerId) 生成跨端完全一致的 SVG（docs/plan.md §7.2）。
///
/// 生成过程是纯函数：任何节点、任何平台上，同样的 (peerId, dark, size)
/// 必须产出逐字节相同的字符串。因此这里只用 utf8 编码、sha256 与整数运算，
/// 不读时钟、不读平台、不读随机源，颜色换算也不经过浮点。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

/// 网格边长：5×5。
const int identiconGridSize = 5;

/// 自由决定位数量：5 行 × 3 列 = 15 位。
const int identiconFreeBits = 15;

/// SVG 视图坐标系边长；缩放交给 width/height，几何坐标恒定。
const double _viewBox = 100;

/// 网格外边距（视图坐标）。
const double _padding = 5;

/// 单元格边长（视图坐标）：5 + 5×18 + 5 = 100，两侧边距对称。
const double _cellSize = 18;

/// 单元格圆角（视图坐标）。
const double _cellRadius = 3;

/// 明色主题下的画布底色（中性，不含色相）。
const String identiconCanvasLight = '#ffffff';

/// 暗色主题下的画布底色（中性，取自暗色 surface token）。
const String identiconCanvasDark = '#161a21';

/// 由 peerId 生成 identicon SVG。
///
/// - [peerId] 不校验：非法输入同样得到稳定结果，便于端到端一致性测试直接调用；
/// - [dark] 影响画布底色与色块明度（暗色下更亮，保证在画布上可辨）；
/// - [size] 只影响 width/height 属性，不改变几何与颜色；
/// - 网格为 5×5，第 1 列与第 5 列镜像（第 2 与第 4 列同理），15 位决定填充。
String buildIdenticonSvg(
  String peerId, {
  required bool dark,
  int size = 400,
}) {
  if (size <= 0) {
    throw ArgumentError.value(size, 'size', 'identicon 边长必须为正数');
  }
  final List<int> hash = _hashOf(peerId);
  final String cellFill = _cellFillOf(hash, dark: dark);
  final StringBuffer out = StringBuffer()
    ..write('<svg xmlns="http://www.w3.org/2000/svg"')
    ..write(' width="')
    ..write(size)
    ..write('" height="')
    ..write(size)
    ..write('" viewBox="0 0 ')
    ..write(_num(_viewBox))
    ..write(' ')
    ..write(_num(_viewBox))
    ..write('" role="img" aria-label="')
    ..write(_escapeXml(peerId))
    ..write('">')
    ..write('<rect x="0" y="0" width="')
    ..write(_num(_viewBox))
    ..write('" height="')
    ..write(_num(_viewBox))
    ..write('" fill="')
    ..write(dark ? identiconCanvasDark : identiconCanvasLight)
    ..write('"/>');

  final List<List<bool>> grid = _gridOf(hash);
  for (int row = 0; row < identiconGridSize; row++) {
    for (int col = 0; col < identiconGridSize; col++) {
      if (!grid[row][col]) {
        continue;
      }
      out
        ..write('<rect x="')
        ..write(_num(_padding + col * _cellSize))
        ..write('" y="')
        ..write(_num(_padding + row * _cellSize))
        ..write('" width="')
        ..write(_num(_cellSize))
        ..write('" height="')
        ..write(_num(_cellSize))
        ..write('" rx="')
        ..write(_num(_cellRadius))
        ..write('" fill="')
        ..write(cellFill)
        ..write('"/>');
    }
  }

  out.write('</svg>');
  return out.toString();
}

/// 与 [buildIdenticonSvg] 同源的填充矩阵，供测试与调试直接取用。
///
/// 返回 5 行 × 5 列的布尔矩阵：true 表示该格填色。
List<List<bool>> identiconGrid(String peerId) => _gridOf(_hashOf(peerId));

/// 由 peerId 派生的 15 位填充位（按行主序，只含前 3 列）。
///
/// 第 4、5 列不在此列表中，因为它们恒等于第 2、1 列。
List<bool> identiconBits(String peerId) {
  final List<int> hash = _hashOf(peerId);
  return <bool>[
    for (int row = 0; row < identiconGridSize; row++)
      for (int col = 0; col < 3; col++) _isFilled(hash, row, col),
  ];
}

/// 由 peerId 派生的色相（0..359）。
int identiconHue(String peerId) {
  final List<int> hash = _hashOf(peerId);
  return ((hash[0] << 8) | hash[1]) % 360;
}

/// 由 peerId 派生的饱和度百分比（45..65）。
int identiconSaturation(String peerId) {
  final List<int> hash = _hashOf(peerId);
  return 45 + (hash[2] % 21);
}

/// 从 [buildIdenticonSvg] 的输出中解出色块，供渲染与测试使用。
///
/// 约定：带 `rx` 的 `rect` 是色块，不带 `rx` 的是画布底色。
List<IdenticonRect> parseIdenticonSvg(String svg) {
  final RegExp cellPattern = RegExp(
    r'<rect x="([0-9.]+)" y="([0-9.]+)" width="([0-9.]+)"'
    r' height="([0-9.]+)" rx="([0-9.]+)" fill="(#[0-9a-f]{6})"/>',
  );
  final List<IdenticonRect> cells = <IdenticonRect>[];
  for (final RegExpMatch m in cellPattern.allMatches(svg)) {
    cells.add(
      IdenticonRect(
        x: double.parse(m.group(1)!),
        y: double.parse(m.group(2)!),
        width: double.parse(m.group(3)!),
        height: double.parse(m.group(4)!),
        radius: double.parse(m.group(5)!),
        fill: m.group(6)!,
      ),
    );
  }
  return cells;
}

/// 从 SVG 中取画布底色。
String parseIdenticonCanvasFill(String svg) {
  final RegExpMatch? match = RegExp(
    r'<rect x="0" y="0"[^>]*fill="(#[0-9a-f]{6})"',
  ).firstMatch(svg);
  return match?.group(1) ?? identiconCanvasLight;
}

/// 解析出的一个色块，坐标为 SVG 视图坐标（0..100）。
final class IdenticonRect {
  const IdenticonRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.radius,
    required this.fill,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final double radius;
  final String fill;

  /// 列号；由 x 反推。
  int get column => ((x - _padding) / _cellSize).round();

  /// 行号；由 y 反推。
  int get row => ((y - _padding) / _cellSize).round();

  @override
  String toString() => 'IdenticonRect(col: $column, row: $row, fill: $fill)';
}

List<int> _hashOf(String peerId) =>
    sha256.convert(utf8.encode(peerId)).bytes;

List<List<bool>> _gridOf(List<int> hash) => <List<bool>>[
      for (int row = 0; row < identiconGridSize; row++)
        <bool>[
          for (int col = 0; col < identiconGridSize; col++)
            _isFilled(hash, row, col),
        ],
    ];

/// 第 col 列在第 row 行是否填色；col ≥ 3 时镜像到 0..2。
bool _isFilled(List<int> hash, int row, int col) {
  final int mirrored = col <= 2 ? col : identiconGridSize - 1 - col;
  final int bitIndex = row * 3 + mirrored;
  assert(bitIndex >= 0 && bitIndex < identiconFreeBits);
  // 15 位取自 hash[4..18] 的最低有效位：稳定、跨平台、无浮点参与。
  return (hash[4 + bitIndex] & 1) == 1;
}

String _cellFillOf(List<int> hash, {required bool dark}) {
  final int hue = ((hash[0] << 8) | hash[1]) % 360;
  final int saturation = 45 + (hash[2] % 21);
  final int lightness = dark ? 60 + (hash[3] % 11) : 42 + (hash[3] % 11);
  return _hslHex(hue, saturation, lightness);
}

/// 视图坐标一律输出整数，绝不经过 `double.toString()`。
///
/// `double.toString()` 的最短往返表示在极端值上可能与平台/内核相关，
/// 跨端一致性要求逐字节相同，所以这条路径必须被断言封死：
/// 所有几何量（viewBox、padding、cellSize、cellRadius）都是整数。
String _num(double value) {
  assert(
    value == value.roundToDouble(),
    'identicon 几何量必须是整数，否则跨端字符串可能不一致：$value',
  );
  return value.toInt().toString();
}

String _escapeXml(String raw) => raw
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// HSL → 6 位小写十六进制颜色。
///
/// 全程整数运算：色相按度数、饱和度与明度按百分比，分子分母都保持整数，
/// 因此同一输入在任何平台上得到同一字节序列。
String _hslHex(int hue, int saturationPercent, int lightnessPercent) {
  final int h = ((hue % 360) + 360) % 360;
  final int s = saturationPercent.clamp(0, 100);
  final int l = lightnessPercent.clamp(0, 100);

  // cFrac = c × 10000（c 为 HSL 的 chroma，取值 [0,1]）。
  final int delta = (2 * l - 100).abs();
  final int cFrac = (100 - delta) * s;
  // xFrac = X × 10000，X = c × (1 - |(h/60 mod 2) - 1|)。
  final int xFrac = cFrac * (60 - ((h % 120) - 60).abs()) ~/ 60;
  // mFrac = m × 10000，m = l - c/2；cFrac 恒为偶数，故除 2 无损。
  final int mFrac = 100 * l - cFrac ~/ 2;

  final int sector = (h ~/ 60) % 6;
  final int rFrac;
  final int gFrac;
  final int bFrac;
  switch (sector) {
    case 0:
      (rFrac, gFrac, bFrac) = (cFrac, xFrac, 0);
    case 1:
      (rFrac, gFrac, bFrac) = (xFrac, cFrac, 0);
    case 2:
      (rFrac, gFrac, bFrac) = (0, cFrac, xFrac);
    case 3:
      (rFrac, gFrac, bFrac) = (0, xFrac, cFrac);
    case 4:
      (rFrac, gFrac, bFrac) = (xFrac, 0, cFrac);
    default:
      (rFrac, gFrac, bFrac) = (cFrac, 0, xFrac);
  }

  final StringBuffer hex = StringBuffer('#');
  for (final int part in <int>[rFrac, gFrac, bFrac]) {
    hex.write(_channelHex(part + mFrac));
  }
  return hex.toString();
}

/// (frac × 10000 + mFrac × 10000) → 0..255，四舍五入且只用整数。
String _channelHex(int scaledFraction) {
  final int numerator = scaledFraction * 255;
  final int rounded = numerator >= 0
      ? (numerator + 5000) ~/ 10000
      : -((-numerator + 5000) ~/ 10000);
  return rounded.clamp(0, 255).toRadixString(16).padLeft(2, '0');
}

/// 把 [buildIdenticonSvg] 的字符串结果画出来；不参与任何生成逻辑。
class IdenticonPainter extends CustomPainter {
  /// 传入 [buildIdenticonSvg] 的返回值。
  const IdenticonPainter(this.svg);

  /// 待渲染的 SVG 字符串。
  final String svg;

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.shortestSide / _viewBox;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = _colorOf(parseIdenticonCanvasFill(svg)),
    );
    for (final IdenticonRect cell in parseIdenticonSvg(svg)) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            cell.x * scale,
            cell.y * scale,
            cell.width * scale,
            cell.height * scale,
          ),
          Radius.circular(cell.radius * scale),
        ),
        Paint()..color = _colorOf(cell.fill),
      );
    }
  }

  @override
  bool shouldRepaint(covariant IdenticonPainter oldDelegate) =>
      oldDelegate.svg != svg;

  static Color _colorOf(String hex) =>
      Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
}

/// 默认头像控件：渲染 [buildIdenticonSvg] 的结果。
class Identicon extends StatelessWidget {
  /// 用 [peerId] 生成并渲染头像。
  const Identicon({
    super.key,
    required this.peerId,
    this.size = 40,
    this.radius,
  });

  /// 设备稳定标识。
  final String peerId;

  /// 边长（逻辑像素）。
  final double size;

  /// 圆角；为空时取边长的 22%。
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final String svg = buildIdenticonSvg(
      peerId,
      dark: Theme.of(context).brightness == Brightness.dark,
    );
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius ?? size * 0.22),
        child: CustomPaint(
          size: Size.square(size),
          painter: IdenticonPainter(svg),
        ),
      ),
    );
  }
}

/// 头像位：有自定义头像字节就显示它，否则永远回落到 identicon。
class PeerAvatar extends StatelessWidget {
  /// 未提供 [avatarBytes] 时按 [peerId] 生成 identicon。
  const PeerAvatar({
    super.key,
    required this.peerId,
    this.avatarBytes,
    this.size = 40,
    this.radius,
  });

  /// 设备稳定标识。
  final String peerId;

  /// 已解码的自定义头像；为 null 表示用户没有设置头像。
  final Uint8List? avatarBytes;

  /// 边长（逻辑像素）。
  final double size;

  /// 圆角；为空时取边长的 22%。
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final Uint8List? bytes = avatarBytes;
    if (bytes == null || bytes.isEmpty) {
      return Identicon(peerId: peerId, size: size, radius: radius);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius ?? size * 0.22),
      child: Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) =>
            Identicon(peerId: peerId, size: size, radius: radius),
      ),
    );
  }
}
