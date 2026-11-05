// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter_test/flutter_test.dart';
import 'package:identicon_dart/identicon_dart.dart' as generator;
import 'package:image/image.dart' as image;
import 'package:lan_simple_file/app/widgets/identicon.dart';

void main() {
  test('PNG generation is deterministic, cached and seed-specific', () async {
    final first = buildIdenticonPng('p_nyhnu4iiynhqs');
    expect(identical(first, buildIdenticonPng('p_nyhnu4iiynhqs')), isTrue);
    expect(
      await first,
      orderedEquals(await buildIdenticonPng('p_nyhnu4iiynhqs')),
    );
    expect(
      await first,
      isNot(orderedEquals(await buildIdenticonPng('desktop'))),
    );
  });

  test('package-backed 5x5 pattern is symmetric with white padding', () async {
    for (final seed in ['p_nyhnu4iiynhqs', 'desktop', 'android', 'macos']) {
      final png = image.decodePng(await buildIdenticonPng(seed))!;
      final raw = generator.Identicon(value: seed).raw();
      expect(png.width, 420);
      expect(png.height, 420);
      expect(png.getPixel(0, 0).r, 255);
      expect(png.getPixel(419, 419).g, 255);
      var filled = 0;
      for (var y = 0; y < 5; y++) {
        for (var x = 0; x < 5; x++) {
          final pixel = png.getPixel(90 + x * 60, 90 + y * 60);
          final isWhite = pixel.r == 255 && pixel.g == 255 && pixel.b == 255;
          expect(!isWhite, raw[y][x]);
          expect(raw[y][x], raw[y][4 - x]);
          if (!isWhite) filled++;
        }
      }
      expect(filled, inInclusiveRange(1, 24));
    }
  });

  test(
    'requested PNG size is exact, including non-multiples of seven',
    () async {
      for (final size in [7, 41, 96, 420]) {
        final png = image.decodePng(
          await buildIdenticonPng('size', size: size),
        )!;
        expect(png.width, size);
        expect(png.height, size);
      }
      expect(() => buildIdenticonPng('size', size: 6), throwsArgumentError);
    },
  );
}
