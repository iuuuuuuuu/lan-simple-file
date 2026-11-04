// SPDX-License-Identifier: GPL-3.0-only

/// 共享模块测试共用的真实夹具。
///
/// 刻意不用 mock 顶替存储层与文件系统：
/// - 存储是真实 sqlite 文件（LanFileStoreImpl.open 落在临时目录里）；
/// - 文件是真实临时目录里的真实文件；
/// - 身份是真实 Ed25519（DeviceIdentityImpl.fromSeed，固定种子可复现）。
///
/// 唯一被替换的是 PeerOnlineProbe —— 那是发现层的窄接口，
/// 真跑需要 UDP 广播，属于另一个模块的验证范围。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:lan_simple_file/core/contracts/identity.dart';
import 'package:lan_simple_file/core/contracts/types.dart';
import 'package:lan_simple_file/core/files/local_ref_factory.dart';
import 'package:lan_simple_file/core/identity/capability_codec_impl.dart';
import 'package:lan_simple_file/core/identity/device_identity_impl.dart';
import 'package:lan_simple_file/core/identity/token_revocation_store.dart';
import 'package:lan_simple_file/core/shares/share_service_impl.dart';
import 'package:lan_simple_file/core/store/store_impl.dart';
import 'package:path/path.dart' as p;

/// 夹具统一的固定基准时间：让 codec 的时间窗判定可复现。
final DateTime kFixtureNow = DateTime.utc(2026, 6, 1);

/// 由填充值造一个可复现的 32 字节种子。
Uint8List seedOf(int fill) =>
    Uint8List.fromList(List<int>.generate(32, (int i) => (fill + i) & 0xff));

/// 内存版公钥查找表：让 codec 能离线验签。
final class MapKeyLookup implements PublicKeyLookup {
  MapKeyLookup();

  final Map<String, Uint8List> _keys = <String, Uint8List>{};

  /// 登记某人的公钥。
  void register(PeerId peerId, Uint8List publicKey) {
    _keys[peerId.value] = Uint8List.fromList(publicKey);
  }

  @override
  Future<Uint8List?> findPublicKey(PeerId peerId) async {
    final Uint8List? stored = _keys[peerId.value];
    return stored == null ? null : Uint8List.fromList(stored);
  }
}

/// 一套完整夹具：真实库 + 真实身份 + 真实 codec + 真实临时目录。
final class SharesFixture {
  SharesFixture._({
    required this.sandbox,
    required this.store,
    required this.identity,
    required this.codec,
    required this.probe,
    required this.otherIdentity,
    required this.otherCodec,
  });

  /// 建夹具；clock 固定后所有时间戳可断言。
  static Future<SharesFixture> create({
    DateTime Function()? clock,
    Set<PeerId>? online,
    Map<PeerId, DateTime>? lastSeen,
  }) async {
    final Directory sandbox = Directory.systemTemp.createTempSync('lsf_shares_');
    final File dbFile = File(p.join(sandbox.path, 'shares.db'));
    final LanFileStoreImpl store = await LanFileStoreImpl.open(dbFile: dbFile);

    final DeviceIdentityImpl identity = DeviceIdentityImpl.fromSeed(seedOf(0));
    final DeviceIdentityImpl other = DeviceIdentityImpl.fromSeed(seedOf(64));
    final MapKeyLookup keys = MapKeyLookup()
      ..register(identity.peerId, identity.publicKey)
      ..register(other.peerId, other.publicKey);

    final CapabilityCodecImpl codec = CapabilityCodecImpl(
      issuer: identity,
      revoked: TokenRevocationStore(),
      keys: keys,
      clock: clock ?? (() => kFixtureNow),
    );
    // 验签方也用同一个固定时钟，避免「签发时 2026-06，验签时真实 2026-11」变过期。
    final CapabilityCodecImpl otherCodec = CapabilityCodecImpl(
      issuer: other,
      revoked: TokenRevocationStore(),
      keys: keys,
      clock: clock ?? (() => kFixtureNow),
    );

    return SharesFixture._(
      sandbox: sandbox,
      store: store,
      identity: identity,
      codec: codec,
      probe: FixedOnlineProbe(
        online: online ?? <PeerId>{identity.peerId},
        lastSeen: lastSeen,
      ),
      otherIdentity: other,
      otherCodec: otherCodec,
    );
  }

  /// 临时目录根。
  final Directory sandbox;

  /// 真实落盘的库。
  final LanFileStoreImpl store;

  /// 本机身份。
  final DeviceIdentityImpl identity;

  /// 本机签发的 codec。
  final CapabilityCodecImpl codec;

  /// 可控的在线探测。
  final FixedOnlineProbe probe;

  /// 第三方身份（扮演「别人」）。
  final DeviceIdentityImpl otherIdentity;

  /// 第三方 codec。
  final CapabilityCodecImpl otherCodec;

  /// 建一个分享服务实例。
  ShareServiceImpl service({
    DateTime Function()? clock,
    String Function()? idGenerator,
    String Function()? tokenIdGenerator,
  }) {
    return ShareServiceImpl(
      store: store,
      identity: identity,
      codec: codec,
      localFactory: const LocalRefFactory(),
      probe: probe,
      clock: clock,
      idGenerator: idGenerator,
      tokenIdGenerator: tokenIdGenerator,
    );
  }

  /// 在临时目录里建一棵可控的目录树，返回根目录。
  ///
  /// 结构：根下 filesPerDir 个文件 + 一个子目录，递归到 depth 层。
  Directory makeTree(String name, {int filesPerDir = 3, int depth = 2}) {
    final Directory root = Directory(p.join(sandbox.path, name))
      ..createSync(recursive: true);
    void fill(Directory dir, int level) {
      for (var i = 0; i < filesPerDir; i++) {
        File(p.join(dir.path, 'f${level}_$i.txt'))
            .writeAsStringSync('content-$level-$i');
      }
      if (level < depth) {
        final Directory child = Directory(p.join(dir.path, 'd$level'))
          ..createSync();
        fill(child, level + 1);
      }
    }

    fill(root, 0);
    return root;
  }


  /// 关库并清目录。
  Future<void> dispose() async {
    await store.close();
    if (sandbox.existsSync()) {
      sandbox.deleteSync(recursive: true);
    }
  }
}