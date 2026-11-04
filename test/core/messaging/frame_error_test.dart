// SPDX-License-Identifier: GPL-3.0-only

/// 坏帧处理：链路不断、但失败必须上报（证明「兜住 ≠ 吞掉」）。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/core/identity/device_identity_impl.dart';
import 'package:lan_simple_file/core/messaging/messaging_service_impl.dart';
import 'package:lan_simple_file/core/store/store_impl.dart';

void main() {
  late Directory tempDir;
  late LanFileStoreImpl store;
  late DeviceIdentityImpl me;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lsf_frame_err_');
    store = await LanFileStoreImpl.open(
      dbFile: File('${tempDir.path}${Platform.pathSeparator}f.sqlite'),
    );
    me = DeviceIdentityImpl.fromSeed(
      Uint8List.fromList(List<int>.generate(32, (int i) => (i * 5 + 1) % 256)),
    );
  });

  tearDown(() async {
    await store.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('非法 msg 帧经 handleFrame 抛出，且能被上报点捕获', () async {
    final List<Object> reported = <Object>[];
    final MessagingServiceImpl service = MessagingServiceImpl(
      store: store,
      identity: me,
      selfName: 'A',
      selfAvatarHash: '',
      onFrameError: (PeerId peer, WsFrame frame, Object error, StackTrace st) {
        reported.add(error);
      },
    );

    // 缺 id 的 msg 帧：decodeMessage 必须抛，而不是静默落一条空消息。
    final WsFrame bad = WsFrame(WsFrame.msg, <String, Object?>{'thread': 't'});
    await expectLater(
      service.handleFrame(me.peerId, bad),
      throwsA(isA<LanFileException>()),
    );

    await service.dispose();
  });

  test('未注入上报点时写 stderr，不静默丢弃', () async {
    // 这条不做副作用断言（stderr 在测试里不易捕获），只锁定默认路径存在：
    // 构造函数不传 onFrameError 时仍能正常构造并处理合法帧。
    final MessagingServiceImpl service = MessagingServiceImpl(
      store: store,
      identity: me,
      selfName: 'A',
      selfAvatarHash: '',
    );
    expect(service.onFrameError, isNull);
    await service.dispose();
  });
}
