// SPDX-License-Identifier: GPL-3.0-only

/// identicon 的跨端一致性测试：稳定性、唯一性、镜像对称、主题差异。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/widgets/identicon.dart';
import 'package:lan_simple_file/core/contracts/types.dart';

/// 生成 [count] 个互不相同的、形如真实 peerId 的样本。
///
/// 序号按 base36 从低位写入 13 位，因此 `p_` + 13 位互不重复，
/// 且格式满足契约里的 ^p_[a-z0-9]{13}$。
List<String> _peerIdSamples(int count) {
  return <String>[for (int i = 0; i < count; i++) _peerIdOf(i)];
}

String _peerIdOf(int index) {
  const String digits = '0123456789abcdefghijklmnopqrstuvwxyz';
  int value = index;
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < 13; i++) {
    out.write(digits[value % 36]);
    value = value ~/ 36;
  }
  return 'p_${out.toString()}';
}

String _gridKey(String peerId) => identiconGrid(peerId)
    .map((List<bool> row) => row.map((bool b) => b ? '1' : '0').join())
    .join('/');

String _cellFills(String peerId) => parseIdenticonSvg(
      buildIdenticonSvg(peerId, dark: false),
    ).map((IdenticonRect c) => c.fill).toSet().join(',');

void main() {
  group('buildIdenticonSvg 稳定性', () {
    test('同一 peerId 两次调用逐字节相同', () {
      const String peerId = 'p_7fk3m9x2a1cdk';
      final String first = buildIdenticonSvg(peerId, dark: false);
      final String second = buildIdenticonSvg(peerId, dark: false);
      expect(second, equals(first));
      expect(first, startsWith('<svg xmlns="http://www.w3.org/2000/svg"'));
      expect(first, endsWith('</svg>'));
    });

    test('同一 peerId 的暗色输出也稳定，且与明色输出不同', () {
      const String peerId = 'p_7fk3m9x2a1cdk';
      final String darkFirst = buildIdenticonSvg(peerId, dark: true);
      final String darkSecond = buildIdenticonSvg(peerId, dark: true);
      expect(darkSecond, equals(darkFirst));
      expect(darkFirst, isNot(equals(buildIdenticonSvg(peerId, dark: false))));
    });

    test('800 次重复调用结果集只有一个元素（无隐藏状态）', () {
      const String peerId = 'p_abc123xyz789k';
      final Set<String> outputs = <String>{
        for (int i = 0; i < 800; i++) buildIdenticonSvg(peerId, dark: false),
      };
      expect(outputs, hasLength(1));
    });

    test('size 只改 width/height，不改几何与颜色', () {
      const String peerId = 'p_q1w2e3r4t5y6k';
      final String small = buildIdenticonSvg(peerId, dark: false, size: 40);
      final String large = buildIdenticonSvg(peerId, dark: false, size: 400);
      expect(small, contains('width="40" height="40"'));
      expect(large, contains('width="400" height="400"'));
      // 去掉 width/height 后两者必须完全一致。
      final String stripped = small
          .replaceFirst('width="40" height="40"', '')
          .toString();
      final String strippedLarge = large
          .replaceFirst('width="400" height="400"', '')
          .toString();
      expect(strippedLarge, equals(stripped));
      expect(parseIdenticonSvg(large).length, parseIdenticonSvg(small).length);
    });

    test('非法 size 抛 ArgumentError', () {
      expect(
        () => buildIdenticonSvg('p_7fk3m9x2a1cdk', dark: false, size: 0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => buildIdenticonSvg('p_7fk3m9x2a1cdk', dark: false, size: -1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('SVG 中的 peerId 被 XML 转义，注入不成立', () {
      final String svg = buildIdenticonSvg('p_<&">x', dark: false);
      expect(svg, contains('aria-label="p_&lt;&amp;&quot;&gt;x"'));
      expect(svg, isNot(contains('aria-label="p_<&">x"')));
    });
  });

  group('不同 peerId 的唯一性', () {
    test('100 个样本的 SVG 全部互不相等', () {
      final List<String> samples = _peerIdSamples(100);
      final Map<String, String> svgByPeer = <String, String>{
        for (final String peerId in samples)
          peerId: buildIdenticonSvg(peerId, dark: false),
      };
      expect(svgByPeer, hasLength(100));
      expect(
        svgByPeer.values.toSet(),
        hasLength(100),
        reason: '100 个不同 peerId 必须产出 100 个不同的 SVG',
      );
    });

    test('100 个样本的可见结果（网格 + 色块色）全部互不相等', () {
      // 计划 §7.2 把填充位固定为 15 位（32768 种网格），
      // 因此样本量增大后网格本身一定出现生日碰撞——这是规格的已知上限，
      // 由色相（0..359）提供额外的区分度来保证「看起来不一样」。
      // 实测：n=100 时不同网格 99 个，但网格+颜色的可见结果 100 个全不同。
      final Set<String> visual = <String>{
        for (final String peerId in _peerIdSamples(100))
          '${_gridKey(peerId)}|${_cellFills(peerId)}',
      };
      expect(visual, hasLength(100));
    });

    test('网格碰撞率与 15 位规格相符（不夸大区分度）', () {
      // 15 位 → 32768 种网格；100 个样本的期望碰撞数 ≈ 100²/(2·32768) ≈ 0.15。
      // 实测 1 次碰撞属正常波动，这里给下界而不是硬编码「全部不同」，
      // 避免把统计现象写成必然通过的假用例。
      final Set<String> grids = <String>{
        for (final String peerId in _peerIdSamples(100)) _gridKey(peerId),
      };
      expect(grids.length, greaterThanOrEqualTo(95));
      expect(grids.length, lessThanOrEqualTo(100));
    });

    test('色相落在 0..359，饱和度落在 45..65', () {
      for (final String peerId in _peerIdSamples(200)) {
        final int hue = identiconHue(peerId);
        final int saturation = identiconSaturation(peerId);
        expect(hue, inInclusiveRange(0, 359), reason: peerId);
        expect(saturation, inInclusiveRange(45, 65), reason: peerId);
      }
    });
  });

  group('镜像对称性', () {
    test('50 个样本：第 1 列与第 5 列、第 2 列与第 4 列填充状态一致', () {
      for (final String peerId in _peerIdSamples(50)) {
        final List<List<bool>> grid = identiconGrid(peerId);
        expect(grid, hasLength(5));
        for (int row = 0; row < 5; row++) {
          expect(grid[row], hasLength(5));
          expect(
            grid[row][0],
            equals(grid[row][4]),
            reason: '$peerId 第 $row 行第 1/5 列不对称',
          );
          expect(
            grid[row][1],
            equals(grid[row][3]),
            reason: '$peerId 第 $row 行第 2/4 列不对称',
          );
        }
      }
    });

    test('50 个样本：SVG 里解码出的色块坐标也满足镜像', () {
      for (final String peerId in _peerIdSamples(50)) {
        final String svg = buildIdenticonSvg(peerId, dark: false);
        final Map<String, Set<int>> colsByRow = <String, Set<int>>{};
        for (final IdenticonRect cell in parseIdenticonSvg(svg)) {
          expect(cell.column, inInclusiveRange(0, 4));
          expect(cell.row, inInclusiveRange(0, 4));
          colsByRow.putIfAbsent('${cell.row}', () => <int>{})
              .add(cell.column);
        }
        for (final MapEntry<String, Set<int>> entry in colsByRow.entries) {
          final Set<int> cols = entry.value;
          expect(
            cols.contains(2),
            equals(cols.contains(2)),
            reason: '$peerId 第 ${entry.key} 行中心列判断异常',
          );
          for (final int col in <int>[0, 1]) {
            expect(
              cols.contains(col),
              equals(cols.contains(4 - col)),
              reason: '$peerId 第 ${entry.key} 行第 $col 列与镜像列不一致',
            );
          }
        }
      }
    });

    test('镜像矩阵与 15 位自由位一一对应', () {
      for (final String peerId in _peerIdSamples(50)) {
        final List<bool> bits = identiconBits(peerId);
        final List<List<bool>> grid = identiconGrid(peerId);
        expect(bits, hasLength(identiconFreeBits));
        for (int row = 0; row < 5; row++) {
          for (int col = 0; col < 5; col++) {
            final int mirrored = col <= 2 ? col : 4 - col;
            expect(
              grid[row][col],
              equals(bits[row * 3 + mirrored]),
              reason: '$peerId ($row,$col) 与自由位不一致',
            );
          }
        }
      }
    });
  });

  group('夹具合规', () {
    test('测试里用到的每个 peerId 都能通过 PeerId.parse', () {
      // types.dart 的 PeerId 正则是 ^p_[a-z0-9]{13}$；
      // 夹具一旦写成 12 位就会成为跨模块坏样本，这里直接用它把关。
      final List<String> fixtures = <String>[
        'p_7fk3m9x2a1cdk',
        'p_0000000000000',
        'p_abc123xyz789k',
        'p_q1w2e3r4t5y6k',
        'p_9z8y7x6w5v4uk',
        'p_localdevice00',
        'p_aaa111bbb222z',
        ..._peerIdSamples(100),
      ];
      for (final String peerId in fixtures) {
        expect(
          () => PeerId.parse(peerId),
          returnsNormally,
          reason: '夹具 $peerId 不是合法 PeerId（必须是 p_ + 13 位小写字母数字）',
        );
      }
    });
  });

  group('SVG 结构', () {
    test('画布底色按明暗区分，且色块全部为 6 位小写十六进制', () {
      const String peerId = 'p_9z8y7x6w5v4uk';
      final String light = buildIdenticonSvg(peerId, dark: false);
      final String dark = buildIdenticonSvg(peerId, dark: true);
      expect(parseIdenticonCanvasFill(light), equals(identiconCanvasLight));
      expect(parseIdenticonCanvasFill(dark), equals(identiconCanvasDark));
      for (final IdenticonRect cell in parseIdenticonSvg(dark)) {
        expect(cell.fill, matches(RegExp(r'^#[0-9a-f]{6}$')));
      }
    });

    test('至少有一个色块（5x5 网格不会是空图）', () {
      // 15 位全 0 的概率是 2^-15；此处逐一样本检查，避免运气成分。
      for (final String peerId in _peerIdSamples(300)) {
        final List<IdenticonRect> cells = parseIdenticonSvg(
          buildIdenticonSvg(peerId, dark: false),
        );
        expect(cells, isNotEmpty, reason: peerId);
        expect(cells.length, lessThanOrEqualTo(25));
      }
    });

    test('固定样本的 SVG 与快照一致（防止跨端漂移）', () {
      // 这条用例锁死算法：改动取位、配色或格式都会让它失败。
      const String peerId = 'p_0000000000000';
      final String svg = buildIdenticonSvg(peerId, dark: false, size: 100);
      expect(svg, equals(_goldenSvg));
    });
  });
}

/// p_0000000000000 的明色 100px 输出，由本次实现实跑 dump 得到。
///
/// 这条常量是跨端一致性的锚点：任何平台上重跑都必须逐字节相同。
const String _goldenSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"'
    ' viewBox="0 0 100 100" role="img" aria-label="p_0000000000000">'
    '<rect x="0" y="0" width="100" height="100" fill="#ffffff"/>'
    '<rect x="41" y="5" width="18" height="18" rx="3" fill="#54cc33"/>'
    '<rect x="5" y="23" width="18" height="18" rx="3" fill="#54cc33"/>'
    '<rect x="23" y="23" width="18" height="18" rx="3" fill="#54cc33"/>'
    '<rect x="59" y="23" width="18" height="18" rx="3" fill="#54cc33"/>'
    '<rect x="77" y="23" width="18" height="18" rx="3" fill="#54cc33"/>'
    '<rect x="5" y="41" width="18" height="18" rx="3" fill="#54cc33"/>'
    '<rect x="41" y="41" width="18" height="18" rx="3" fill="#54cc33"/>'
    '<rect x="77" y="41" width="18" height="18" rx="3" fill="#54cc33"/>'
    '<rect x="41" y="59" width="18" height="18" rx="3" fill="#54cc33"/>'
    '<rect x="23" y="77" width="18" height="18" rx="3" fill="#54cc33"/>'
    '<rect x="41" y="77" width="18" height="18" rx="3" fill="#54cc33"/>'
    '<rect x="59" y="77" width="18" height="18" rx="3" fill="#54cc33"/>'
    '</svg>';
