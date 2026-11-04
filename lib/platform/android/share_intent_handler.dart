// SPDX-License-Identifier: GPL-3.0-only

/// ACTION_SEND / ACTION_SEND_MULTIPLE 的接收入口。
///
/// 产品语义（docs/plan.md M7）：从相册或文件管理器「分享到本 App」后**直接建 share**，
/// 不经二次确认页。安卓只有手动选择文件这一个共享入口，没有拖拽。
///
/// 本文件只做两件可测的事：
/// 1. 把平台推来的 raw intent 参数解析成强类型的 SharedPayload（含拒绝理由）；
/// 2. 把 payload 映射成建 share 所需的请求参数，交给上层去调 ShareService。
/// 真正的 ShareService 装配在 assembly.dart，按任务约束不在本任务内接线。
library;

import 'package:flutter/services.dart';

import '../../core/contracts/contracts.dart';

/// 分享接收通道名，与 Kotlin 侧 kShareIntentChannelName 必须一致。
const String kShareIntentChannelName = 'lan.simple.file/share-intent';

/// 单次分享最多接收的条目数；超出直接拒绝，避免一次导入上千个文件卡死。
const int kMaxSharedItems = 100;

/// ACTION_SEND / ACTION_SEND_MULTIPLE 的两种来源。
enum SharedIntentKind {
  /// 单文件：android.intent.action.SEND。
  single,

  /// 多文件：android.intent.action.SEND_MULTIPLE。
  multiple,
}

/// 一条被分享进来的条目。
final class SharedPayloadItem {
  const SharedPayloadItem({required this.uri, this.mime});

  /// 平台给的内容 URI（content:// 或 file://）。
  final String uri;

  /// MIME；未知为 null。
  final String? mime;

  /// 是否是可用的 URI（content:// 与 file:// 都接受）。
  bool get isUsableScheme =>
      uri.startsWith('content://') || uri.startsWith('file://');

  /// SAF 树授权只需要 content://；file:// 在 Android 7+ 会触发 FileUriExposedException。
  bool get isContentUri => uri.startsWith('content://');

  @override
  String toString() => 'SharedPayloadItem($uri, $mime)';
}

/// 解析后的分享载荷。
final class SharedPayload {
  const SharedPayload({
    required this.kind,
    required this.items,
    this.subject,
  });

  final SharedIntentKind kind;
  final List<SharedPayloadItem> items;

  /// 分享时附带的标题/说明（可选）。
  final String? subject;

  bool get isEmpty => items.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'subject': subject,
    'items': <Map<String, Object?>>[
      for (final SharedPayloadItem item in items)
        <String, Object?>{'uri': item.uri, 'mime': item.mime},
    ],
  };

  @override
  String toString() =>
      'SharedPayload(${kind.name}, ${items.length} items)';
}

/// 拒绝分享的判定。
enum SharedRejectReason {
  /// 没有携带任何条目。
  empty,

  /// URI 既不是 content:// 也不是 file://。
  badScheme,

  /// 全是 file:// —— Android 7+ 不允许跨进程暴露 file URI。
  plainFileUri,

  /// 超过 kMaxSharedItems。
  tooManyItems,

  /// intent action 不认识。
  unknownAction;

  /// 给用户看的原因；不得为空串。
  String get userMessage => switch (this) {
    SharedRejectReason.empty => '这次分享没有带文件，已忽略',
    SharedRejectReason.badScheme => '分享进来的地址不是可读的内容地址，已忽略',
    SharedRejectReason.plainFileUri =>
      '对方发来的是裸 file:// 地址，安卓 7 以上不允许读取。请在文件管理器里重新选择',
    SharedRejectReason.tooManyItems =>
      '一次最多分享 $kMaxSharedItems 个文件，请分批进行',
    SharedRejectReason.unknownAction => '不支持的分享方式，已忽略',
  };
}

/// 解析结果：要么成功，要么带可读理由被拒。
final class SharedIntentResult {
  const SharedIntentResult.accepted(this.payload) : rejectReason = null;

