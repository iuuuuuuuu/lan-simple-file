// SPDX-License-Identifier: GPL-3.0-only

/// 本机设备身份：Ed25519 密钥对的生成、落盘与使用。
///
/// 落盘位置由调用方通过 [DeviceIdentityImpl.loadOrCreate] 的 `dataDir` 注入；
/// 生产代码请用 [DeviceIdentityImpl.loadOrCreateInAppData]，它走
/// `path_provider` 取应用数据目录，不硬编码任何路径。
///
/// 文件 `identity.key` 是 JSON：
///
/// ```json
/// {"v":1,"alg":"ed25519","seed":"<base64url,无填充>","pub":"<base64url,无填充>"}
/// ```
///
/// 只存种子（32 字节），公钥由种子现算并与存储值交叉校验，防止手改文件
/// 让 peerId 悄悄漂移。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

import '../contracts/errors.dart';
import '../contracts/identity.dart';
import '../contracts/types.dart';
import 'ed25519_signer.dart';

/// 身份密钥文件名；相对 [DeviceIdentityImpl.loadOrCreate] 的 `dataDir`。
const String kIdentityFileName = 'identity.key';

/// 身份文件格式版本。
const int kIdentityFileVersion = 1;

/// 首次生成身份时用的互斥锁文件名；相对 [DeviceIdentityImpl.loadOrCreate] 的
/// `dataDir`，用后即删。
const String kIdentityLockFileName = 'identity.lock';

/// 一个可用签名的最小 Ed25519 身份。
final class DeviceIdentityImpl implements DeviceIdentity {
  DeviceIdentityImpl._(Uint8List seed, Uint8List publicKey)
      : _seed = seed,
        _publicKey = publicKey,
        _keyPair = SimpleKeyPairData(
          seed,
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
          type: KeyPairType.ed25519,
        ),
        peerId = derivePeerId(publicKey);

  /// 测试与工具用：由 32 字节种子确定性构造，不触盘。
  ///
  /// 相同种子在任意进程、任意平台产生相同 [peerId] 与相同签名。
  static DeviceIdentityImpl fromSeed(Uint8List seed) {
    final Uint8List publicKey = deriveEd25519PublicKeyFromSeed(seed);
    return DeviceIdentityImpl._(Uint8List.fromList(seed), publicKey);
  }

  /// 从 [dataDir] 读取 `identity.key`；不存在则生成并落盘。
  ///
  /// 并发安全靠 `identity.lock` 的**独占创建**：`File.create(exclusive: true)`
  /// 在操作系统层面是原子的，抢到锁的一方写密钥，抢不到的一方短暂等锁
  /// 释放后回读。抢占失败的一方**绝不**使用自己生成的种子，否则同一台
  /// 设备会出现两个 peerId。
  static Future<DeviceIdentityImpl> loadOrCreate({
    required Directory dataDir,
  }) async {
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }
    final File file = File(
      dataDir.path + Platform.pathSeparator + kIdentityFileName,
    );

    if (await file.exists()) {
      return _readIdentityFile(file);
    }

