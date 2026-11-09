// SPDX-License-Identifier: GPL-3.0-only

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/shares/share_organization.dart';
import 'package:lan_simple_file/core/store/store_impl.dart';

ShareRecord item(String id, {String kind = 'folder'}) => ShareRecord(
  id: ShareId.parse(id),
  ownerPeerId: PeerId.parse('p_aaaaaaaaaaaaa'),
  rootKind: 'localPath',
  rootUri: '/files/$id',
  kind: kind,
  displayName: id,
  createdAt: DateTime.utc(2026),
  mode: ShareMode.people,
  enabled: true,
  missing: false,
  isEphemeral: false,
  groupId: 'private-access-group',
);

void main() {
  final file = item('a-file', kind: 'file');
  final folder = item('z-folder');
  test('default folders first, manual order is exact and new items append', () {
    expect(const ShareOrganization().arrange([file, folder]), [folder, file]);
    expect(
      ShareOrganization(order: [file.id.value, folder.id.value])
          .arrange([folder, item('new-folder'), file]),
      [
        file,
        folder,
        isA<ShareRecord>().having((s) => s.id.value, 'id', 'new-folder'),
      ],
    );
  });

  test(
    'group order and share order are independent of names and permissions',
    () {
      final layout = ShareOrganization(
        names: {'work': 'Work', 'photos': 'Photos'},
        assignments: {file.id.value: 'work', folder.id.value: 'photos'},
        groupOrder: ['photos', 'work', ''],
        order: [file.id.value, folder.id.value],
      );
      expect(layout.arrange([file, folder]), [folder, file]);
      expect(layout.arrange([file, folder], group: 'work'), [file]);
      expect(
        layout
            .copyWith(names: {'work': 'Renamed', 'photos': 'Photos'})
            .groupOf(file.id.value),
        'work',
      );
      expect(file.mode, ShareMode.people);
      expect(file.groupId, 'private-access-group');
      expect(
        layout.move([file.id.value], 'photos').arrange([
          folder,
          file,
        ], group: 'photos'),
        [file, folder],
      );
    },
  );

  test('deleting a group keeps shares and their manual order', () {
    final layout = ShareOrganization(
      names: {'work': 'Work'},
      assignments: {file.id.value: 'work'},
      groupOrder: ['work', ''],
      order: [file.id.value, folder.id.value],
    ).removeGroup('work');
    expect(layout.names, isEmpty);
    expect(layout.assignments, isEmpty);
    expect(layout.arrange([folder, file]), [file, folder]);
    expect(
      () => layout.move([file.id.value], 'missing'),
      throwsFormatException,
    );
  });

  test(
    'placing a searched share preserves hidden items and joins target group',
    () {
      final hidden = item('hidden');
      final next =
          const ShareOrganization(
            names: {'work': 'Work'},
            assignments: {'z-folder': 'work', 'hidden': 'work'},
            order: ['a-file', 'hidden', 'z-folder'],
          ).place(
            [file, hidden, folder],
            share: file.id.value,
            target: folder.id.value,
            after: true,
          );
      expect(next.groupOf(file.id.value), 'work');
      expect(next.arrange([file, folder, hidden]), [hidden, folder, file]);
      expect(file.mode, ShareMode.people);
      expect(file.groupId, 'private-access-group');
      expect(
        next.place(
          [file],
          share: file.id.value,
          target: 'missing',
          after: false,
        ),
        same(next),
      );
    },
  );

  test(
    'groups, assignments and both orders survive closing and reopening storage',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'share-organization-',
      );
      var store = await LanFileStoreImpl.open(
        dbFile: File('${sandbox.path}/test.sqlite'),
      );
      addTearDown(() async {
        await store.close();
        await sandbox.delete(recursive: true);
      });
      final original = ShareOrganization(
        names: {'work': '工作资料', 'photos': 'Photos'},
        assignments: {file.id.value: 'work', folder.id.value: 'photos'},
        order: [file.id.value, folder.id.value],
        groupOrder: ['work', '', 'photos'],
      );
      await StoreShareOrganizationSource(store).save(original);
      await store.close();
      store = await LanFileStoreImpl.open(
        dbFile: File('${sandbox.path}/test.sqlite'),
      );
      final restored = await StoreShareOrganizationSource(store).load();
      expect(restored.toJson(), original.toJson());
      expect(restored.arrange([folder, file]), [file, folder]);
    },
  );
}