  const SharedIntentResult.rejected(SharedRejectReason this.rejectReason)
    : payload = null;

  final SharedPayload? payload;
  final SharedRejectReason? rejectReason;

  bool get isAccepted => payload != null;

  /// 给人看的结论；成功时说明接收了什么。
  String get userMessage {
    final SharedRejectReason? reason = rejectReason;
    if (reason != null) {
      return reason.userMessage;
    }
    final SharedPayload? accepted = payload;
    if (accepted == null) {
      return '没有可接收的内容';
    }
    return accepted.kind == SharedIntentKind.single
        ? '接收 1 个文件，已准备共享'
        : '接收 ${accepted.items.length} 个文件，已准备共享';
  }
}

/// 把平台推来的原始 map 解析成 SharedIntentResult。
///
/// 输入形状（Kotlin 侧构造）：
///   action: 'android.intent.action.SEND' 或 '...SEND_MULTIPLE'
///   subject: String?
///   items: [ { uri: String, mime: String? }, ... ]
///
/// 任何不合法的输入都走 rejected，不抛异常——这是外部输入，抛错只会炸 UI。
SharedIntentResult parseShareIntent(Map<String, Object?> raw) {
  final Object? action = raw['action'];
  final SharedIntentKind kind;
  if (action == 'android.intent.action.SEND') {
    kind = SharedIntentKind.single;
  } else if (action == 'android.intent.action.SEND_MULTIPLE') {
    kind = SharedIntentKind.multiple;
  } else {
    return const SharedIntentResult.rejected(
      SharedRejectReason.unknownAction,
    );
  }

  final Object? rawItems = raw['items'];
  if (rawItems is! List || rawItems.isEmpty) {
    return const SharedIntentResult.rejected(SharedRejectReason.empty);
  }
  if (rawItems.length > kMaxSharedItems) {
    return const SharedIntentResult.rejected(SharedRejectReason.tooManyItems);
  }

  final List<SharedPayloadItem> items = <SharedPayloadItem>[];
  for (final Object? entry in rawItems) {
    if (entry is! Map) {
      return const SharedIntentResult.rejected(SharedRejectReason.badScheme);
    }
    final Object? uri = entry['uri'];
    if (uri is! String || uri.isEmpty) {
      return const SharedIntentResult.rejected(SharedRejectReason.badScheme);
    }
    final Object? mime = entry['mime'];
    items.add(
      SharedPayloadItem(uri: uri, mime: mime is String ? mime : null),
    );
  }

  if (items.every((SharedPayloadItem item) => !item.isUsableScheme)) {
    return const SharedIntentResult.rejected(SharedRejectReason.badScheme);
  }
  if (items.every((SharedPayloadItem item) => !item.isContentUri)) {
    return const SharedIntentResult.rejected(SharedRejectReason.plainFileUri);
  }

  final Object? subject = raw['subject'];
  return SharedIntentResult.accepted(
    SharedPayload(
      kind: kind,
      items: items
          .where((SharedPayloadItem item) => item.isContentUri)
          .toList(),
      subject: subject is String && subject.isNotEmpty ? subject : null,
    ),
  );
}

/// 把分享载荷映射成建 share 的请求。
///
/// 每个被分享的 content URI 都直接成为一个 mode=lan、rootKind=safTree 的分享根：
/// 安卓侧没有「多文件打包成一个目录」的 SAF 能力，逐个建是唯一诚实的做法。
/// 目录 URI 由 provider 自己识别（DocumentFile.isDirectory），此处不猜。
List<CreateShareRequest> buildShareRequests(
  SharedPayload payload, {
  required String displayNamePrefix,
}) {
  if (payload.isEmpty) {
    throw const LanFileException(
      LanFileErrorCode.invalidArgument,
      '分享载荷为空，不能建 share',
    );
  }
  return <CreateShareRequest>[
    for (final SharedPayloadItem item in payload.items)
      _requestFor(item, displayNamePrefix),
  ];
}

