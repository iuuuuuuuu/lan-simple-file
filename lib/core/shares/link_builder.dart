// SPDX-License-Identifier: GPL-3.0-only

/// 分享链接构造器：链接只带 shareId 与能力凭证，绝不含网络地址。
///
/// 这是 host-independent-capability-addressing 决策笔记的落地：
/// 提供者换 IP、换网卡、换端口之后，旧链接必须依然有效，
/// 因此链接里一个字节的 IP / 主机名 / 端口都不能出现。
library;

import '../contracts/errors.dart';
import '../contracts/identity.dart';
import '../contracts/types.dart';

/// 链接的 scheme。
const String kShareLinkScheme = 'lsf';

/// 链接的 host 段；固定为 open，用来区分后续可能的其它入口。
const String kShareLinkHost = 'open';

/// 链接里分享 id 的查询参数名。
const String kShareLinkShareParam = 'share';

/// 链接里能力凭证的查询参数名。
const String kShareLinkTokenParam = 'k';

/// 默认凭证有效期。
const Duration kShareLinkDefaultTtl = Duration(hours: 24);

/// 把 shareId（加可选凭证）编成 lsf://open?share=ID&k=TOKEN。
///
/// 不引入任何网络拓扑信息：没有 IP、没有主机名、没有端口、没有 http 前缀。
final class LinkBuilder {
  const LinkBuilder();

  /// 组装链接。[token] 为空时只留 share 参数（例如 lan 模式不需要凭证）。
  Uri build({required ShareId shareId, String? token}) {
    final Map<String, String> query = <String, String>{
      kShareLinkShareParam: shareId.value,
    };
    if (token != null && token.isNotEmpty) {
      query[kShareLinkTokenParam] = token;
    }
    final Uri uri = Uri(
      scheme: kShareLinkScheme,
      host: kShareLinkHost,
      queryParameters: query,
    );
    assertNoNetworkAddress(uri.toString());
    return uri;
  }

  /// 从链接里取回 shareId；链接不合法抛 LanFileException。
  ShareId parseShareId(Uri link) {
    if (link.scheme != kShareLinkScheme || link.host != kShareLinkHost) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '不是本应用的分享链接：$link',
      );
    }
    final String? raw = link.queryParameters[kShareLinkShareParam];
    if (raw == null || raw.isEmpty) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '分享链接缺少 share 参数：$link',
      );
    }
    try {
      return ShareId.parse(raw);
    } on FormatException catch (e) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '分享链接里的 shareId 非法：$raw',
        cause: e,
      );
    }
  }

  /// 从链接里取回凭证字符串；没有则 null。
  String? parseToken(Uri link) {
    final String? token = link.queryParameters[kShareLinkTokenParam];
    return (token == null || token.isEmpty) ? null : token;
  }

  /// 断言字符串里不含任何网络地址成分。
  ///
  /// 契约硬约束的自检点：构造完链接立刻过一遍，谁哪天往 query 里塞了
  /// ip / port 会在这里当场炸，而不是等上线后才被发现。
  void assertNoNetworkAddress(String text) {
    const List<String> forbidden = <String>[
      'http://',
      'https://',
      '192.168.',
      '127.0.0.1',
      'localhost',
    ];
    for (final String needle in forbidden) {
      if (text.contains(needle)) {
        throw LanFileException(
          LanFileErrorCode.invalidArgument,
          '分享链接中不得出现网络地址成分（$needle）：$text',
        );
      }
    }
    final Uri uri = Uri.parse(text);
    if (uri.hasPort) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '分享链接中不得携带端口：$text',
      );
    }
    for (final String key in uri.queryParameters.keys) {
      final String lower = key.toLowerCase();
      if (lower == 'ip' || lower == 'host' || lower == 'port') {
        throw LanFileException(
          LanFileErrorCode.invalidArgument,
          '分享链接不得携带网络定位参数（$key）：$text',
        );
      }
    }
  }

  /// 用给定 codec 为某个分享签发凭证并返回链接。
  ///
  /// [subject] 为 '*' 表示任何持链接者；[ttl] 是凭证有效期。
  Future<Uri> buildSigned({
    required ShareId shareId,
    required CapabilityCodec codec,
    required PeerId issuer,
    String subject = '*',
    Set<String> permissions = const <String>{'read'},
    required DateTime now,
    Duration ttl = kShareLinkDefaultTtl,
    required String tokenId,
  }) async {
    if (tokenId.isEmpty) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        'tokenId 不能为空',
      );
    }
    final String token = await codec.issue(
      CapabilityGrant(
        shareId: shareId,
        issuer: issuer,
        subject: subject,
        permissions: permissions,
        notBefore: now,
        expiresAt: now.add(ttl),
        tokenId: tokenId,
      ),
    );
    return build(shareId: shareId, token: token);
  }
}
