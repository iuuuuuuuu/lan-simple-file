// SPDX-License-Identifier: GPL-3.0-only
import 'dart:io';

import 'package:android_file_picker/android_file_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/assembly.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/files/saf_bridge.dart';
import 'package:lan_simple_file/core/shares/share_service_impl.dart';
import 'package:lan_simple_file/ui/pages/shares_page.dart';
import 'package:lan_simple_file/ui/shell/qq_shell.dart';
import 'package:lan_simple_file/ui/shell/session_list.dart';
import 'package:lan_simple_file/ui/shell/session_rail.dart';
import 'package:lan_simple_file/ui/widgets/pick_share_files.dart';
import 'package:path/path.dart' as p;

import 'qq_shell_test.dart' show FakeSessionSource, setViewport, wrapShell;

class TestFilePicker extends FilePickerPlatform {
  String? directory;
  AndroidOptions? directoryOptions;
  int directoryCalls = 0;
  final fileTypes = <FileType>[];

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    directoryCalls++;
    directoryOptions = androidOptions;
    return directory;
  }

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    fileTypes.add(type);
    return [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late AppServices services;
  late TestFilePicker picker;
  late FilePickerPlatform originalPicker;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lsf_folder_picker_');
    services = await AppAssembler.assemble(
      dataDir: Directory('${temp.path}/data'),
      httpPortOverride: 0,
      udpPortOverride: 0,
      enableDiscovery: false,
    );
    originalPicker = FilePickerPlatform.instance;
    picker = TestFilePicker();
    FilePickerPlatform.instance = picker;
  });

  tearDown(() async {
    FilePickerPlatform.instance = originalPicker;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(kSafChannelName), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
          null,
        );
    await services.stop();
    await temp.delete(recursive: true);
  });

  test('选择本地目录直接创建文件夹分享，不复制内容', () async {
    final directory = await Directory('${temp.path}/documents').create();
    final file = await File('${directory.path}/a.txt').writeAsString('hello');
    picker.directory = directory.path;

    final shares = await pickShareFolder(services);
    final share = shares.single;
    await (services.shares as ShareServiceImpl).awaitIndex(share.id);
    expect(share.kind, 'folder');
    expect(share.displayName, 'documents');
    expect(share.rootKind, 'localPath');
    expect(share.rootUri, p.normalize(directory.path));
    expect(await file.readAsString(), 'hello');
    expect(
      await Directory('${temp.path}/data/uploaded-files').exists(),
      isFalse,
    );
    expect(
      (await services.shares.browse(share.id)).entries.single.name,
      'a.txt',
    );
  });

  test('取消选择目录不创建分享', () async {
    expect(await pickShareFolder(services), isEmpty);
    expect(await services.shares.listMine(), isEmpty);
    expect(picker.directoryCalls, 1);
  });

  testWidgets('文件夹菜单调用真实安卓适配器的 dir 通道，不打开文件模式', (tester) async {
    final calls = <MethodCall>[];
    FilePickerPlatform.instance = FilePickerAndroid();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('miguelruivo.flutter.plugins.filepicker'),
          (call) async {
            calls.add(call);
            return null;
          },
        );
    await setViewport(tester, const Size(360, 616));
    await tester.pumpWidget(
      wrapShell(
        QqShell(services: services, sessionSource: FakeSessionSource()),
      ),
    );
    await tester.pumpAndSettle();
    final open = tester
        .widget<IconButton>(find.byKey(const ValueKey('mobile-upload')))
        .onPressed!;
    open();
    open();
    await tester.pumpAndSettle();
    expect(find.text('选择文件夹'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('share-upload-folder')));
    await tester.pumpAndSettle();
    expect(calls.map((call) => call.method), ['dir']);
    expect((calls.single.arguments as Map)['androidSafOptions'], {
      'grant': 'lifetime',
      'access': 'readOnly',
      'autoPersist': true,
    });
    expect(find.text('选择文件夹'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('安卓目录采用持久只读 SAF 授权，保留目录名称和目录类型', () async {
    const treeUri =
        'content://com.android.externalstorage.documents/tree/primary%3ADCIM';
    picker.directory = treeUri;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(kSafChannelName), (
          call,
        ) async {
          final args = (call.arguments as Map).cast<String, Object?>();
          expect(args['treeUri'], treeUri);
          return switch (call.method) {
            'statItem' => {
              'documentId': 'primary:DCIM',
              'name': '相册目录',
              'isDirectory': true,
            },
            'exists' || 'canRead' => true,
            'listChildren' => [],
            _ => throw MissingPluginException(call.method),
          };
        });

    final share = (await pickShareFolder(services)).single;
    final scan = await (services.shares as ShareServiceImpl).awaitIndex(
      share.id,
    );
    expect(scan?.failures, 0);
    final options = picker.directoryOptions as FilePickerAndroidOptions;
    expect(options.safOptions.grant, AndroidSAFGrant.lifetime);
    expect(options.safOptions.accessMode, AndroidSAFAccessMode.readOnly);
    expect(options.safOptions.persistGrant, isTrue);
    expect(share.rootKind, 'safTree');
    expect(share.rootUri, treeUri);
    expect(share.displayName, '相册目录');
    expect(share.kind, 'folder');
    expect(share.missing, isFalse);
    expect((await services.shares.listMine()).single.id, share.id);
    expect((await services.shares.browse(share.id)).entries, isEmpty);
  });

  test('安卓目录权限不可读时不落库', () async {
    picker.directory =
        'content://com.android.externalstorage.documents/tree/primary%3ADCIM';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(kSafChannelName), (
          _,
        ) async {
          throw PlatformException(code: 'accessDenied');
        });
    await expectLater(
      pickShareFolder(services),
      throwsA(
        isA<LanFileException>().having(
          (error) => error.code,
          'code',
          LanFileErrorCode.accessDenied,
        ),
      ),
    );
    expect(await services.shares.listMine(), isEmpty);
  });

  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('加号提供文件、文件夹和照片，取消文件夹可再次打开 $size', (tester) async {
      await setViewport(tester, size);
      final source = FakeSessionSource()
        ..rows[ShellSection.nearby] = [
          SessionRowData(
            id: services.identity.peerId.value,
            title: '本机测试会话',
            avatarSeed: services.identity.peerId.value,
          ),
        ];
      await tester.pumpWidget(
        wrapShell(QqShell(services: services, sessionSource: source)),
      );
      await tester.pumpAndSettle();
      if (size.width >= 600) {
        await tester.tap(find.text('本机测试会话'));
        await tester.pumpAndSettle();
      }
      final add = size.width < 600
          ? find.byKey(const ValueKey('mobile-upload'))
          : find.byKey(const ValueKey('chat-upload'));
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.text('选择文件'), findsOneWidget);
      expect(find.text('选择文件夹'), findsOneWidget);
      expect(find.text('选择照片'), findsOneWidget);
      await tester.tap(find.text('选择文件夹'));
      await tester.pumpAndSettle();
      expect(picker.directoryCalls, 1);
      expect(picker.fileTypes, isEmpty);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.text('选择文件夹'), findsOneWidget);
      await tester.tap(find.text('选择照片'));
      await tester.pumpAndSettle();
      expect(picker.fileTypes, [FileType.image]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('我的分享页没有右上角上传按钮，保留刷新', (tester) async {
    await setViewport(tester, const Size(1280, 800));
    await tester.pumpWidget(
      wrapShell(Scaffold(body: SharesPage(services: services))),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('我的分享'), findsOneWidget);
    expect(find.byKey(const ValueKey('shares-upload')), findsNothing);
    expect(find.text('上传文件'), findsNothing);
    expect(find.byTooltip('刷新'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
