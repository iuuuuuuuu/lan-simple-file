// SPDX-License-Identifier: GPL-3.0-only

library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';

/// 选择图片，居中裁剪为 256px 方形头像。
Future<Uint8List?> pickAvatar() async {
  final PlatformFile? selected = await FilePicker.pickFile(
    type: FileType.image,
    dialogTitle: '选择头像图片',
  );
  if (selected == null) return null;
  if ((await selected.length() ?? 0) > 20 * 1024 * 1024) {
    throw const FormatException('图片不能超过 20 MB');
  }
  return normalizeAvatarImage(await selected.readAsBytes());
}

Future<Uint8List> normalizeAvatarImage(Uint8List bytes) async {
  if (bytes.length > 20 * 1024 * 1024) {
    throw const FormatException('图片不能超过 20 MB');
  }
  final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
    bytes,
  );
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  ui.Picture? picture;
  ui.Image? output;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final double scale = math.min(
      1,
      512 / math.max(descriptor.width, descriptor.height),
    );
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (descriptor.width * scale).round()),
      targetHeight: math.max(1, (descriptor.height * scale).round()),
    );
    image = (await codec.getNextFrame()).image;
    final double side = math.min(image.width, image.height).toDouble();
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(
        (image.width - side) / 2,
        (image.height - side) / 2,
        side,
        side,
      ),
      const ui.Rect.fromLTWH(0, 0, 256, 256),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    picture = recorder.endRecording();
    output = await picture.toImage(256, 256);
    final ByteData? data = await output.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (data == null) throw const FormatException('无法读取图片');
    return data.buffer.asUint8List();
  } finally {
    output?.dispose();
    picture?.dispose();
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}
