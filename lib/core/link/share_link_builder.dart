// SPDX-License-Identifier: GPL-3.0-only

/// 分享链接的对外构造门面：把 [LinkBuilder] 的原始能力收成一个入口，
/// 并强制「链接绝不含网络地址」这条硬门禁。
///
/// 与 `lib/core/shares/link_builder.dart` 的关系：
/// - [LinkBuilder] 是底层编码器（已在 M2 交付并有用例）；
/// - 本文件是**对外那一层**，负责：签发凭证、拼链接、过地址门禁、
///   同时产出「微信/短信里可以直接点开」的 http 兜底说明。
///
/// 这里不重复实现编码逻辑，全部委托给 [LinkBuilder]，避免两套规则漂移。
library;

import 'package:lan_simple_file/core/contracts/contracts.dart';

import '../shares/link_builder.dart';
import 'link_parser.dart';

/// 链接生成结果：既含 lsf:// 深链，也含「没有网络地址」的自证。
final class ShareLinkResult {
  const ShareLinkResult({
    required this.uri,
    required this.shareId,
    this.token,
  });

  /// lsf:// 深链。
  final Uri uri;

  final ShareId shareId;

  /// 签发出来的能力凭证；lan 模式可能为空。
  final String? token;

  /// 深链字符串。
  String get text => uri.toString();

  /// 硬门禁：确认链接里没有任何网络地址成分。
  ///
  /// 这是验收里「对 192.168 / 127.0.0.1 / http:// / :47778 逐一断言 false」
  /// 的实现侧对应物——不但测试断言，生产代码每次生成链接都会过一遍。
  void assertNoNetworkAddress() {
    const LinkBuilder().assertNoNetworkAddress(text);
    // 额外补两条本工程特有的：默认 HTTP 端口与组播网段字面量。
    for (final String needle in <String>[
      '192.168.',
      '127.0.0.1',
      'http://',
      '47778',
      '239.255.',
    ]) {
      if (text.contains(needle)) {
        throw LanFileException(
          LanFileErrorCode.invalidArgument,
          '分享链接中不得出现网络地址成分（$needle）：$text',
        );
      }
    }
  }
}

/// 分享链接构造门面。
final class ShareLinkBuilder {
  const ShareLinkBuilder({
    this.builder = const LinkBuilder(),
    this.parser = const LinkParser(),
  });

  /// 底层编码器。
  final LinkBuilder builder;

  /// 反向解析器（自检 round-trip 用）。
  final LinkParser parser;

  /// 只带 shareId 的链接（lan 模式，无需凭证）。
  ShareLinkResult buildPlain(ShareId shareId) {
    final Uri uri = builder.build(shareId: shareId);
    final ShareLinkResult result =
        ShareLinkResult(uri: uri, shareId: shareId);
    result.assertNoNetworkAddress();
    // round-trip 自检：自己生成的东西自己必须能解析回来。
    final ShareLink parsed = parser.parse(uri.toString());
    if (parsed.shareId != shareId) {
      throw LanFileException(
        LanFileErrorCode.internal,
        '链接 round-trip 失败：$uri',
      );
    }
    return result;
  }

  /// 签发凭证并生成链接。
  Future<ShareLinkResult> buildSigned({
    required ShareId shareId,
    required CapabilityCodec codec,
    required PeerId issuer,
    required String tokenId,
    required DateTime now,
    String subject = kAnySubject,
    Set<String> permissions = const <String>{'read'},
    Duration ttl = kShareLinkDefaultTtl,
  }) async {
    final Uri uri = await builder.buildSigned(
      shareId: shareId,
      codec: codec,
      issuer: issuer,
      subject: subject,
      permissions: permissions,
      now: now,
      ttl: ttl,
      tokenId: tokenId,
    );
    final ShareLinkResult result = ShareLinkResult(
      uri: uri,
      shareId: shareId,
      token: builder.parseToken(uri),
    );
    result.assertNoNetworkAddress();
    final ShareLink parsed = parser.parse(uri.toString());
    if (parsed.shareId != shareId || parsed.token != result.token) {
      throw LanFileException(
        LanFileErrorCode.internal,
        '链接 round-trip 失败：$uri',
      );
    }
    return result;
  }

  /// 用同一套规则解析外部传入的链接字符串。
  ShareLink parse(String raw) => parser.parse(raw);
}

/// 「任何持链接者」的 subject 取值；与 CapabilityCodec 的约定一致。
const String kAnySubject = '*';

/// 默认凭证有效期（24 小时），与 LinkBuilder 保持一致。
const Duration kShareLinkDefaultTtl = Duration(hours: 24);