    final File lockFile = File(
      dataDir.path + Platform.pathSeparator + kIdentityLockFileName,
    );
    final bool hasLock = await _acquireLock(lockFile);
    try {
      // 拿到锁之后再查一次：可能刚被另一个实例写好了。
      if (await file.exists()) {
        return await _readIdentityFile(file);
      }
      if (!hasLock) {
        // 极限情况下（锁文件被别人长期占着且身份仍不存在），宁可直接失败，
        // 也不能无锁写盘——否则可能覆盖掉对方刚写好的身份。
        throw LanFileException(
          LanFileErrorCode.io,
          '无法获取身份文件锁，放弃创建以避免产生第二个 peerId: ${lockFile.path}',
        );
      }

      final Uint8List candidateSeed = _randomSeed();
      final Uint8List publicKey = deriveEd25519PublicKeyFromSeed(candidateSeed);
      final String encoded = jsonEncode(<String, Object?>{
        'v': kIdentityFileVersion,
        'alg': 'ed25519',
        'seed': _encodeBase64Url(candidateSeed),
        'pub': _encodeBase64Url(publicKey),
      });

      final File temp = File('${file.path}.tmp');
      try {
        await temp.writeAsString(encoded, flush: true);
        await temp.rename(file.path);
      } on FileSystemException {
        await _deleteQuietly(temp);
        rethrow;
      }
      return DeviceIdentityImpl._(candidateSeed, publicKey);
    } finally {
      if (hasLock) {
        await _deleteQuietly(lockFile);
      }
    }
  }

  /// 生产入口：应用数据目录下取 `identity.key`。
  ///
  /// 路径来自 `path_provider` 的 `getApplicationSupportDirectory()`，
  /// 不硬编码 Windows / Android 的目录结构。
  static Future<DeviceIdentityImpl> loadOrCreateInAppData() async {
    final Directory dir = await getApplicationSupportDirectory();
    return loadOrCreate(dataDir: dir);
  }

  static Future<DeviceIdentityImpl> _readIdentityFile(File file) async {
    final String raw;
    try {
      raw = await file.readAsString();
    } on FileSystemException catch (error) {
      throw LanFileException(
        LanFileErrorCode.io,
        '读取身份文件失败: ${file.path}',
        cause: error,
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      throw LanFileException(
        LanFileErrorCode.io,
        '身份文件不是合法 JSON: ${file.path}',
        cause: error,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw LanFileException(
        LanFileErrorCode.io,
        '身份文件结构非法: ${file.path}',
      );
    }
    final Object? version = decoded['v'];
    final Object? algorithm = decoded['alg'];
    final Object? seedText = decoded['seed'];
    final Object? publicText = decoded['pub'];
    if (version != kIdentityFileVersion ||
        algorithm != 'ed25519' ||
        seedText is! String ||
        publicText is! String) {
      throw LanFileException(
        LanFileErrorCode.io,
        '身份文件版本或算法不受支持: ${file.path}',
      );
    }

    final Uint8List seed;
    final Uint8List storedPublicKey;
    try {
      seed = _decodeBase64Url(seedText);
      storedPublicKey = _decodeBase64Url(publicText);
    } on FormatException catch (error) {
      throw LanFileException(
        LanFileErrorCode.io,
        '身份文件中的密钥不是合法 base64url: ${file.path}',
        cause: error,
      );
    }
    if (seed.length != 32 || storedPublicKey.length != kEd25519PublicKeyBytes) {
      throw LanFileException(
        LanFileErrorCode.io,
        '身份文件中的密钥长度非法: ${file.path}',
      );
    }

    final Uint8List derived = deriveEd25519PublicKeyFromSeed(seed);
    if (!_constantTimeEquals(derived, storedPublicKey)) {
      throw LanFileException(
        LanFileErrorCode.io,
        '身份文件公钥与种子不匹配（文件可能被改动）: ${file.path}',
      );
    }
    return DeviceIdentityImpl._(seed, storedPublicKey);
  }

  final Uint8List _seed;
  final Uint8List _publicKey;
  final SimpleKeyPairData _keyPair;

  @override
  final PeerId peerId;

  @override
  Uint8List get publicKey => Uint8List.fromList(_publicKey);

  @override
  Future<Uint8List> sign(Uint8List payload) async {
    final Signature signature = await Ed25519().sign(
      domainSeparatedPayload(payload),
      keyPair: _keyPair,
    );
    return Uint8List.fromList(signature.bytes);
  }

  @override
  Future<bool> verifyOwn(Uint8List payload, Uint8List signature) {
    return Ed25519Signer().verify(payload, signature, _publicKey);
  }

  /// 仅用于「把本机身份迁移到另一台设备」这类显式操作；调用方必须
  /// 自行保证传输与存放安全。
  Uint8List exportSeed() => Uint8List.fromList(_seed);
}

Uint8List _randomSeed() {
  final Random random = Random.secure();
  final Uint8List seed = Uint8List(32);
  for (var i = 0; i < seed.length; i++) {
    seed[i] = random.nextInt(256);
  }
  return seed;
}

String _encodeBase64Url(Uint8List bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

Uint8List _decodeBase64Url(String text) {
  final int remainder = text.length % 4;
  final String padded = remainder == 0 ? text : text + '=' * (4 - remainder);
  return Uint8List.fromList(base64Url.decode(padded));
}

/// 独占创建锁文件；拿到返回 `true`，被别人占着返回 `false`。
///
/// 另外做一次「等锁」：`File.create(exclusive: true)` 抢到失败时对手可能
/// 正在写密钥，等它写完再让调用方回读，避免把竞态暴露给上层。
Future<bool> _acquireLock(File lockFile, {int attempts = 100}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    try {
      await lockFile.create(exclusive: true);
      return true;
    } on FileSystemException {
      // 竞争者的锁可能马上释放；等 10ms 再试，最多 ~1 秒。
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }
  return false;
}

Future<void> _deleteQuietly(File file) async {
  try {
    if (await file.exists()) {
      await file.delete();
    }
  } on FileSystemException {
    // 清理临时文件失败不改变「抢占失败」的结论。
  }
}

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
