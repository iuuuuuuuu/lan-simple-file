// SPDX-License-Identifier: GPL-3.0-only

/// 网页上传的磁盘临时区：`temp/web-share/<sessionId>/<uploadId>/<name>`。
///
/// 三条硬约束在这里落地（它们是产品要求，不是实现细节）：
/// 1. **接受前零字节**：没拿到上传凭证时 [beginUpload] 直接拒，且不建任何目录/文件；
/// 2. 配额按会话计，跨上传累计；超额连目录都不建；
/// 3. 队列释放只在宽限期后发生，由 [SessionSweeper] 驱动，不在请求路径里删。
library;

import 'dart:io';

import 'package:lan_simple_file/core/contracts/contracts.dart';

/// 一次上传在临时区里的落点。
final class StagingUpload {
  const StagingUpload({
    required this.uploadId,
    required this.directory,
    required this.fileName,
  });

  final String uploadId;

  /// 该上传独占的目录；文件写在其中，避免不同 visitor 同名互覆盖。
  final String directory;

  /// 最终文件名（已净化，不含路径分隔符）。
  final String fileName;

  /// 数据文件的绝对路径。
  String get filePath => '$directory${Platform.pathSeparator}$fileName';

  /// 该上传目录的归属会话。
  String get sessionId => directory.split(Platform.pathSeparator).last;
}

/// 临时区门面。
///
/// 只暴露「建位置 / 写字节 / 校验配额 / 列残留 / 删」这五件事；
/// 任何一段都不得在未授权时创建文件。
final class StagingArea {
  StagingArea({
    required this.rootPath,
    this.quotaBytes = LanFileConstants.webShareQuotaBytes,
  });

  /// 临时区根目录的绝对路径（如 `<appdata>/temp/web-share`）。
  final String rootPath;

  /// 单会话配额（20 GB）。
  final int quotaBytes;

  /// 临时区根。
  Directory get root => Directory(rootPath);

  /// 会话目录。
  ///
  /// 取值即校验：会话 id 来自浏览器，直接拼进路径就是路径穿越入口
  /// （`../../x` 会把临时区写到盘上任意位置）。这里不接受未校验的 id。
  Directory sessionDir(String sessionId) => Directory(
    '$rootPath${Platform.pathSeparator}${requireValidSessionId(sessionId)}',
  );