CreateShareRequest _requestFor(
  SharedPayloadItem item,
  String displayNamePrefix,
) {
  final String name = displayNameOfUri(item.uri, fallback: item.mime);
  return CreateShareRequest(
    rootKind: ShareRootKind.safTree,
    rootUri: item.uri,
    displayName: displayNamePrefix.isEmpty
        ? name
        : '$displayNamePrefix · $name',
    mode: ShareMode.lan,
    kind: 'file',
  );
}

/// 从 URI 末段取一个像样的展示名。
///
/// content:// URI 的末段常是 msf%3A12345 这类不透明的 id，
/// 此时退回 fallback 或「未命名文件」，绝不把 URL 编码串直接甩给用户。
String displayNameOfUri(String uri, {String? fallback}) {
  final List<String> segments;
  try {
    segments = Uri.parse(uri).pathSegments;
  } on FormatException {
    return _cleanFallback(fallback);
  }
  final String tail = segments.isEmpty ? '' : segments.last;
  String decoded;
  try {
    decoded = Uri.decodeComponent(tail);
  } on ArgumentError {
    return _cleanFallback(fallback);
  } on FormatException {
    return _cleanFallback(fallback);
  }
  if (decoded.isEmpty || decoded.contains(':') || decoded.contains('/')) {
    return _cleanFallback(fallback);
  }
  return decoded;
}

String _cleanFallback(String? fallback) {
  if (fallback == null || fallback.isEmpty) {
    return '未命名文件';
  }
  // MIME 里的斜杠不能出现在展示名里。
  return fallback.replaceAll('/', '_');
}

/// 分享接收的平台桥。
final class ShareIntentBridge {
  // 私有字段与公开命名参数同名冲突，无法用 initializing formal。
  // ignore: prefer_initializing_formals
  const ShareIntentBridge({MethodChannel? channel}) : _channel = channel;

  final MethodChannel? _channel;

  MethodChannel get _resolved =>
      _channel ?? const MethodChannel(kShareIntentChannelName);

  /// 取出「冷启动那一刻带进来的 intent」，取完即清（只消费一次）。
  ///
  /// 返回 null 表示没有待处理的分享。
  Future<SharedIntentResult?> takePending() async {
    try {
      final Object? value = await _resolved.invokeMethod<Object?>(
        'takePendingIntent',
      );
      if (value == null) {
        return null;
      }
      if (value is! Map) {
        return const SharedIntentResult.rejected(
          SharedRejectReason.unknownAction,
        );
      }
      return parseShareIntent(_stringKeyed(value));
    } on MissingPluginException {
      // 桌面/网页环境没有这个通道，等价于「没有待处理分享」。
      return null;
    } on PlatformException catch (error) {
      throw ShareIntentFailure(
        '${error.code}: ${error.message ?? '(无消息)'}',
        cause: error,
      );
    }
  }

  /// 注册「新的分享到来」回调。
  void listen(void Function(SharedIntentResult result) onResult) {
    _resolved.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'onShareIntent') {
        return null;
      }
      final Object? arguments = call.arguments;
      if (arguments is! Map) {
        onResult(
          const SharedIntentResult.rejected(
            SharedRejectReason.unknownAction,
          ),
        );
        return null;
      }
      onResult(parseShareIntent(_stringKeyed(arguments)));
      return null;
    });
  }

  /// 停止接收回调。
  void stopListening() {
    _resolved.setMethodCallHandler(null);
  }

  static Map<String, Object?> _stringKeyed(Map<Object?, Object?> raw) {
    return <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in raw.entries)
        if (entry.key is String) entry.key! as String: entry.value,
    };
  }
}

/// 分享接收失败。
final class ShareIntentFailure implements Exception {
  const ShareIntentFailure(this.message, {this.cause});

  final String message;
  final Object? cause;

  String get userMessage => '读取分享内容失败：$message';

  @override
  String toString() => 'ShareIntentFailure: $message';
}
