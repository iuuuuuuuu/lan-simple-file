// SPDX-License-Identifier: GPL-3.0-only

/// 备用入口：与 lib/main.dart 等价，便于 IDE 直接以 lib/app/main.dart 启动。
///
/// Flutter 约定的默认入口仍是 lib/main.dart；两者共用同一段启动逻辑，
/// 避免出现第二套初始化顺序。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: LanFileApp()));
}
