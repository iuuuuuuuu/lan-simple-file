// SPDX-License-Identifier: GPL-3.0-only
import 'dart:io';

import 'package:android_file_picker/android_file_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/assembly.dart';
import '../../core/files/imported_files.dart';
import '../../core/contracts/contracts.dart';
import '../../core/files/saf_bridge.dart';
import '../../core/files/saf_ref_factory.dart';

Future<List<ShareRecord>> pickShareFolder(AppServices services) async {
  debugPrint(
    'share-picker directory request: ${FilePickerPlatform.instance.runtimeType}',
  );
  final selected = await FilePicker.getDirectoryPath(
    dialogTitle: '选择文件夹',
    androidOptions: const FilePickerAndroidOptions(
      safOptions: AndroidSAFOptions(
        grant: AndroidSAFGrant.lifetime,
        accessMode: AndroidSAFAccessMode.readOnly,
        persistGrant: true,
      ),
    ),
  );
  if (selected == null || selected.isEmpty) return [];
  if (Uri.parse(selected).scheme != 'content') {
    return [await services.sharePath(selected)];
  }
  final root = await SafRefFactory(const SafBridge()).openRoot(selected);
  return [
    await services.shares.create(
      CreateShareRequest(
        rootKind: ShareRootKind.safTree,
        rootUri: selected,
        displayName: root.displayName,
        mode: ShareMode.token,
        kind: 'folder',
      ),
    ),
  ];
}

Future<List<ShareRecord>> pickShareFiles(
  AppServices services, {
  bool photos = false,
}) async {
  final selected = await FilePicker.pickFiles(
    type: photos ? FileType.image : FileType.any,
  );
  if (selected.isEmpty) return [];
  final directory = Directory(
    '${(await getApplicationSupportDirectory()).path}/uploaded-files',
  );
  final shares = <ShareRecord>[];
  for (final item in selected) {
    final file = await persistImportedFile(
      directory: directory,
      name: item.name,
      content: item.readAsByteStream(),
    );
    shares.add(await services.sharePath(file.path));
  }
  return shares;
}
