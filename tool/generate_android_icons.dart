// SPDX-License-Identifier: GPL-3.0-only
import 'dart:io';

import 'package:image/image.dart' as image;

void main() {
  final source = image.decodePng(File('assets/logos/c.png').readAsBytesSync())!;
  for (final entry in {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  }.entries) {
    File('android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png')
        .writeAsBytesSync(
          image.encodePng(
            image.copyResize(
              source,
              width: entry.value,
              height: entry.value,
              interpolation: image.Interpolation.cubic,
            ),
          ),
        );
  }
}
