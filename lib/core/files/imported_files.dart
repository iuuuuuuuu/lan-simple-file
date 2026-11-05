// SPDX-License-Identifier: GPL-3.0-only
import 'dart:io';

import 'package:path/path.dart' as p;

Future<File> persistImportedFile({
  required Directory directory,
  required String name,
  required Stream<List<int>> content,
}) async {
  await directory.create(recursive: true);
  final safe = p
      .basename(name.replaceAll(r'\', '/'))
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
  final label = safe.isEmpty || safe == '.' || safe == '..' ? '文件' : safe;
  final folder = await directory.createTemp('file_');
  final output = File(p.join(folder.path, label));
  final partial = File(p.join(folder.path, '.uploading'));
  try {
    final sink = partial.openWrite();
    try {
      await sink.addStream(content);
    } on Object {
      try {
        await sink.close();
      } on Object {
        /* Preserve the original error. */
      }
      rethrow;
    }
    await sink.close();
    await partial.rename(output.path);
    return output;
  } on Object {
    await folder.delete(recursive: true);
    rethrow;
  }
}
