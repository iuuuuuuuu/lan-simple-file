// SPDX-License-Identifier: GPL-3.0-only

/// ShareServiceImpl 的行为测试。
///
/// 真实 sqlite 文件 + 真实临时目录 + 真实 Ed25519 身份，
/// 唯一替换的是 PeerOnlineProbe（发现层的窄接口，见 shares_test_support）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/errors.dart';
import 'package:lan_simple_file/core/contracts/file_ref.dart';
import 'package:lan_simple_file/core/contracts/identity.dart';
import 'package:lan_simple_file/core/contracts/services.dart';
import 'package:lan_simple_file/core/contracts/store.dart';
import 'package:lan_simple_file/core/contracts/types.dart';
import 'package:lan_simple_file/core/shares/index_scanner.dart';
import 'package:lan_simple_file/core/shares/share_service_impl.dart';
import 'package:path/path.dart' as p;

import 'shares_test_support.dart';

/// 一页页翻完，顺带断言每页条数不超过 limit。
Future<List<TreeEntryView>> drainAll(
  ShareServiceImpl service,
  ShareId id, {
  ItemKey? path,
  required int limit,
}) async {
  final List<TreeEntryView> all = <TreeEntryView>[];
  String? cursor;
  var pages = 0;
  do {
    final ({List<TreeEntryView> entries, String? nextCursor}) page =
        await service.browse(id, path: path, cursor: cursor, limit: limit);
    expect(page.entries.length, lessThanOrEqualTo(limit));
    all.addAll(page.entries);
    cursor = page.nextCursor;
    pages++;
    expect(pages, lessThan(200), reason: '分页必须能终止');
  } while (cursor != null);
  return all;
}

