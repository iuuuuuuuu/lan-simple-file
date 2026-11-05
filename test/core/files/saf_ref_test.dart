// SPDX-License-Identifier: GPL-3.0-only

/// saf_ref_test：Dart 侧对 SAF 通道的语义验证。
///
/// 全部用例走 mock MethodChannel（TestDefaultBinaryMessenger 的标准做法），
/// 验证的是：参数编解码、返回值归一化、异常映射、分页游标、范围读取。
/// 真机上 ContentResolver / DocumentFile 的真实行为不在此覆盖范围，
/// 见报告里的「未验证项」清单。
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/errors.dart';
import 'package:lan_simple_file/core/contracts/file_ref.dart';
import 'package:lan_simple_file/core/contracts/types.dart';
import 'package:lan_simple_file/core/files/saf_bridge.dart';
import 'package:lan_simple_file/core/files/saf_ref.dart';
import 'package:lan_simple_file/core/files/saf_ref_factory.dart';

const String kTreeUri =
    'content://com.android.externalstorage.documents/tree/primary%3ADCIM';
const String kRootId = 'primary:DCIM';

/// 记录调用并按脚本应答的假通道。
final class FakeSafChannel {
  FakeSafChannel();

  final List<MethodCall> calls = <MethodCall>[];

  /// method -> 应答脚本。脚本收到参数，返回 Object?，或抛出 PlatformException。
  final Map<String, Object? Function(Map<String, Object?> args)> handlers =
      <String, Object? Function(Map<String, Object?>)>{};

  void on(String method, Object? Function(Map<String, Object?> args) fn) {
    handlers[method] = fn;
  }

  Future<Object?> dispatch(MethodCall call) async {
    calls.add(call);
    final Map<String, Object?> args =
        (call.arguments as Map<Object?, Object?>? ?? <Object?, Object?>{})
            .cast<String, Object?>();
    final Object? Function(Map<String, Object?>)? handler = handlers[call.method];
    if (handler == null) {
      throw MissingPluginException('未注册的假方法: ${call.method}');
    }
    return handler(args);
  }

  List<MethodCall> callsOf(String method) =>
      calls.where((MethodCall c) => c.method == method).toList();
}

/// 把假通道接到 Flutter 的默认二进制信使上。
void installChannel(FakeSafChannel fake) {
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel(kSafChannelName),
    fake.dispatch,
  );
}

Map<String, Object?> item({
  required String documentId,
  String? name,
  bool isDirectory = false,
  int? size,
  int? lastModified,
  String? mime,
}) {
  return <String, Object?>{
    'documentId': documentId,
    'name': name ?? documentId,
    'isDirectory': isDirectory,
    'size': size,
    'lastModified': lastModified,
    'mime': mime,
  };
}

