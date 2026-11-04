// SPDX-License-Identifier: GPL-3.0-only

/// ShareServiceImpl.delete 的真实存储集成测试。
///
/// 真 sqlite 文件 + 真临时目录，不 mock 任何一层：
/// - delete 后 store.findShare 必须查不到；
/// - listItems 必须为空；
/// - **磁盘上的原始文件必须还在**（本产品只记位置，绝不碰用户文件）。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:lan_simple_file/core/files/local_ref_factory.dart';
import 'package:lan_simple_file/core/identity/capability_codec_impl.dart';
import 'package:lan_simple_file/core/identity/device_identity_impl.dart';
import 'package:lan_simple_file/core/identity/token_revocation_store.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/shares/share_service_impl.dart';
import 'package:lan_simple_file/core/store/store_impl.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory sandbox;
  late LanFileStoreImpl store;
  late ShareServiceImpl service;
  late PeerId self;

  setUp(() async {
    sandbox = Directory.systemTemp.createTempSync('lsf_delete_');
    store = await LanFileStoreImpl.open(
      dbFile: File(p.join(sandbox.path, 'delete.db')),
    );
    final Fixture f = _fixtureFor(store, sandbox);
    service = f.service;
    self = f.self;
  });

  tearDown(() async {
    await store.close();
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  group('delete', () {
    test('删后 findShare 为 null、listItems 为空、原文件仍在磁盘上', () async {
      final Directory tree = Directory(p.join(sandbox.path, 'shared'))
        ..createSync();
      final File keep = File(p.join(tree.path, 'important.txt'))
        ..writeAsStringSync('用户的重要数据');
      Directory(p.join(tree.path, 'sub')).createSync();
      File(p.join(tree.path, 'sub', 'nested.bin'))
          .writeAsBytesSync(List<int>.filled(64, 7));

      final ShareRecord record = await service.create(
        CreateShareRequest(
          rootKind: ShareRootKind.localPath,
          rootUri: tree.path,
          displayName: '要删的分享',
          mode: ShareMode.lan,
        ),
      );
      await service.awaitIndex(record.id);

      // 删之前：记录在、索引非空。
      expect(await store.findShare(record.id), isNotNull);
      expect((await store.listItems(record.id)).isNotEmpty, isTrue);
      final int indexedRows = (await store.listItems(record.id)).length;

      await service.delete(record.id);

      // 删之后：记录查不到，索引为空。
      expect(
        await store.findShare(record.id),
        isNull,
        reason: '删除必须真的从库里移除，而不只是 enabled=false',
      );
      expect(await store.listItems(record.id), isEmpty);

      // 关键：用户的原文件一个都不能少。
      expect(keep.existsSync(), isTrue, reason: '绝不能删除用户的原始文件');
      expect(keep.readAsStringSync(), '用户的重要数据');
      expect(
        Directory(p.join(tree.path, 'sub')).existsSync(),
        isTrue,
        reason: '子目录也必须原样保留',
      );
      expect(
        (await store.listItems(record.id)).length,
        0,
        reason: '索引已清空（之前是 $indexedRows 行）',
      );
    });

    test('删除幂等：同一个 id 删两次不抛', () async {
      final Directory tree = Directory(p.join(sandbox.path, 'twice'))
        ..createSync();
      File(p.join(tree.path, 'x.txt')).writeAsStringSync('x');
      final ShareRecord record = await service.create(
        CreateShareRequest(
          rootKind: ShareRootKind.localPath,
          rootUri: tree.path,
          displayName: '删两次',
          mode: ShareMode.lan,
        ),
      );
      await service.awaitIndex(record.id);

      await service.delete(record.id);
      // 第二次：不抛，且状态仍是不存在。
      await service.delete(record.id);
      expect(await store.findShare(record.id), isNull);
    });

    test('删除不存在的 id 不抛（幂等语义）', () async {
      await service.delete(ShareId.parse('never-existed'));
    });

    test('只删目标分享，不影响别的分享', () async {
      final Directory a = Directory(p.join(sandbox.path, 'a'))..createSync();
      final Directory b = Directory(p.join(sandbox.path, 'b'))..createSync();
      File(p.join(a.path, 'a.txt')).writeAsStringSync('a');
      File(p.join(b.path, 'b.txt')).writeAsStringSync('b');

      final ShareRecord ra = await service.create(
        CreateShareRequest(
          rootKind: ShareRootKind.localPath,
          rootUri: a.path,
          displayName: 'A',
          mode: ShareMode.lan,
        ),
      );
      final ShareRecord rb = await service.create(
        CreateShareRequest(
          rootKind: ShareRootKind.localPath,
          rootUri: b.path,
          displayName: 'B',
          mode: ShareMode.lan,
        ),
      );
      await service.awaitIndex(ra.id);
      await service.awaitIndex(rb.id);

      await service.delete(ra.id);

      expect(await store.findShare(ra.id), isNull);
      expect(
        await store.findShare(rb.id),
        isNotNull,
        reason: '删除 A 不能波及 B',
      );
      expect((await store.listItems(rb.id)).isNotEmpty, isTrue);
      expect((await service.listMine()).length, 1);
    });

    test('停止后再删除也成功（停用不是删除的前置阻碍）', () async {
      final Directory tree = Directory(p.join(sandbox.path, 'stopped'))
        ..createSync();
      File(p.join(tree.path, 'y.txt')).writeAsStringSync('y');
      final ShareRecord record = await service.create(
        CreateShareRequest(
          rootKind: ShareRootKind.localPath,
          rootUri: tree.path,
          displayName: '先停再删',
          mode: ShareMode.lan,
        ),
      );
      await service.awaitIndex(record.id);

      await service.stop(record.id);
      expect((await store.findShare(record.id))!.enabled, isFalse);

      await service.delete(record.id);
      expect(await store.findShare(record.id), isNull);
      expect(File(p.join(tree.path, 'y.txt')).existsSync(), isTrue);
    });
  });

  group('delete 与 resume 共用真实库', () {
    test('停用 -> 重新启用 -> 删除，全链路走通', () async {
      final Directory tree = Directory(p.join(sandbox.path, 'cycle'))
        ..createSync();
      File(p.join(tree.path, 'z.txt')).writeAsStringSync('z');
      final ShareRecord record = await service.create(
        CreateShareRequest(
          rootKind: ShareRootKind.localPath,
          rootUri: tree.path,
          displayName: '走一遍',
          mode: ShareMode.lan,
        ),
      );
      await service.awaitIndex(record.id);

      await service.stop(record.id);
      expect((await store.findShare(record.id))!.enabled, isFalse);

      await service.resume(record.id);
      expect((await store.findShare(record.id))!.enabled, isTrue);

      // 重新启用后索引还在，browse 立刻可用。
      final ({List<TreeEntryView> entries, String? nextCursor}) page =
          await service.browse(record.id);
      expect(page.entries.single.name, 'z.txt');

      await service.delete(record.id);
      expect(await store.findShare(record.id), isNull);
      expect(await store.listItems(record.id), isEmpty);
    });

    test('ownerPeerId 是本机身份（删除/启用都不改归属）', () async {
      final Directory tree = Directory(p.join(sandbox.path, 'own'))
        ..createSync();
      final ShareRecord record = await service.create(
        CreateShareRequest(
          rootKind: ShareRootKind.localPath,
          rootUri: tree.path,
          displayName: '归属',
          mode: ShareMode.lan,
        ),
      );
      expect(record.ownerPeerId, self);
      await service.awaitIndex(record.id);
      await service.stop(record.id);
      expect((await store.findShare(record.id))!.ownerPeerId, self);
      await service.resume(record.id);
      expect((await store.findShare(record.id))!.ownerPeerId, self);
    });
  });
}

/// 造一套最小真实夹具（真身份 + 真 codec + 真工厂）。
final class Fixture {
  const Fixture({required this.service, required this.self});

  final ShareServiceImpl service;
  final PeerId self;
}

/// 与 test/core/shares/shares_test_support.dart 同构的最小版本。
///
/// 不复用那边的文件：它属于另一个任务的测试夹具，
/// 跨任务 import 会把两个目录绑死，改动互相牵制。
Fixture _fixtureFor(LanFileStoreImpl store, Directory sandbox) {
  final DeviceIdentityImpl identity = DeviceIdentityImpl.fromSeed(
    Uint8List.fromList(List<int>.generate(32, (int i) => (i * 3) & 0xff)),
  );
  final MapKeyLookup keys = MapKeyLookup()
    ..register(identity.peerId, identity.publicKey);
  final CapabilityCodecImpl codec = CapabilityCodecImpl(
    issuer: identity,
    revoked: TokenRevocationStore(),
    keys: keys,
  );
  return Fixture(
    self: identity.peerId,
    service: ShareServiceImpl(
      store: store,
      identity: identity,
      codec: codec,
      localFactory: const LocalRefFactory(),
    ),
  );
}

/// 内存公钥表。
final class MapKeyLookup implements PublicKeyLookup {
  final Map<String, Uint8List> _keys = <String, Uint8List>{};

  void register(PeerId peerId, Uint8List key) {
    _keys[peerId.value] = Uint8List.fromList(key);
  }

  @override
  Future<Uint8List?> findPublicKey(PeerId peerId) async => _keys[peerId.value];
}