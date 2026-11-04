// SPDX-License-Identifier: GPL-3.0-only

/// ACTION_SEND 接收入口的解析测试。
///
/// **诚实边界**：这里喂的是 Kotlin 侧承诺的 map 形状，用 mock 通道与纯函数验证。
/// **没有从真实系统分享面板发起过分享**——真机才能验证 intent 的真实形状。
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/core/contracts/contracts.dart';
import 'package:lan_simple_file/platform/android/share_intent_handler.dart';

final class FakeShareChannel {
  final List<MethodCall> calls = <MethodCall>[];
  Object? Function()? pendingHandler;
  void Function(MethodCall call)? onCall;

  Future<Object?> dispatch(MethodCall call) async {
    calls.add(call);
    if (call.method == 'takePendingIntent') {
      final Object? Function()? handler = pendingHandler;
      return handler == null ? null : handler();
    }
    return null;
  }
}

void installShareChannel(FakeShareChannel fake) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel(kShareIntentChannelName),
        fake.dispatch,
      );
}

Map<String, Object?> singleIntent({
  String uri = 'content://com.android.providers.media/documents/image/1234',
  String? mime = 'image/jpeg',
}) => <String, Object?>{
  'action': 'android.intent.action.SEND',
  'subject': '来自相册',
  'items': <Object?>[
    <String, Object?>{'uri': uri, 'mime': mime},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('单文件分享解析', () {
    test('SEND 的一个 content URI 被接受，带上 mime 与 subject', () {
      final SharedIntentResult result = parseShareIntent(singleIntent());
      expect(result.isAccepted, isTrue);
      final SharedPayload payload = result.payload!;
      expect(payload.kind, SharedIntentKind.single);
      expect(payload.items.length, 1);
      expect(payload.items.single.isContentUri, isTrue);
      expect(payload.items.single.mime, 'image/jpeg');
      expect(payload.subject, '来自相册');
      expect(result.userMessage, contains('1 个文件'));
    });

    test('空 subject 归一为 null，不留下空串', () {
      final SharedIntentResult result = parseShareIntent(<String, Object?>{
        ...singleIntent(),
        'subject': '',
      });
      expect(result.payload!.subject, isNull);
    });
  });

  group('多文件分享解析', () {
    test('SEND_MULTIPLE 的多个 URI 全部保留', () {
      final SharedIntentResult result = parseShareIntent(<String, Object?>{
        'action': 'android.intent.action.SEND_MULTIPLE',
        'items': <Object?>[
          <String, Object?>{
            'uri': 'content://media/1',
            'mime': 'image/jpeg',
          },
          <String, Object?>{
            'uri': 'content://media/2',
            'mime': 'image/png',
          },
          <String, Object?>{
            'uri': 'content://media/3',
            'mime': null,
          },
        ],
      });
      expect(result.isAccepted, isTrue);
      expect(result.payload!.kind, SharedIntentKind.multiple);
      expect(result.payload!.items.length, 3);
      expect(result.payload!.items.last.mime, isNull);
      expect(result.userMessage, contains('3 个文件'));
    });

    test('混合 content:// 与 file:// 时只保留 content://', () {
      final SharedIntentResult result = parseShareIntent(<String, Object?>{
        'action': 'android.intent.action.SEND_MULTIPLE',
        'items': <Object?>[
          <String, Object?>{'uri': 'content://media/1', 'mime': null},
          <String, Object?>{'uri': 'file:///sdcard/x.jpg', 'mime': null},
        ],
      });
      expect(result.isAccepted, isTrue);
      expect(result.payload!.items.length, 1);
      expect(result.payload!.items.single.uri, 'content://media/1');
    });
  });

  group('拒绝路径', () {
    test('未知 action 被拒，理由可读', () {
      final SharedIntentResult result = parseShareIntent(<String, Object?>{
        'action': 'android.intent.action.VIEW',
        'items': <Object?>[
          <String, Object?>{'uri': 'content://x', 'mime': null},
        ],
      });
      expect(result.isAccepted, isFalse);
      expect(result.rejectReason, SharedRejectReason.unknownAction);
      expect(result.userMessage, isNotEmpty);
    });

    test('没有条目时被拒', () {
      final SharedIntentResult result = parseShareIntent(<String, Object?>{
        'action': 'android.intent.action.SEND',
        'items': <Object?>[],
      });
      expect(result.rejectReason, SharedRejectReason.empty);
    });

    test('items 不是 List 时被拒，不抛异常', () {
      final SharedIntentResult result = parseShareIntent(<String, Object?>{
        'action': 'android.intent.action.SEND',
        'items': 'oops',
      });
      expect(result.isAccepted, isFalse);
    });

    test('纯 file:// 被拒（Android 7+ 不许跨进程暴露 file URI）', () {
      final SharedIntentResult result = parseShareIntent(<String, Object?>{
        'action': 'android.intent.action.SEND',
        'items': <Object?>[
          <String, Object?>{'uri': 'file:///sdcard/a.jpg', 'mime': 'image/jpeg'},
        ],
      });
      expect(result.rejectReason, SharedRejectReason.plainFileUri);
      expect(result.userMessage, contains('file://'));
    });

    test('非 content/file 协议被拒', () {
      final SharedIntentResult result = parseShareIntent(<String, Object?>{
        'action': 'android.intent.action.SEND',
        'items': <Object?>[
          <String, Object?>{'uri': 'javascript:alert(1)', 'mime': null},
        ],
      });
      expect(result.rejectReason, SharedRejectReason.badScheme);
      expect(result.userMessage, isNotEmpty);
    });

    test('条目超过上限时被拒，提示分批', () {
      final SharedIntentResult result = parseShareIntent(<String, Object?>{
        'action': 'android.intent.action.SEND_MULTIPLE',
        'items': <Object?>[
          for (int i = 0; i <= kMaxSharedItems; i++)
            <String, Object?>{'uri': 'content://media/$i', 'mime': null},
        ],
      });
      expect(result.rejectReason, SharedRejectReason.tooManyItems);
      expect(result.userMessage, contains('分批'));
    });

    test('uri 为空串时被拒', () {
      final SharedIntentResult result = parseShareIntent(<String, Object?>{
        'action': 'android.intent.action.SEND',
        'items': <Object?>[
          <String, Object?>{'uri': '', 'mime': null},
        ],
      });
      expect(result.rejectReason, SharedRejectReason.badScheme);
    });
  });

  group('建 share 请求映射', () {
    test('每个 content URI 映射成一个 safTree + lan 的请求', () {
      final SharedIntentResult parsed = parseShareIntent(<String, Object?>{
        'action': 'android.intent.action.SEND_MULTIPLE',
        'items': <Object?>[
          <String, Object?>{'uri': 'content://media/a.jpg', 'mime': 'image/jpeg'},
          <String, Object?>{'uri': 'content://media/b.pdf', 'mime': 'application/pdf'},
        ],
      });
      final List<CreateShareRequest> requests = buildShareRequests(
        parsed.payload!,
        displayNamePrefix: 'YG 的手机',
      );
      expect(requests.length, 2);
      for (final CreateShareRequest request in requests) {
        expect(request.rootKind, ShareRootKind.safTree);
        expect(request.mode, ShareMode.lan);
        expect(request.kind, 'file');
        expect(request.displayName, startsWith('YG 的手机 · '));
      }
      expect(requests[0].rootUri, 'content://media/a.jpg');
      expect(requests[0].displayName, contains('a.jpg'));
    });

    test('空载荷建 share 抛 invalidArgument，不产出空请求', () {
      const SharedPayload empty = SharedPayload(
        kind: SharedIntentKind.single,
        items: <SharedPayloadItem>[],
      );
      expect(
        () => buildShareRequests(empty, displayNamePrefix: 'x'),
        throwsA(
          isA<LanFileException>().having(
            (LanFileException e) => e.code,
            'code',
            LanFileErrorCode.invalidArgument,
          ),
        ),
      );
    });
  });

  group('展示名推导', () {
    test('取 URI 末段并解码', () {
      expect(
        displayNameOfUri('content://media/my%20photo.jpg'),
        'my photo.jpg',
      );
    });

    test('不透明 id（含冒号）时退回 fallback，不把 id 甩给用户', () {
      expect(
        displayNameOfUri(
          'content://com.android.providers.media.documents/document/msf%3A1234',
          fallback: 'image_jpeg',
        ),
        'image_jpeg',
      );
    });

    test('完全拿不到名字时给「未命名文件」', () {
      expect(displayNameOfUri('content://'), '未命名文件');
    });
  });

  group('通道桥（mock，非真机）', () {
    late FakeShareChannel fake;
    late ShareIntentBridge bridge;

    setUp(() {
      fake = FakeShareChannel();
      installShareChannel(fake);
      bridge = const ShareIntentBridge();
    });

    test('takePending 取到内容并解析', () async {
      fake.pendingHandler = () => singleIntent();
      final SharedIntentResult? result = await bridge.takePending();
      expect(result, isNotNull);
      expect(result!.isAccepted, isTrue);
      expect(fake.calls.single.method, 'takePendingIntent');
    });

    test('没有待处理分享时返回 null', () async {
      fake.pendingHandler = () => null;
      expect(await bridge.takePending(), isNull);
    });

    test('通道缺失时返回 null（桌面环境等价于没有分享）', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(kShareIntentChannelName),
            null,
          );
      expect(await bridge.takePending(), isNull);
      installShareChannel(fake);
    });

    test('平台抛错时上抛 ShareIntentFailure', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(kShareIntentChannelName),
            (MethodCall call) async {
              throw PlatformException(code: 'boom', message: 'nope');
            },
          );
      await expectLater(
        bridge.takePending(),
        throwsA(
          isA<ShareIntentFailure>().having(
            (ShareIntentFailure e) => e.message,
            'message',
            contains('boom'),
          ),
        ),
      );
      installShareChannel(fake);
    });
  });
}
