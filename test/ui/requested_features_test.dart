// SPDX-License-Identifier: GPL-3.0-only

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/widgets/identicon.dart';
import 'package:lan_simple_file/core/contacts/peer_groups.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/ui/pages/groups_page.dart';
import 'package:lan_simple_file/ui/pages/nearby_page.dart';
import 'package:lan_simple_file/ui/pages/settings_page.dart';
import 'package:lan_simple_file/ui/pages/shares_page.dart';
import 'package:lan_simple_file/ui/shell/session_rail.dart';
import 'package:lan_simple_file/ui/widgets/avatar_picker.dart';

import 'settings_page_test.dart' show FakeSettingsSource, snapshotOf;
import 'support/ui_fakes.dart';

class MemoryPeerGroups implements PeerGroupsSource {
  PeerGroups value = const PeerGroups();
  @override
  Future<PeerGroups> load() async => value;
  @override
  Future<void> save(PeerGroups groups) async {
    value = groups;
  }
}

final Uint8List png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGM4sdDoPwAGawKb0aSw4gAAAABJRU5ErkJggg==',
);

void main() {
  testWidgets('分享可命名，卡片继续显示源的完整位置', (tester) async {
    const String path = r'D:\素材\照片.jpg';
    final FakeMySharesSource source = FakeMySharesSource()
      ..shares = <ShareRecord>[
        shareRecord(
          id: 'rename01',
          kind: 'file',
          displayName: '照片.jpg',
          rootUri: path,
        ),
      ];
    await tester.pumpWidget(wrapWithTheme(SharesPage(source: source)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('share-actions-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置分享名称'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('share-name-field')),
      '旅行照片',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(source.shares.single.displayName, '旅行照片');
    expect(source.shares.single.rootUri, path);
    expect(find.text('旅行照片'), findsOneWidget);
    expect(find.text(path), findsOneWidget);
  });

  testWidgets('头像与昵称居中，群聊合并到联系人入口', (tester) async {
    await tester.pumpWidget(
      wrapWithTheme(
        SessionRail(
          selected: ShellSection.nearby,
          onSelect: (_) {},
          selfPeerId: peerOf('00').value,
          selfName: 'iuuuuuuuu',
          onOpenSettings: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final double avatarX = tester.getCenter(find.byType(PeerAvatar)).dx;
    final double nicknameX = tester.getCenter(find.text('iuuuuuuuu')).dx;
    final double railX = tester
        .getCenter(find.byKey(const ValueKey<String>('shell-rail')))
        .dx;
    expect(avatarX, closeTo(nicknameX, 0.1));
    expect(avatarX, closeTo(railX, 0.1));
    final double nearbyY = tester
        .getCenter(find.byKey(const ValueKey<String>('rail-nearby')))
        .dy;
    final double sharesY = tester
        .getCenter(find.byKey(const ValueKey<String>('rail-shares')))
        .dy;
    expect(find.byKey(const ValueKey<String>('rail-groups')), findsNothing);
    expect(sharesY, greaterThan(nearbyY));
  });

  testWidgets('修改头像和恢复默认调用保存能力并更新图片', (tester) async {
    final List<Uint8List?> saved = <Uint8List?>[];
    await tester.pumpWidget(
      wrapWithTheme(
        SettingsPage(
          source: FakeSettingsSource(snapshotOf()),
          avatarPicker: () async => png,
          saveAvatar: (Uint8List? bytes) async {
            saved.add(bytes);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('change-avatar')));
    await tester.pumpAndSettle();
    expect(saved.single, orderedEquals(png));
    expect(find.text('头像已保存'), findsOneWidget);
    final PeerAvatar avatar = tester.widget<PeerAvatar>(
      find.byType(PeerAvatar),
    );
    expect(avatar.avatarBytes, orderedEquals(png));
    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();
    expect(saved.last, isNull);
    expect(
      tester.widget<PeerAvatar>(find.byType(PeerAvatar)).avatarBytes,
      isNull,
    );
  });

  testWidgets('头像裁剪输出固定大小 PNG', (tester) async {
    final Uint8List? output = await tester.runAsync(
      () => normalizeAvatarImage(png),
    );
    expect(output, isNotNull);
    expect(output!.take(8), <int>[137, 80, 78, 71, 13, 10, 26, 10]);
    final ({int width, int height})? size = await tester.runAsync(() async {
      final ui.Codec codec = await ui.instantiateImageCodec(output);
      try {
        final ui.Image image = (await codec.getNextFrame()).image;
        try {
          return (width: image.width, height: image.height);
        } finally {
          image.dispose();
        }
      } finally {
        codec.dispose();
      }
    });
    expect(size, (width: 256, height: 256));
  });

  testWidgets('陌生人可移动到自建分组，重命名/删除和重开页面均正确', (tester) async {
    final MemoryPeerGroups groups = MemoryPeerGroups();
    final FakeNearbySource source = FakeNearbySource()
      ..peers = <PeerView>[peerView(suffix: '01', name: '小明')];
    Widget page(Key key) => wrapWithTheme(
      NearbyPage(key: key, source: source, groupsSource: groups),
    );
    await tester.pumpWidget(page(const ValueKey<String>('first')));
    await tester.pumpAndSettle();
    expect(find.text('陌生人 (1)'), findsOneWidget);
    expect(find.text('重新搜索'), findsNothing);
    expect(find.byTooltip('刷新'), findsNothing);
    await tester.tap(find.byTooltip('新建分组'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('peer-group-name-field')),
      '同事',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('移动到分组'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同事'));
    await tester.pumpAndSettle();
    expect(find.text('陌生人 (0)'), findsOneWidget);
    expect(find.text('同事 (1)'), findsOneWidget);
    expect(groups.value.groupOf(peerOf('01')), groups.value.names.keys.single);

    await tester.pumpWidget(page(const ValueKey<String>('reopened')));
    await tester.pumpAndSettle();
    expect(find.text('同事 (1)'), findsOneWidget);
    await tester.tap(find.byTooltip('管理分组'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('peer-group-name-field')),
      '朋友',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('朋友 (1)'), findsOneWidget);
    await tester.tap(find.byTooltip('管理分组'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除分组'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('陌生人 (1)'), findsOneWidget);
    expect(groups.value.names, isEmpty);
    expect(groups.value.assignments, isEmpty);
  });

  testWidgets('新建群聊会传入群名和选中成员并刷新列表', (tester) async {
    final FakeGroupsSource source = FakeGroupsSource();
    final DeviceRecord member = DeviceRecord(
      peerId: peerOf('01'),
      publicKey: Uint8List(0),
      name: '小明',
      avatarHash: '',
      os: 'windows',
      firstSeen: DateTime.utc(2026),
      lastSeen: DateTime.utc(2026),
      online: true,
      isSelf: false,
      isGuest: false,
      note: '',
    );
    String? name;
    List<PeerId>? invited;
    await tester.pumpWidget(
      wrapWithTheme(
        GroupsPage(
          source: source,
          listMembers: () async => <DeviceRecord>[member],
          createGroup: (String value, List<PeerId> members) async {
            name = value;
            invited = members;
            source.threads.add(groupThread(groupId: 'created', title: value));
            return 'created';
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('create-group')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('group-name-field')),
      '项目讨论',
    );
    await tester.tap(
      find.byKey(ValueKey<String>('group-member-${member.peerId.value}')),
    );
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(name, '项目讨论');
    expect(invited, <PeerId>[member.peerId]);
    expect(find.text('项目讨论'), findsOneWidget);
    expect(find.byType(GroupRowView), findsOneWidget);
  });
}
