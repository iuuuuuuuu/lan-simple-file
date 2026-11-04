// SPDX-License-Identifier: GPL-3.0-only

/// 分享链接解析：`lsf://open?share=<id>&k=<token>` -> [ShareLink]。
///
/// 链接是**唯一**的对外入口描述：它只带分享标识与能力凭证，
/// 一个字节的网络地址都不带（见 host-independent-capability-addressing 笔记）。
///
/// 解析失败一律抛 [LanFileException]（码 invalidArgument），
/// 不抛裸 FormatException —— 调用方（UI、扫码器）只需要一种错误类型。
library;

import 'package:lan_simple_file/core/contracts/contracts.dart';

import '../shares/link_builder.dart';

/// 一条解析后的分享链接。
final class ShareLink {
  const ShareLink({required this.shareId, this.token});

  /// 分享标识。
  final ShareId shareId;

  /// 能力凭证；lan 模式的链接可以没有。
  final String? token;

  /// 是否携带凭证。
  bool get hasToken => token != null && token!.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is ShareLink && other.shareId == shareId && other.token == token;

  @override
  int get hashCode => Object.hash(shareId, token);

  @override
  String toString() => 'ShareLink(${shareId.value}, token=$hasToken)';
}

/// 链接解析器。
///
/// 与 [LinkBuilder] 共用同一套 scheme/host/参数名常量，
/// 避免「构造用一套、解析用另一套」造成的静默失配。
final class LinkParser {
  const LinkParser();

  /// 解析链接字符串。
  ///
  /// 接受：
  /// - `lsf://open?share=ID`
  /// - `lsf://open?share=ID&k=TOKEN`
  ///
  /// 拒绝（全部抛 invalidArgument）：
  /// - 空串、非 URI、scheme 不是 lsf、host 不是 open
  /// - 缺 share 参数、shareId 格式非法
  /// - 链接里含网络地址成分（ip/host/port 参数、192.168 之类字面量、显式端口）
  ShareLink parse(String raw) {
    if (raw.trim().isEmpty) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        '分享链接为空',
      );
    }
    final Uri uri;
    try {
      uri = Uri.parse(raw);
    } on FormatException catch (error) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '不是合法 URI：$raw',
        cause: error,
      );
    }
    if (uri.scheme != kShareLinkScheme) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '不是本应用的分享链接（scheme 应为 $kShareLinkScheme）：$raw',
      );
    }
    if (uri.host != kShareLinkHost) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '不是本应用的分享链接（host 应为 $kShareLinkHost）：$raw',
      );
    }
    // 链接一旦带端口或网络定位参数，就已经不是「与拓扑解耦」的链接了。
    if (uri.hasPort) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '分享链接不得携带端口：$raw',
      );
    }
    for (final String key in uri.queryParameters.keys) {
      final String lower = key.toLowerCase();
      if (lower == 'ip' || lower == 'host' || lower == 'port') {
        throw LanFileException(
          LanFileErrorCode.invalidArgument,
          '分享链接不得携带网络定位参数（$key）：$raw',
        );
      }
    }

    final String? rawShare = uri.queryParameters[kShareLinkShareParam];
    if (rawShare == null || rawShare.isEmpty) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '分享链接缺少 share 参数：$raw',
      );
    }
    final ShareId? shareId = ShareId.tryParse(rawShare);
    if (shareId == null) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '分享链接里的 shareId 非法：$rawShare',
      );
    }

    final String? rawToken = uri.queryParameters[kShareLinkTokenParam];
    final String? token = (rawToken == null || rawToken.isEmpty) ? null : rawToken;
    return ShareLink(shareId: shareId, token: token);
  }

  /// 尝试解析；非法时返回 null（扫码预览这类「不该炸 UI」的场景用）。
  ShareLink? tryParse(String raw) {
    try {
      return parse(raw);
    } on LanFileException {
      return null;
    }
  }
}
