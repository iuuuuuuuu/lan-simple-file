// SPDX-License-Identifier: GPL-3.0-only

/// 安卓 SAF 的 FileRefFactory 实现。
///
/// rootUri 是 SAF 树 URI（形如 content://com.android.externalstorage.documents/tree/primary%3ADCIM）；
/// resolve 传入的 ItemKey 是 documentId（形如 primary:DCIM/Camera）。
library;

import '../contracts/errors.dart';
import '../contracts/file_ref.dart';
import '../contracts/types.dart';
import 'saf_bridge.dart';
import 'saf_ref.dart';

/// 由 SAF 树 URI 构造 [SafRef] 的工厂。
final class SafRefFactory implements FileRefFactory {
  SafRefFactory(this.bridge);

  /// 通道封装；测试可注入带 mock channel 的实例。
  final SafBridge bridge;

  @override
  ShareRootKind get rootKind => ShareRootKind.safTree;

  @override
  Future<FileRef> openRoot(String rootUri) async {
    _requireTreeUri(rootUri);
    return SafRef(
      bridge: bridge,
      treeUri: rootUri,
      documentId: _rootDocumentId(rootUri),
    );
  }

  @override
  Future<FileRef> resolve(String rootUri, ItemKey itemKey) async {
    _requireTreeUri(rootUri);
    final String rootDocumentId = _rootDocumentId(rootUri);
    final String target = itemKey.value;
    if (target == rootDocumentId ||
        target.startsWith('$rootDocumentId/')) {
      return SafRef(bridge: bridge, treeUri: rootUri, documentId: target);
    }
    throw LanFileException(
      LanFileErrorCode.invalidArgument,
      'itemKey 不在该 root 下: $target（root=$rootDocumentId）',
    );
  }

  @override
  Future<bool> canRead(String rootUri) async {
    _requireTreeUri(rootUri);
    try {
      return await bridge.canRead(rootUri);
    } on LanFileException catch (e) {
      if (e.code == LanFileErrorCode.accessDenied ||
          e.code == LanFileErrorCode.notFound) {
        return false;
      }
      rethrow;
    }
  }

  /// 从树 URI 解出根 documentId。
  ///
  /// SAF 树 URI 末段形如 tree/primary%3ADCIM%2FCamera，
  /// 解开百分号编码即得 documentId primary:DCIM/Camera。
  static String _rootDocumentId(String treeUri) {
    final Uri uri = Uri.parse(treeUri);
    final List<String> segments = uri.pathSegments;
    if (segments.isEmpty) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '树 URI 缺少路径段: $treeUri',
      );
    }
    final String last = segments.last;
    if (last.isEmpty) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        '树 URI 缺少 documentId: $treeUri',
      );
    }
    return last;
  }

  void _requireTreeUri(String rootUri) {
    if (rootUri.isEmpty) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        'rootUri 不能为空',
      );
    }
    if (!rootUri.startsWith('content://') || !rootUri.contains('/tree/')) {
      throw LanFileException(
        LanFileErrorCode.invalidArgument,
        'rootUri 不是 SAF 树 URI: $rootUri',
      );
    }
  }
}