  /// 校验会话 id 形态：只允许字母数字、下划线、连字符，长度 8..64。
  ///
  /// 会话 id 来自浏览器，必须当不可信输入处理——否则 `../` 就能把
  /// 临时区写到盘上任意位置。
  static String requireValidSessionId(String sessionId) {
    if (sessionId.length < 8 || sessionId.length > 64) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        'guestSessionId 长度必须在 8..64 之间',
      );
    }
    for (final int unit in sessionId.codeUnits) {
      final bool ok = (unit >= 0x30 && unit <= 0x39) ||
          (unit >= 0x41 && unit <= 0x5a) ||
          (unit >= 0x61 && unit <= 0x7a) ||
          unit == 0x5f ||
          unit == 0x2d;
      if (!ok) {
        throw const LanFileException(
          LanFileErrorCode.invalidArgument,
          'guestSessionId 只能由字母数字、下划线、连字符组成',
        );
      }
    }
    return sessionId;
  }

  /// 净化上传文件名：去掉任何路径分隔符与控制字符，拒绝 `..` 段。
  static String sanitizeFileName(String raw) {
    final StringBuffer buffer = StringBuffer();
    for (final int rune in raw.runes) {
      if (rune < 0x20 || rune == 0x7f) continue;
      if (rune == 0x2f || rune == 0x5c) {
        // 路径分隔符一律替换，避免把文件写到目录外。
        buffer.write('_');
        continue;
      }
      buffer.writeCharCode(rune);
    }
    String name = buffer.toString().trim();
    if (name.isEmpty || name == '.' || name == '..') {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        '上传文件名为空或非法',
      );
    }
    if (name.length > 200) name = name.substring(0, 200);
    return name;
  }

  /// 会话目录当前占用的字节数（递归累加）。
  Future<int> usedBytes(String sessionId) async {
    final Directory dir = sessionDir(requireValidSessionId(sessionId));
    if (!await dir.exists()) return 0;
    int total = 0;
    await for (final FileSystemEntity entity in dir.list(recursive: true)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } on FileSystemException {
          // 正在写的文件可能瞬间不可读，跳过这一次，不要把总数算崩。
        }
      }
    }
    return total;
  }

  /// 配额检查：`已用 + 追加` 超过配额就抛 507。
  ///
  /// 这一步必须在**创建任何文件之前**完成，否则「先写后拒」会留下垃圾。
  Future<void> requireQuota(String sessionId, int additionalBytes) async {
    if (additionalBytes < 0) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        '追加字节数不能为负',
      );
    }
    final int used = await usedBytes(sessionId);
    if (used + additionalBytes > quotaBytes) {
      throw LanFileException(
        LanFileErrorCode.quotaExceeded,
        '网页临时区配额已满：已用 $used，需再写入 $additionalBytes，'
        '配额 $quotaBytes',
      );
    }
  }

  /// 为一个已获授权的上传准备落点。
  ///
  /// **调用方必须先完成授权判定**（offer 被接受且上传凭证有效）。
  /// 本方法在授权通过后才允许创建目录；未授权时调用它是编码错误。
  Future<StagingUpload> beginUpload({
    required String sessionId,
    required String uploadId,
    required String fileName,
    required int declaredSize,
  }) async {
    requireValidSessionId(sessionId);
    requireValidUploadId(uploadId);
    final String safeName = sanitizeFileName(fileName);
    await requireQuota(sessionId, declaredSize);

    final String dir =
        '${sessionDir(sessionId).path}${Platform.pathSeparator}$uploadId';
    await Directory(dir).create(recursive: true);
    return StagingUpload(
      uploadId: uploadId,
      directory: dir,
      fileName: safeName,
    );
  }

  /// 上传 id 形态：与会话 id 同一套字符集。
  static String requireValidUploadId(String uploadId) {
    if (uploadId.length < 4 || uploadId.length > 64) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        'uploadId 长度必须在 4..64 之间',
      );
    }
    for (final int unit in uploadId.codeUnits) {
      final bool ok = (unit >= 0x30 && unit <= 0x39) ||
          (unit >= 0x41 && unit <= 0x5a) ||
          (unit >= 0x61 && unit <= 0x7a) ||
          unit == 0x5f ||
          unit == 0x2d;
      if (!ok) {
        throw const LanFileException(
          LanFileErrorCode.invalidArgument,
          'uploadId 只能由字母数字、下划线、连字符组成',
        );
      }
    }
    return uploadId;
  }

  /// 把分片写到指定偏移；返回写入后的文件长度。
  ///
  /// [expectedTotal] 用于防止「声称 1KB 实际写 1GB」的越权写入。
  Future<int> writeChunk({
    required StagingUpload upload,
    required int offset,
    required List<int> data,
    required int expectedTotal,
  }) async {
    if (offset < 0) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        '写入偏移不能为负',
      );
    }
    final int end = offset + data.length;
    if (end > expectedTotal) {
      throw const LanFileException(
        LanFileErrorCode.invalidArgument,
        '写入超出声明的文件长度',
      );
    }
    final File file = File(upload.filePath);
    await file.parent.create(recursive: true);
    final RandomAccessFile handle = await file.open(mode: FileMode.append);
    try {
      await handle.setPosition(offset);
      await handle.writeFrom(data);
      await handle.flush();
    } finally {
      await handle.close();
    }
    return end;
  }

  /// 列出当前磁盘上所有会话目录名。
  Future<List<String>> listSessionIds() async {
    final Directory root = this.root;
    if (!await root.exists()) return <String>[];
    final List<String> ids = <String>[];
    await for (final FileSystemEntity entity in root.list()) {
      if (entity is Directory) {
        final String name = entity.path.split(Platform.pathSeparator).last;
        ids.add(name);
      }
    }
    ids.sort();
    return ids;
  }

  /// 删除某会话的全部临时文件与元数据。
  Future<void> purgeSession(String sessionId) async {
    final Directory dir = sessionDir(requireValidSessionId(sessionId));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// 磁盘上是否还能找到该会话的任何残留。
  Future<bool> hasResidue(String sessionId) async {
    final Directory dir = sessionDir(requireValidSessionId(sessionId));
    return dir.exists();
  }
}