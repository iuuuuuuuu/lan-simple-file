// SPDX-License-Identifier: GPL-3.0-only
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/app/widgets/identicon.dart';

Widget wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets(
    'avatar loads a PNG at stable dimensions and follows seed changes',
    (tester) async {
      await tester.pumpWidget(wrap(const Identicon(peerId: 'first', size: 48)));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(Identicon)), const Size(48, 48));
      final first =
          tester.widget<Image>(find.byType(Image)).image as MemoryImage;
      expect(first.bytes, orderedEquals(await buildIdenticonPng('first')));
      await tester.pumpWidget(
        wrap(const Identicon(peerId: 'second', size: 48)),
      );
      await tester.pumpAndSettle();
      final second =
          tester.widget<Image>(find.byType(Image)).image as MemoryImage;
      expect(second.bytes, orderedEquals(await buildIdenticonPng('second')));
      expect(second.bytes, isNot(orderedEquals(first.bytes)));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'custom avatar uses its bytes; empty and invalid bytes fall back',
    (tester) async {
      final png = await buildIdenticonPng('custom');
      await tester.pumpWidget(
        wrap(PeerAvatar(peerId: 'peer', avatarBytes: png)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Identicon), findsNothing);
      final displayed =
          tester.widget<Image>(find.byType(Image)).image as MemoryImage;
      expect(displayed.bytes, orderedEquals(png));
      for (final bytes in [
        Uint8List(0),
        Uint8List.fromList([1, 2, 3]),
      ]) {
        await tester.pumpWidget(
          wrap(PeerAvatar(peerId: 'peer', avatarBytes: bytes)),
        );
        await tester.pumpAndSettle();
        expect(find.byType(Identicon), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