void main() {
  late SharesFixture fx;

  setUp(() async {
    fx = await SharesFixture.create();
  });

  tearDown(() async {
    await fx.dispose();
  });

  group('create', () {
    test('建 folder 分享：落库、根存在、enabled 为真', () async {
      final Directory tree = fx.makeTree('docs');
      final ShareServiceImpl service = fx.service();

      final ShareRecord record = await service.create(
        CreateShareRequest(
          rootKind: ShareRootKind.localPath,
          rootUri: tree.path,
          displayName: '我的文档',
          mode: ShareMode.lan,
        ),
      );

      expect(record.kind, 'folder');
      expect(record.displayName, '我的文档');
      expect(record.enabled, isTrue);
      expect(record.missing, isFalse);
      expect(record.isEphemeral, isFalse);
      expect(record.ownerPeerId, fx.identity.peerId);
      final ShareRecord? stored = await fx.store.findShare(record.id);
      expect(stored, isNotNull);
      expect(stored!.rootUri, tree.path);
    });

    test('create 不阻塞：返回时索引未写完也能拿到记录', () async {
      final Directory tree = fx.makeTree('slow', filesPerDir: 20, depth: 3);
      final ShareServiceImpl service = fx.service();

      final ShareRecord record = await service.create(
        CreateShareRequest(
          rootKind: ShareRootKind.localPath,
          rootUri: tree.path,
          displayName: '大树',
          mode: ShareMode.lan,
        ),
      );

      // 记录在启动后台扫描之前就已落库。
      expect(await fx.store.findShare(record.id), isNotNull);
      // 扫描句柄存在，证明首扫是后台任务而不是同步跑完。
      final ScanResult? scanned = await service.awaitIndex(record.id);
      expect(scanned, isNotNull, reason: '后台首扫必须能被等到');
      expect(scanned!.itemsIndexed, greaterThan(0));
    });

    test('单文件分享：kind 自动判定为 file', () async {
      final File single = File(p.join(fx.sandbox.path, 'one.txt'))
        ..writeAsStringSync('hello');
      final ShareServiceImpl service = fx.service();

      final ShareRecord record = await service.create(
        CreateShareRequest(
          rootKind: ShareRootKind.localPath,
          rootUri: single.path,
          displayName: '单文件',
          mode: ShareMode.lan,
        ),
      );
      expect(record.kind, 'file');
    });

    test('根不存在 → notFound，且不落库', () async {
      final ShareServiceImpl service = fx.service();
      await expectLater(
        service.create(
          CreateShareRequest(
            rootKind: ShareRootKind.localPath,
            rootUri: p.join(fx.sandbox.path, 'no-such-dir'),
            displayName: 'x',
            mode: ShareMode.lan,
          ),
        ),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.notFound,
          ),
        ),
      );
      expect(await service.listMine(), isEmpty);
    });

    test('相对根 → invalidArgument（准入闸门生效）', () async {
      final ShareServiceImpl service = fx.service();
      await expectLater(
        service.create(
          CreateShareRequest(
            rootKind: ShareRootKind.localPath,
            rootUri: 'relative/docs',
            displayName: 'x',
            mode: ShareMode.lan,
          ),
        ),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.invalidArgument,
          ),
        ),
      );
    });

    test('空名字 → invalidArgument', () async {
      final Directory tree = fx.makeTree('named');
      final ShareServiceImpl service = fx.service();
      await expectLater(
        service.create(
          CreateShareRequest(
            rootKind: ShareRootKind.localPath,
            rootUri: tree.path,
            displayName: '   ',
            mode: ShareMode.lan,
          ),
        ),
        throwsA(isA<LanFileException>()),
      );
    });
  });

  group('browse 分页', () {
    test('三层树：逐层翻页不重不漏', () async {
      final Directory tree = fx.makeTree('browse', filesPerDir: 5, depth: 2);
      final ShareServiceImpl service = fx.service();
      final ShareRecord record = await service.create(
        CreateShareRequest(
          rootKind: ShareRootKind.localPath,
          rootUri: tree.path,
          displayName: '浏览树',
          mode: ShareMode.lan,
        ),
      );
      await service.awaitIndex(record.id);

      // 第一层：根下 5 个文件 + d0 目录 = 6 项。
      final List<TreeEntryView> rootEntries = await drainAll(
        service,
        record.id,
        limit: 2,
      );
      expect(rootEntries.length, 6);
      expect(
        rootEntries.map((TreeEntryView e) => e.name).toList(),
        <String>['d0', 'f0_0.txt', 'f0_1.txt', 'f0_2.txt', 'f0_3.txt', 'f0_4.txt'],
        reason: '必须按 name 升序',
      );

      // 整棵树：递归收集，断言不重复且总数对得上。
      final Set<String> seen = <String>{};
      Future<void> walk(ItemKey key) async {
        final List<TreeEntryView> entries = await drainAll(
          service,
          record.id,
          path: key,
          limit: 2,
        );
        for (final TreeEntryView e in entries) {
          expect(
            seen.add(e.itemKey.value),
            isTrue,
            reason: '重复条目：${e.itemKey.value}',
          );
          if (e.isDirectory) await walk(e.itemKey);
        }
      }

      await walk(ItemKey.parse('.'));
      // 根 5 文件 + d0；d0 5 文件 + d1；d1 5 文件 = 17。
      expect(seen.length, 17);
    });

    test('cursor 就是上一页最后一条的 itemKey', () async {
      final Directory tree = Directory(p.join(fx.sandbox.path, 'cursor'))
        ..createSync();
      for (var i = 0; i < 5; i++) {
        File(p.join(tree.path, 'n$i')).writeAsStringSync('x');
      }
      final ShareServiceImpl service = fx.service();
      final ShareRecord record = await service.create(
        CreateShareRequest(
          rootKind: ShareRootKind.localPath,
          rootUri: tree.path,
          displayName: '游标',
          mode: ShareMode.lan,
        ),
      );
      await service.awaitIndex(record.id);

      final ({List<TreeEntryView> entries, String? nextCursor}) first =
          await service.browse(record.id, limit: 2);
      expect(first.entries.length, 2);
      expect(first.nextCursor, first.entries.last.itemKey.value);

      final ({List<TreeEntryView> entries, String? nextCursor}) second =
          await service.browse(record.id, cursor: first.nextCursor, limit: 2);
      expect(
        second.entries.map((TreeEntryView e) => e.name).toList(),
        <String>['n2', 'n3'],
      );
    });

    test('limit 默认取 LanFileConstants.treePageSize', () async {
      final Directory tree = Directory(p.join(fx.sandbox.path, 'default'))
        ..createSync();
      for (var i = 0; i < 3; i++) {
        File(p.join(tree.path, 'd$i')).writeAsStringSync('x');
      }
      final ShareServiceImpl service = fx.service();
      final ShareRecord record = await service.create(
        CreateShareRequest(
          rootKind: ShareRootKind.localPath,
          rootUri: tree.path,
          displayName: '默认页大小',
          mode: ShareMode.lan,
        ),
      );
      await service.awaitIndex(record.id);
      final ({List<TreeEntryView> entries, String? nextCursor}) page =
          await service.browse(record.id);
      expect(page.entries.length, 3);
      expect(page.nextCursor, isNull);
    });

    test('单文件分享 browse 返回该文件', () async {
      final File single = File(p.join(fx.sandbox.path, 'solo.txt'))
        ..writeAsStringSync('solo-content');
      final ShareServiceImpl service = fx.service();
      final ShareRecord record = await service.create(
        CreateShareRequest(
          rootKind: ShareRootKind.localPath,
          rootUri: single.path,
          displayName: '单文件',
          mode: ShareMode.lan,
        ),
      );
      await service.awaitIndex(record.id);

      final ({List<TreeEntryView> entries, String? nextCursor}) page =
          await service.browse(record.id);
      expect(page.entries.length, 1);
      expect(page.entries.single.name, 'solo.txt');
      expect(page.entries.single.isDirectory, isFalse);
      expect(page.entries.single.size, 'solo-content'.length);
      expect(page.nextCursor, isNull);
    });

    test('索引缺失时才回退实时列举（新建子目录后立即可见）', () async {
      final Directory tree = fx.makeTree('fallback', filesPerDir: 1, depth: 1);
      final ShareServiceImpl service = fx.service();
      final ShareRecord record = await service.create(
        CreateShareRequest(
          rootKind: ShareRootKind.localPath,
          rootUri: tree.path,
          displayName: '回退',
          mode: ShareMode.lan,
        ),
      );
      await service.awaitIndex(record.id);

      // 索引完成后新增一个目录：索引里没有它，browse 该目录要能回退实时列。
      final Directory fresh = Directory(p.join(tree.path, 'brand-new'))
        ..createSync();
      File(p.join(fresh.path, 'inside.txt')).writeAsStringSync('inside');

      final ({List<TreeEntryView> entries, String? nextCursor}) page =
          await service.browse(record.id, path: ItemKey.parse('brand-new'));
      expect(page.entries.single.name, 'inside.txt');
    });

    test('中文目录名：前缀按 rune 算，不错位到别的子树', () async {
      final Directory tree = Directory(p.join(fx.sandbox.path, 'cn'))
        ..createSync();
      final Directory cn = Directory(p.join(tree.path, '中文 目录'))
        ..createSync();
      File(p.join(cn.path, '甲.txt')).writeAsStringSync('jia');
      File(p.join(cn.path, '乙.txt')).writeAsStringSync('yi');
      // 同名前半段的兄弟目录，专门用来抓前缀错位。
      final Directory sibling = Directory(p.join(tree.path, '中文 目录二'))
        ..createSync();
      File(p.join(sibling.path, '丙.txt')).writeAsStringSync('bing');

      final ShareServiceImpl service = fx.service();
      final ShareRecord record = await service.create(
        CreateShareRequest(
          rootKind: ShareRootKind.localPath,
          rootUri: tree.path,
          displayName: '中文',
          mode: ShareMode.lan,
        ),
      );
      await service.awaitIndex(record.id);

      final ({List<TreeEntryView> entries, String? nextCursor}) page =
          await service.browse(record.id, path: ItemKey.parse('中文 目录'));
      expect(
        page.entries.map((TreeEntryView e) => e.name).toList(),
        <String>['乙.txt', '甲.txt'],
        reason: '只应看到该目录自己的两项，不能串到「中文 目录二」',
      );
    });

    test('limit <= 0 → invalidArgument', () async {
      final Directory tree = fx.makeTree('badlimit');
      final ShareServiceImpl service = fx.service();
      final ShareRecord record = await service.create(
        CreateShareRequest(
          rootKind: ShareRootKind.localPath,
          rootUri: tree.path,
          displayName: 'x',
          mode: ShareMode.lan,
        ),
      );
      await expectLater(
        service.browse(record.id, limit: 0),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.invalidArgument,
          ),
        ),
      );
    });

    test('路径穿越的 path → invalidArgument', () async {
      final Directory tree = fx.makeTree('escape');
      final ShareServiceImpl service = fx.service();
      final ShareRecord record = await service.create(
        CreateShareRequest(
          rootKind: ShareRootKind.localPath,
          rootUri: tree.path,
          displayName: 'x',
          mode: ShareMode.lan,
        ),
      );
      for (final String bad in <String>['..', '../../etc', 'a/../../b']) {
        await expectLater(
          service.browse(record.id, path: ItemKey.parse(bad)),
          throwsA(
            isA<LanFileException>().having(
              (LanFileException e) => e.code,
              'code',
              LanFileErrorCode.invalidArgument,
            ),
          ),
          reason: '应拒绝 $bad',
        );
      }
    });
  });

  group('stop / resume', () {
    test('stop 后 listMine 仍能看到，enabled=false，索引仍在', () async {
      final Directory tree = fx.makeTree('stopped', filesPerDir: 2, depth: 1);
      final ShareServiceImpl service = fx.service();
      final ShareRecord record = await service.create(
        CreateShareRequest(
          rootKind: ShareRootKind.localPath,
          rootUri: tree.path,
          displayName: '停用',
          mode: ShareMode.lan,
        ),
      );
      await service.awaitIndex(record.id);
      final int indexedBefore = (await fx.store.listItems(record.id)).length;
      expect(indexedBefore, greaterThan(0));

      await service.stop(record.id);

      final List<ShareRecord> mine = await service.listMine();
      expect(mine.length, 1, reason: '停用不是删除，记录必须还在');
      expect(mine.single.id, record.id);
      expect(mine.single.enabled, isFalse);
      // 索引不删：重新启用要能立刻用。
      expect((await fx.store.listItems(record.id)).length, indexedBefore);
    });

    test('重新启用后 browse 又能用，且走的是原索引', () async {
      final Directory tree = fx.makeTree('resume', filesPerDir: 3, depth: 1);
      final ShareServiceImpl service = fx.service();
      final ShareRecord record = await service.create(
        CreateShareRequest(
          rootKind: ShareRootKind.localPath,
          rootUri: tree.path,
          displayName: '恢复',
          mode: ShareMode.lan,
        ),
      );
      await service.awaitIndex(record.id);
      await service.stop(record.id);
      await service.resume(record.id);

      final ({List<TreeEntryView> entries, String? nextCursor}) page =
          await service.browse(record.id, limit: 100);
      expect(page.entries.length, 4, reason: '3 文件 + d0');
      expect((await service.listMine()).single.enabled, isTrue);
    });

    test('stop 不存在的分享 → notFound', () async {
      final ShareServiceImpl service = fx.service();
      await expectLater(
        service.stop(ShareId.parse('nope-0001')),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.notFound,
          ),
        ),
      );
    });
  });

  group('relocate', () {
    test('改根后 browse 看到新内容，相对新根被拒', () async {
      final Directory first = fx.makeTree('first', filesPerDir: 1, depth: 0);
      final Directory second = fx.makeTree('second', filesPerDir: 2, depth: 1);
      final ShareServiceImpl service = fx.service();
      final ShareRecord record = await service.create(
        CreateShareRequest(
          rootKind: ShareRootKind.localPath,
          rootUri: first.path,
          displayName: '重定位',
          mode: ShareMode.lan,
        ),
      );
      await service.awaitIndex(record.id);

      await service.relocate(record.id, second.path);
      await service.awaitIndex(record.id);

      final ShareRecord after = (await fx.store.findShare(record.id))!;
      expect(p.equals(after.rootUri, second.path), isTrue);
      final ({List<TreeEntryView> entries, String? nextCursor}) page =
          await service.browse(record.id, limit: 100);
      expect(page.entries.length, 3, reason: 'second 下 2 文件 + d0');

      await expectLater(
        service.relocate(record.id, 'relative/path'),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.invalidArgument,
          ),
        ),
      );
    });

    test('relocate 到不存在目录 → notFound 且原记录不变', () async {
      final Directory tree = fx.makeTree('keep', filesPerDir: 1, depth: 0);
      final ShareServiceImpl service = fx.service();
      final ShareRecord record = await service.create(
        CreateShareRequest(
          rootKind: ShareRootKind.localPath,
          rootUri: tree.path,
          displayName: '保持',
          mode: ShareMode.lan,
        ),
      );
      await expectLater(
        service.relocate(record.id, p.join(fx.sandbox.path, 'ghost')),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.notFound,
          ),
        ),
      );
      final ShareRecord after = (await fx.store.findShare(record.id))!;
      expect(
        p.equals(after.rootUri, tree.path),
        isTrue,
        reason: '失败不应改库',
      );
    });
  });

  group('源失效', () {
    test('源目录被删后 browse 置 missing，offlineHint 可读', () async {
      final Directory tree = fx.makeTree('vanish', filesPerDir: 1, depth: 1);
      final ShareServiceImpl service = fx.service();
      final ShareRecord record = await service.create(
        CreateShareRequest(
          rootKind: ShareRootKind.localPath,
          rootUri: tree.path,
          displayName: '会消失',
          mode: ShareMode.lan,
        ),
      );
      await service.awaitIndex(record.id);

      tree.deleteSync(recursive: true);

      // 索引里还有旧条目，所以必须挑一个索引里没有的路径，
      // 走到实时列举那条路，才会发现源已经没了。
      await expectLater(
        service.browse(record.id, path: ItemKey.parse('never-indexed')),
        throwsA(isA<LanFileException>()),
      );

      final ShareRecord after = (await fx.store.findShare(record.id))!;
      expect(after.missing, isTrue, reason: '源没了必须置 missing');

      final List<SharedRootView> views =
          await service.listPeerShares(fx.identity.peerId);
      expect(views.single.available, isFalse);
      expect(views.single.offlineHint, isNotNull);
      expect(views.single.offlineHint, isNotEmpty);
      expect(views.single.offlineHint, contains('失效'));
    });
  });

  group('listPeerShares 四种不可用原因', () {
    /// 直接落一条指定状态的分享记录，绕过 create（create 永远建 enabled 的）。
    Future<ShareRecord> seedShare({
      required String id,
      required bool enabled,
      required bool missing,
      DateTime? revokedAt,
    }) async {
      final Directory tree = fx.makeTree('peer-$id', filesPerDir: 1, depth: 0);
      final ShareRecord record = ShareRecord(
        id: ShareId.parse(id),
        kind: 'folder',
        rootKind: ShareRootKind.localPath.name,
        rootUri: tree.path,
        displayName: '同伴分享-$id',
        ownerPeerId: fx.otherIdentity.peerId,
        createdAt: DateTime.utc(2026, 1, 1),
        mode: ShareMode.lan,
        enabled: enabled,
        missing: missing,
        isEphemeral: false,
        revokedAt: revokedAt,
      );
      await fx.store.upsertShare(record);
      return record;
    }

    test('全部可用时 available=true 且 offlineHint 为 null', () async {
      await seedShare(id: 'ok-0001', enabled: true, missing: false);
      fx.probe.setOnline(fx.otherIdentity.peerId, online: true);
      final List<SharedRootView> views =
          await fx.service().listPeerShares(fx.otherIdentity.peerId);
      expect(views.single.available, isTrue);
      expect(views.single.offlineHint, isNull);
    });

    test('原因一：提供者离线 → 含「离线」的中文提示', () async {
      await seedShare(id: 'off-0001', enabled: true, missing: false);
      // 复用同一个库，避免同进程开第二个连接（drift 会告警）。
      fx.probe.setOnline(fx.otherIdentity.peerId, online: false);
      fx.probe.setLastSeen(
        fx.otherIdentity.peerId,
        DateTime.utc(2026, 1, 1, 0, 3),
      );
      final DateTime now = DateTime.utc(2026, 1, 1, 0, 6);
      final List<SharedRootView> views =
          await fx.service(clock: () => now).listPeerShares(
        fx.otherIdentity.peerId,
      );
      expect(views.single.available, isFalse);
      final String hint = views.single.offlineHint!;
      expect(hint, isNotEmpty);
      expect(hint, contains('离线'));
      expect(hint, contains('最后在线'));
      expect(hint, contains('3 分钟前'), reason: '必须给出可读的相对时间');
    });
    test('原因二：已停用 → 含「停止共享」的中文提示', () async {
      await seedShare(id: 'dis-0001', enabled: false, missing: false);
      final List<SharedRootView> views =
          await fx.service().listPeerShares(fx.otherIdentity.peerId);
      expect(views.single.available, isFalse);
      final String hint = views.single.offlineHint!;
      expect(hint, isNotEmpty);
      expect(hint, contains('停止共享'));
    });

    test('原因三：源已失效 → 含「失效」的中文提示', () async {
      await seedShare(id: 'mis-0001', enabled: true, missing: true);
      final List<SharedRootView> views =
          await fx.service().listPeerShares(fx.otherIdentity.peerId);
      expect(views.single.available, isFalse);
      final String hint = views.single.offlineHint!;
      expect(hint, isNotEmpty);
      expect(hint, contains('失效'));
    });

    test('原因四：已撤销 → 含「撤销」的中文提示', () async {
      await seedShare(
        id: 'rev-0001',
        enabled: true,
        missing: false,
        revokedAt: DateTime.utc(2026, 1, 2),
      );
      final List<SharedRootView> views =
          await fx.service().listPeerShares(fx.otherIdentity.peerId);
      expect(views.single.available, isFalse);
      final String hint = views.single.offlineHint!;
      expect(hint, isNotEmpty);
      expect(hint, contains('撤销'));
    });

    test('四种提示互不相同，且都是中文', () async {
      final Set<String> hints = <String>{};
      for (final UnavailableReason reason in UnavailableReason.values) {
        final String hint = describeUnavailable(
          reason,
          lastSeen: DateTime.utc(2026, 1, 1),
          clock: () => DateTime.utc(2026, 1, 1, 0, 5),
        );
        expect(hint, isNotEmpty);
        expect(
          RegExp(r'[\u4e00-\u9fff]').hasMatch(hint),
          isTrue,
          reason: '必须含中文：$hint',
        );
        expect(hints.add(hint), isTrue, reason: '原因文案不得重复：$hint');
      }
      expect(hints.length, 4);
    });

    test('从未见过的 peer：offlineHint 也说成人话，不出现英文', () async {
      final String hint = describeUnavailable(UnavailableReason.offline);
      expect(hint, isNotEmpty);
      expect(hint, contains('离线'));
      expect(RegExp(r'[A-Za-z]{4,}').hasMatch(hint), isFalse);
    });
  });

  group('buildLink 不得含网络地址', () {
    Future<ShareRecord> seededShare(ShareMode mode, String id) async {
      final Directory tree = fx.makeTree('link-$id', filesPerDir: 1, depth: 0);
      final ShareRecord record = ShareRecord(
        id: ShareId.parse(id),
        kind: 'folder',
        rootKind: ShareRootKind.localPath.name,
        rootUri: tree.path,
        displayName: '链接-$id',
        ownerPeerId: fx.identity.peerId,
        createdAt: DateTime.utc(2026, 1, 1),
        mode: mode,
        enabled: true,
        missing: false,
        isEphemeral: false,
      );
      await fx.store.upsertShare(record);
      return record;
    }

    test('lan 模式：裸链接，无 token，且不含任何网络地址', () async {
      final ShareRecord record = await seededShare(ShareMode.lan, 'lnk-0001');
      final Uri link = await fx.service().buildLink(record.id);
      final String text = link.toString();

      expect(link.scheme, 'lsf');
      expect(link.host, 'open');
      expect(link.queryParameters['share'], record.id.value);
      expect(link.queryParameters.containsKey('k'), isFalse);

      for (final String forbidden in <String>[
        '192.168',
        '127.0.0.1',
        'http://',
        'localhost',
        '47778',
      ]) {
        expect(
          text.contains(forbidden),
          isFalse,
          reason: '链接不得包含 $forbidden：$text',
        );
      }
      expect(link.hasPort, isFalse);
    });

    test('token 模式：带凭证，且凭证能被离线验签通过', () async {
      final ShareRecord record = await seededShare(ShareMode.token, 'lnk-0002');
      final Uri link = await fx.service(clock: () => kFixtureNow).buildLink(record.id);
      final String text = link.toString();
      final String? token = link.queryParameters['k'];
      expect(token, isNotNull);
      expect(token, isNotEmpty);

      for (final String forbidden in <String>[
        '192.168',
        '127.0.0.1',
        'http://',
        'localhost',
      ]) {
        expect(text.contains(forbidden), isFalse, reason: '不得包含 $forbidden');
      }

      // 用同一个 codec 离线验签：证明链接里的凭证是真的，不是随便拼的字符串。
      final CapabilityClaims claims = await fx.codec.verify(token!);
      expect(claims.shareId, record.id);
      expect(claims.issuer, fx.identity.peerId);
      expect(claims.subject, '*');
      expect(claims.permissions.contains('read'), isTrue);
    });

    test('显式 grant：shareId 不一致被拒', () async {
      final ShareRecord record = await seededShare(ShareMode.token, 'lnk-0003');
      final CapabilityGrant wrong = CapabilityGrant(
        shareId: ShareId.parse('other-9999'),
        issuer: fx.identity.peerId,
        subject: '*',
        permissions: const <String>{'read'},
        notBefore: DateTime.utc(2026, 1, 1),
        expiresAt: DateTime.utc(2026, 1, 2),
        tokenId: 'jti-wrong',
      );
      await expectLater(
        fx.service().buildLink(record.id, grant: wrong),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.invalidArgument,
          ),
        ),
      );
    });

    test('已撤销的分享不出链接 → revoked', () async {
      final ShareRecord record = await seededShare(ShareMode.lan, 'lnk-0004');
      await fx.store.revokeShare(record.id, at: DateTime.utc(2026, 1, 2));
      await expectLater(
        fx.service().buildLink(record.id),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.revoked,
          ),
        ),
      );
    });

    test('链接可被 parseLink 解析回 shareId 与 token', () async {
      final ShareRecord record = await seededShare(ShareMode.token, 'lnk-0005');
      final ShareServiceImpl service = fx.service(clock: () => kFixtureNow);
      final Uri link = await service.buildLink(record.id);
      final ({ShareId shareId, String? token}) parsed = service.parseLink(link);
      expect(parsed.shareId, record.id);
      expect(parsed.token, link.queryParameters['k']);
    });
  });
}