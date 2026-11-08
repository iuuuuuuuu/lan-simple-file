// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lan_simple_file/ui/widgets/app_controls.dart';

export 'package:lan_simple_file/ui/widgets/app_controls.dart';

Finder findAppTooltip(Pattern message) {
  bool matches(String? text) =>
      text != null &&
      (message is RegExp ? message.hasMatch(text) : text == message);
  return find.byWidgetPredicate(
    (widget) =>
        widget is AppTooltip && matches(widget.message) ||
        widget is Tooltip && matches(widget.message),
    description: 'tooltip "$message"',
  );
}
