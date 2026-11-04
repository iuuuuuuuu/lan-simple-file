// SPDX-License-Identifier: GPL-3.0-only

/// identicon 渲染回归：明暗两套都必须真实光栅化出预期的像素，而不只是生成字符串。
///
/// 字符串层由 identicon_test.dart 的纯函数用例覆盖；这里补「画得出来」这一层：
/// 真跑 CustomPainter 到 canvas，再按格中心逐点核对画布底色与填充。
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/widgets/identicon.dart';

/// 头像的渲染尺寸（逻辑像素）。
const double _avatarSize = 100;

/// 渲染 [peerId] 的头像并取回真实位图；只截头像自身，不含整屏。
Future<ui.Image> _renderIdenticon(
  WidgetTester tester,
  String peerId, {
  required Brightness brightness,
}) async {
  final UniqueKey boundaryKey = UniqueKey();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: RepaintBoundary(
            key: boundaryKey,
            child: Identicon(peerId: peerId, size: _avatarSize, radius: 0),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final RenderRepaintBoundary boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
  return boundary.toImage(pixelRatio: 1.0);
}

/// 取回整张位图的 RGBA 字节。
Future<Uint8List> _pixelsOf(WidgetTester tester, ui.Image image) async {
  final ByteData? data = await tester.runAsync<ByteData?>(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  return data!.buffer.asUint8List();
}

/// 按 SVG 视图坐标（0..100）采样一个像素的颜色通道。
({int r, int g, int b}) _sampleAt(
  Uint8List rgba,
  int width,
  double viewX,
  double viewY,
) {
  final int x = (viewX / 100 * _avatarSize).floor().clamp(0, _avatarSize.toInt() - 1);
  final int y = (viewY / 100 * _avatarSize).floor().clamp(0, _avatarSize.toInt() - 1);
  final int i = (y * width + x) * 4;
  return (r: rgba[i], g: rgba[i + 1], b: rgba[i + 2]);
}

/// 视图坐标下第 [row] 行第 [col] 列的格中心。
({double x, double y}) _cellCenter(int row, int col) =>
    (x: 5 + col * 18 + 9, y: 5 + row * 18 + 9);

bool _isNear(({int r, int g, int b}) c, ({int r, int g, int b}) ref,
    {int tolerance = 24}) {
  return (c.r - ref.r).abs() <= tolerance &&
      (c.g - ref.g).abs() <= tolerance &&
      (c.b - ref.b).abs() <= tolerance;
}

void main() {
  // 固定夹具：同时用于字符串用例，格式满足 ^p_[a-z0-9]{13}$。
  const String peerId = 'p_7fk3m9x2a1cdk';

  final Map<Brightness, ({int r, int g, int b})> canvasByBrightness =
      <Brightness, ({int r, int g, int b})>{
    Brightness.light: (r: 0xFF, g: 0xFF, b: 0xFF),
    Brightness.dark: (r: 0x16, g: 0x1A, b: 0x21),
  };

  for (final Brightness brightness in Brightness.values) {
    testWidgets('真实渲染出对应画布底色（${brightness.name}）',
        (WidgetTester tester) async {
      final ui.Image image = await _renderIdenticon(
        tester,
        peerId,
        brightness: brightness,
      );
      addTearDown(image.dispose);

      expect(image.width, _avatarSize.toInt());
      expect(image.height, _avatarSize.toInt());

      final Uint8List rgba = await _pixelsOf(tester, image);
      expect(rgba.length, _avatarSize.toInt() * _avatarSize.toInt() * 4);

      // 视图左上角留白 5，一定是画布底色。
      final ({int r, int g, int b}) corner =
          _sampleAt(rgba, image.width, 1, 1);
      expect(
        _isNear(corner, canvasByBrightness[brightness]!),
        isTrue,
        reason: '角落应为画布底色，实际 $corner',
      );
    });
  }

  testWidgets('真实渲染出的填充格与 buildIdenticonSvg 完全一致',
      (WidgetTester tester) async {
    // 这是「Widget 只是把字符串画出来」的硬证据：
    // 纯函数说哪格填色，画面上那格就必须不是画布底色。
    for (final Brightness brightness in Brightness.values) {
      final ui.Image image = await _renderIdenticon(
        tester,
        peerId,
        brightness: brightness,
      );
      addTearDown(image.dispose);
      final Uint8List rgba = await _pixelsOf(tester, image);

      final String svg =
          buildIdenticonSvg(peerId, dark: brightness == Brightness.dark);
      final Set<String> filledFromSvg = <String>{
        for (final IdenticonRect c in parseIdenticonSvg(svg))
          '${c.row},${c.column}',
      };

      final ({int r, int g, int b}) canvas =
          canvasByBrightness[brightness]!;
      final List<String> mismatched = <String>[];
      for (int row = 0; row < 5; row++) {
        for (int col = 0; col < 5; col++) {
          final ({double x, double y}) center = _cellCenter(row, col);
          final ({int r, int g, int b}) px =
              _sampleAt(rgba, image.width, center.x, center.y);
          final bool painted = !_isNear(px, canvas);
          final bool expected = filledFromSvg.contains('$row,$col');
          if (painted != expected) {
            mismatched.add('($row,$col) 期望 $expected 实际 $painted $px');
          }
        }
      }
      expect(mismatched, isEmpty,
          reason: '${brightness.name} 渲染与 SVG 不一致：$mismatched');
    }
  });

  testWidgets('同一 peerId 明暗两套的填充格完全相同（网格不随主题漂移）',
      (WidgetTester tester) async {
    final Map<Brightness, Set<String>> filled = <Brightness, Set<String>>{};
    for (final Brightness brightness in Brightness.values) {
      final ui.Image image = await _renderIdenticon(
        tester,
        peerId,
        brightness: brightness,
      );
      addTearDown(image.dispose);
      final Uint8List rgba = await _pixelsOf(tester, image);
      final ({int r, int g, int b}) canvas =
          canvasByBrightness[brightness]!;
      filled[brightness] = <String>{
        for (int row = 0; row < 5; row++)
          for (int col = 0; col < 5; col++)
            if (!_isNear(
              _sampleAt(rgba, image.width, _cellCenter(row, col).x,
                  _cellCenter(row, col).y),
              canvas,
            ))
              '$row,$col',
      };
    }
    expect(filled[Brightness.dark], equals(filled[Brightness.light]));
    expect(filled[Brightness.light], isNotEmpty, reason: '不该是空图');
  });

  test('渲染同源：明暗两套 SVG 的色块坐标完全一致', () {
    final String lightSvg = buildIdenticonSvg(peerId, dark: false);
    final String darkSvg = buildIdenticonSvg(peerId, dark: true);
    expect(lightSvg, isNot(equals(darkSvg)), reason: '底色与明度应当不同');
    List<String> coords(String svg) => <String>[
          for (final IdenticonRect c in parseIdenticonSvg(svg))
            '${c.row},${c.column}',
        ];
    expect(coords(darkSvg), equals(coords(lightSvg)));
  });
}