SafRef rootRef(SafBridge bridge, {String documentId = kRootId}) => SafRef(
      bridge: bridge,
      treeUri: kTreeUri,
      documentId: documentId,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSafChannel fake;
  late SafBridge bridge;

  setUp(() {
    fake = FakeSafChannel();
    installChannel(fake);
    bridge = const SafBridge();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(kSafChannelName),
          null,
        );
  });

  group('SafBridge 参数编解码', () {
    test('listChildren 原样透传参数并归一化返回值', () async {
      fake.on('listChildren', (Map<String, Object?> args) {
        return <Object?>[item(documentId: '$kRootId/a.txt', size: 3)];
      });
      final List<Map<String, Object?>> rows =
          await bridge.listChildren(kTreeUri, kRootId, limit: 10);
      final MethodCall call = fake.callsOf('listChildren').single;
      final Map<Object?, Object?> sent =
          call.arguments as Map<Object?, Object?>;
      expect(sent['treeUri'], kTreeUri);
      expect(sent['documentId'], kRootId);
      expect(sent['cursor'], isNull);
      expect(sent['limit'], 10);
      expect(rows.single['documentId'], '$kRootId/a.txt');
      expect(rows.single['isDirectory'], isFalse);
      expect(rows.single['size'], 3);
      expect(rows.single.keys.toSet(), <String>{
        'documentId',
        'name',
        'isDirectory',
        'size',
        'lastModified',
        'mime',
      });
    });

    test('cursor 透传给通道', () async {
      fake.on('listChildren', (Map<String, Object?> args) => <Object?>[]);
      await bridge.listChildren(kTreeUri, kRootId,
          cursor: '$kRootId/b.txt', limit: 5);
      final MethodCall call = fake.callsOf('listChildren').single;
      expect((call.arguments as Map<Object?, Object?>)['cursor'],
          '$kRootId/b.txt');
    });

    test('非法 treeUri / limit 在 Dart 侧被拒，不打到通道', () async {
      await expectLater(
        bridge.listChildren('primary:DCIM', kRootId, limit: 10),
        throwsA(isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.invalidArgument)),
      );
      await expectLater(
        bridge.listChildren(kTreeUri, kRootId, limit: 0),
        throwsA(isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.invalidArgument)),
      );
      expect(fake.calls, isEmpty);
    });

    test('canRead 返回布尔', () async {
      fake.on('canRead', (Map<String, Object?> args) => true);
      expect(await bridge.canRead(kTreeUri), isTrue);
      expect(fake.callsOf('canRead').single.arguments, <String, Object?>{
        'treeUri': kTreeUri,
      });
    });
  });

  group('SafBridge 异常映射', () {
    test('SecurityException → accessDenied', () async {
      fake.on('statItem', (Map<String, Object?> args) {
        throw PlatformException(code: 'accessDenied', message: 'no permission');
      });
      await expectLater(
        bridge.statItem(kTreeUri, kRootId),
        throwsA(isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.accessDenied)),
      );
    });

    test('notFound / providerOffline / 未知码分别映射', () async {
      fake.on('statItem', (Map<String, Object?> args) {
        throw PlatformException(code: 'notFound');
      });
      await expectLater(
        bridge.statItem(kTreeUri, kRootId),
        throwsA(isA<LanFileException>().having(
            (LanFileException e) => e.code, 'code', LanFileErrorCode.notFound)),
      );

      fake.on('statItem', (Map<String, Object?> args) {
        throw PlatformException(code: 'providerOffline');
      });
      await expectLater(
        bridge.statItem(kTreeUri, kRootId),
        throwsA(isA<LanFileException>().having((LanFileException e) => e.code,
            'code', LanFileErrorCode.providerOffline)),
      );

      fake.on('statItem', (Map<String, Object?> args) {
        throw PlatformException(code: 'someUnknownCode');
      });
      await expectLater(
        bridge.statItem(kTreeUri, kRootId),
        throwsA(isA<LanFileException>().having(
            (LanFileException e) => e.code, 'code', LanFileErrorCode.internal)),
      );
    });

    test('通道缺失 → unsupported', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel(kSafChannelName),
        null,
      );
      await expectLater(
        bridge.exists(kTreeUri, kRootId),
        throwsA(isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.unsupported)),
      );
      installChannel(fake);
    });
  });

  group('SafRef 分页游标', () {
    test('满页时给出 nextCursor，且 cursor = 最后一条 documentId', () async {
      fake.on('statItem', (Map<String, Object?> args) =>
          item(documentId: kRootId, name: 'DCIM', isDirectory: true));
      fake.on('listChildren', (Map<String, Object?> args) {
        // Kotlin 侧对 limit + 1 的探测请求返回 3 条，说明还有下一页。
        return <Object?>[
          item(documentId: '$kRootId/a.txt', size: 1),
          item(documentId: '$kRootId/b.txt', size: 2),
          item(documentId: '$kRootId/c.txt', size: 3),
        ];
      });

      final SafRef ref = rootRef(bridge);
      final FileEntryPage page = await ref.list(limit: 2);

      expect(page.entries.map((FileEntry e) => e.itemKey.value),
          <String>['$kRootId/a.txt', '$kRootId/b.txt']);
      expect(page.hasMore, isTrue);
      expect(page.nextCursor, '$kRootId/b.txt');
      // 探测请求用 limit + 1
      expect((fake.callsOf('listChildren').single.arguments
          as Map<Object?, Object?>)['limit'], 3);

      // 第二页用游标续取，返回不足一页即到末尾。
      fake.on('listChildren', (Map<String, Object?> args) {
        expect((args)['cursor'], '$kRootId/b.txt');
        return <Object?>[item(documentId: '$kRootId/c.txt', size: 3)];
      });
      final FileEntryPage page2 = await ref.list(cursor: page.nextCursor, limit: 2);
      expect(page2.entries.single.itemKey.value, '$kRootId/c.txt');
      expect(page2.hasMore, isFalse);
      expect(page2.nextCursor, isNull);
    });

    test('翻完两页不重不漏', () async {
      fake.on('statItem', (Map<String, Object?> args) =>
          item(documentId: kRootId, name: 'DCIM', isDirectory: true));
      final List<String> all = <String>[
        for (int i = 0; i < 5; i++) '$kRootId/f$i',
      ]..sort();
      fake.on('listChildren', (Map<String, Object?> args) {
        final String? cursor = args['cursor'] as String?;
        final int limit = args['limit']! as int;
        final List<String> rest = all
            .where((String id) => cursor == null || id.compareTo(cursor) > 0)
            .take(limit)
            .toList();
        return <Object?>[
          for (final String id in rest)
            item(documentId: id, size: 1),
        ];
      });

      final SafRef ref = rootRef(bridge);
      final List<String> seen = <String>[];
      String? cursor;
      int guard = 0;
      while (true) {
        final FileEntryPage page = await ref.list(cursor: cursor, limit: 2);
        seen.addAll(page.entries.map((FileEntry e) => e.itemKey.value));
        if (!page.hasMore) {
          break;
        }
        cursor = page.nextCursor;
        if (++guard > 10) {
          fail('分页未收敛');
        }
      }
      expect(seen, all);
      expect(seen.toSet().length, seen.length);
    });

    test('对文件调用 list 抛 invalidArgument', () async {
      fake.on('statItem', (Map<String, Object?> args) => item(
            documentId: kRootId,
            name: 'a.txt',
            size: 1,
            mime: 'text/plain',
          ));
      await expectLater(
        rootRef(bridge).list(limit: 10),
        throwsA(isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.invalidArgument)),
      );
      expect(fake.callsOf('listChildren'), isEmpty);
    });
  });

  group('SafRef 范围读取', () {
    test('openRead 传 start/endExclusive，并按块拼接', () async {
      fake.on('statItem', (Map<String, Object?> args) =>
          item(documentId: kRootId, name: 'big.bin', size: 600000));
      final List<Uint8List> chunks = <Uint8List>[
        Uint8List.fromList(List<int>.filled(262144, 7)),
        Uint8List.fromList(List<int>.filled(100, 8)),
      ];
      int index = 0;
      fake.on('openRead', (Map<String, Object?> args) {
        expect(args['start'], 1000);
        expect(args['endExclusive'], 600000);
        return 'saf-1';
      });
      fake.on('readChunk', (Map<String, Object?> args) {
        expect(args['handle'], 'saf-1');
        expect(args['maxBytes'], kSafReadChunkBytes);
        if (index >= chunks.length) {
          return null;
        }
        return chunks[index++];
      });
      fake.on('closeRead', (Map<String, Object?> args) => null);

      final List<int> bytes = <int>[];
      await for (final List<int> chunk
          in rootRef(bridge).openRead(start: 1000, endExclusive: 600000)) {
        bytes.addAll(chunk);
      }
      expect(bytes.length, 262144 + 100);
      expect(bytes.first, 7);
      expect(bytes.last, 8);
      expect(fake.callsOf('closeRead').length, 1);
    });

    test('读取中途抛错时仍然关闭句柄', () async {
      fake.on('statItem', (Map<String, Object?> args) =>
          item(documentId: kRootId, name: 'big.bin', size: 10));
      fake.on('openRead', (Map<String, Object?> args) => 'saf-2');
      fake.on('readChunk', (Map<String, Object?> args) {
        throw PlatformException(code: 'io', message: 'boom');
      });
      fake.on('closeRead', (Map<String, Object?> args) => null);

      await expectLater(
        rootRef(bridge).openRead().toList(),
        throwsA(isA<LanFileException>().having(
            (LanFileException e) => e.code, 'code', LanFileErrorCode.io)),
      );
      expect(fake.callsOf('closeRead').length, 1);
    });

    test('越界读取在 Dart 侧被拒', () async {
      fake.on('statItem', (Map<String, Object?> args) =>
          item(documentId: kRootId, name: 'big.bin', size: 100));
      fake.on('openRead', (Map<String, Object?> args) => 'saf-3');

      await expectLater(
        rootRef(bridge).openRead(start: 500).toList(),
        throwsA(isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.invalidArgument)),
      );
      expect(fake.callsOf('openRead'), isEmpty);
    });

    test('对目录调用 openRead 抛 invalidArgument', () async {
      fake.on('statItem', (Map<String, Object?> args) =>
          item(documentId: kRootId, name: 'DCIM', isDirectory: true));
      await expectLater(
        rootRef(bridge).openRead().toList(),
        throwsA(isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.invalidArgument)),
      );
    });
  });

  group('SafRef 属性与指纹', () {
    test('itemKey 用 documentId 而不是路径', () {
      final SafRef ref =
          rootRef(bridge, documentId: 'primary:DCIM/Camera/IMG_0001.jpg');
      expect(ref.itemKey.value, 'primary:DCIM/Camera/IMG_0001.jpg');
      expect(ref.documentId, 'primary:DCIM/Camera/IMG_0001.jpg');
      expect(ref.treeUri, kTreeUri);
      expect(ref.displayName, 'IMG_0001.jpg');
    });

    test('fingerprint 为 size-mtimeMs，并只打一次 statItem', () async {
      fake.on('statItem', (Map<String, Object?> args) => item(
            documentId: kRootId,
            name: 'a.bin',
            size: 1234,
            lastModified: 1700000000123,
          ));
      final SafRef ref = rootRef(bridge);
      expect(await ref.fingerprint(), '1234-1700000000123');
      expect(await ref.length(), 1234);
      expect((await ref.lastModified())!.toUtc().millisecondsSinceEpoch,
          1700000000123);
      expect(fake.callsOf('statItem').length, 1, reason: '属性应被缓存');
    });

    test('toEntry 与 length 目录返回 0', () async {
      fake.on('statItem', (Map<String, Object?> args) =>
          item(documentId: kRootId, name: 'DCIM', isDirectory: true));
      final SafRef ref = rootRef(bridge);
      expect(await ref.length(), 0);
      final FileEntry entry = ref.toEntry();
      expect(entry.kind, EntryKind.directory);
      expect(entry.isDirectory, isTrue);
      expect(entry.name, 'DCIM');
    });

    test('exists 在权限撤回时返回 false 而不是抛异常', () async {
      fake.on('exists', (Map<String, Object?> args) => false);
      expect(await rootRef(bridge).exists(), isFalse);
    });
  });

  group('SafRef.child 与 SafRefFactory', () {
    test('child 接受直接子项并拒绝跨层键', () async {
      fake.on('statItem', (Map<String, Object?> args) =>
          item(documentId: '$kRootId/sub', name: 'sub', isDirectory: true));
      final SafRef ref = rootRef(bridge);
      final FileRef child = await ref.child(ItemKey('$kRootId/sub'));
      expect(child.itemKey.value, '$kRootId/sub');
      expect(child.isDirectory, isTrue);

      await expectLater(
        ref.child(ItemKey('primary:Download/x')),
        throwsA(isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.invalidArgument)),
      );
    });

    test('factory.resolve 只接受 root 下的键', () async {
      fake.on('statItem', (args) => item(
            documentId: args['documentId'] as String,
            isDirectory: args['documentId'] == kRootId,
          ));
      final SafRefFactory factory = SafRefFactory(bridge);
      final FileRef ref = await factory.resolve(kTreeUri, ItemKey(kRootId));
      expect(ref.itemKey.value, kRootId);
      expect(ref.isDirectory, isTrue);

      final FileRef nested =
          await factory.resolve(kTreeUri, ItemKey('$kRootId/Camera/a.jpg'));
      expect(nested.itemKey.value, '$kRootId/Camera/a.jpg');
      expect(nested.isDirectory, isFalse);

      await expectLater(
        factory.resolve(kTreeUri, ItemKey('primary:Download/b.jpg')),
        throwsA(isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.invalidArgument)),
      );
    });

    test('factory.openRoot 从树 URI 解出根 documentId', () async {
      fake.on(
        'statItem',
        (_) => item(documentId: kRootId, name: 'DCIM', isDirectory: true),
      );
      final SafRefFactory factory = SafRefFactory(bridge);
      expect(factory.rootKind, ShareRootKind.safTree);
      final FileRef ref = await factory.openRoot(kTreeUri);
      expect(ref.itemKey.value, kRootId);
      expect((ref as SafRef).documentId, kRootId);
      expect(ref.displayName, 'DCIM');
      expect(ref.isDirectory, isTrue);
      expect(ref.toEntry().kind, EntryKind.directory);
      expect(fake.callsOf('statItem'), hasLength(1));
    });

    test('factory.openRoot 保留文件元数据且 documentId 只解码一次', () async {
      const documentId = 'primary:资料/100%20';
      final uri = Uri(
        scheme: 'content',
        host: 'com.android.externalstorage.documents',
        pathSegments: ['tree', documentId],
      ).toString();
      fake.on('statItem', (args) {
        expect(args['documentId'], documentId);
        return item(documentId: documentId, name: '100%20', size: 12);
      });
      final ref = await SafRefFactory(bridge).openRoot(uri);
      expect(ref.displayName, '100%20');
      expect(ref.isDirectory, isFalse);
      expect(await ref.length(), 12);
      expect(fake.callsOf('statItem'), hasLength(1));
    });

    test('factory.canRead 权限撤回返回 false', () async {
      final SafRefFactory factory = SafRefFactory(bridge);
      fake.on('canRead', (Map<String, Object?> args) => false);
      expect(await factory.canRead(kTreeUri), isFalse);

      fake.on('canRead', (Map<String, Object?> args) {
        throw PlatformException(code: 'accessDenied');
      });
      expect(await factory.canRead(kTreeUri), isFalse);
    });
  });
}
