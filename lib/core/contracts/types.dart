// SPDX-License-Identifier: GPL-3.0-only

/// 值类型：标识符不做字符串透传，构造即校验。
library;

final RegExp _peerIdPattern = RegExp(r'^p_[a-z0-9]{13}$');
final RegExp _shareIdPattern = RegExp(r'^[A-Za-z0-9_-]{4,64}$');
final RegExp _avatarHashPattern = RegExp(r'^sha256:[0-9a-f]{16,64}$');

/// offer 的来源：节点或网页访客。
enum OfferOrigin { peer, webSession }

/// 设备稳定身份标识，与 IP 解耦。
final class PeerId implements Comparable<PeerId> {
  const PeerId._(this.value);

  /// 解析并校验；不合法直接抛 [FormatException]。
  factory PeerId.parse(String raw) {
    if (!_peerIdPattern.hasMatch(raw)) {
      throw FormatException('非法 PeerId: $raw');
    }
    return PeerId._(raw);
  }

  /// 仅当形如 PeerId 时返回，否则 null。
  static PeerId? tryParse(String raw) =>
      _peerIdPattern.hasMatch(raw) ? PeerId._(raw) : null;

  final String value;

  @override
  String toString() => value;

  @override
  int compareTo(PeerId other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) => other is PeerId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// 分享标识，出现在链接与路径中，必须 URL 安全。
final class ShareId implements Comparable<ShareId> {
  const ShareId._(this.value);

  /// 解析并校验；不合法直接抛 [FormatException]。
  factory ShareId.parse(String raw) {
    if (!_shareIdPattern.hasMatch(raw)) {
      throw FormatException('非法 ShareId: $raw');
    }
    return ShareId._(raw);
  }

  /// 仅当形如 ShareId 时返回，否则 null。
  static ShareId? tryParse(String raw) =>
      _shareIdPattern.hasMatch(raw) ? ShareId._(raw) : null;

  final String value;

  @override
  String toString() => value;

  @override
  int compareTo(ShareId other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) => other is ShareId && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// 头像内容哈希，用于跨端一致的头像寻址与缓存键。
final class AvatarHash {
  const AvatarHash._(this.value);

  /// 解析并校验；不合法直接抛 [FormatException]。
  factory AvatarHash.parse(String raw) {
    if (!_avatarHashPattern.hasMatch(raw)) {
      throw FormatException('非法 AvatarHash: $raw');
    }
    return AvatarHash._(raw);
  }

  /// 仅当形如 AvatarHash 时返回，否则 null。
  static AvatarHash? tryParse(String raw) =>
      _avatarHashPattern.hasMatch(raw) ? AvatarHash._(raw) : null;

  final String value;

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) => other is AvatarHash && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// 混合逻辑时钟：物理毫秒 + 逻辑计数 + 发起者，跨节点可复现排序。
final class Hlc implements Comparable<Hlc> {
  const Hlc({
    required this.millis,
    required this.counter,
    required this.origin,
  });

  /// 从 `ms:counter:origin` 形式解析。
  factory Hlc.parse(String raw) {
    final parts = raw.split(':');
    if (parts.length != 3) {
      throw FormatException('非法 HLC: $raw');
    }
    return Hlc(
      millis: int.parse(parts[0]),
      counter: int.parse(parts[1]),
      origin: parts[2],
    );
  }

  final int millis;
  final int counter;
  final String origin;

  /// 序列化形式 `ms:counter:origin`。
  String encode() => '$millis:$counter:$origin';

  @override
  int compareTo(Hlc other) {
    final byMillis = millis.compareTo(other.millis);
    if (byMillis != 0) return byMillis;
    final byCounter = counter.compareTo(other.counter);
    if (byCounter != 0) return byCounter;
    return origin.compareTo(other.origin);
  }

  @override
  String toString() => encode();

  @override
  bool operator ==(Object other) =>
      other is Hlc &&
      other.millis == millis &&
      other.counter == counter &&
      other.origin == origin;

  @override
  int get hashCode => Object.hash(millis, counter, origin);
}

/// 文件在分享内部的稳定键：桌面为相对路径，安卓为 SAF docId。
final class ItemKey {
  const ItemKey(this.value);

  /// 解析并校验；长度为 0、超过 4096 或含控制字符时抛 [FormatException]。
  factory ItemKey.parse(String raw) {
    if (raw.isEmpty || raw.length > 4096) {
      throw FormatException('非法 ItemKey 长度');
    }
    for (final unit in raw.codeUnits) {
      if (unit < 0x20) {
        throw FormatException('ItemKey 含控制字符');
      }
    }
    return ItemKey(raw);
  }

  final String value;

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) => other is ItemKey && other.value == value;

  @override
  int get hashCode => value.hashCode;
}
