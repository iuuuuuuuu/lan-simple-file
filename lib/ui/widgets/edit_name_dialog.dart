// SPDX-License-Identifier: GPL-3.0-only

import 'package:flutter/material.dart';

import 'app_controls.dart';

/// 名称输入和校验由弹窗管理，控制器随弹窗卸载释放。
class EditNameDialog extends StatefulWidget {
  const EditNameDialog({
    super.key,
    required this.title,
    required this.label,
    this.initialValue = '',
    this.maxLength = 64,
    this.fieldKey,
    this.confirmLabel = '保存',
  });
  final String title;
  final String label;
  final String initialValue;
  final int maxLength;
  final Key? fieldKey;
  final String confirmLabel;

  @override
  State<EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<EditNameDialog> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  bool _submitted = false;
  void _save() {
    if (_submitted) return;
    if (_form.currentState!.validate()) {
      _submitted = true;
      Navigator.of(context).pop(_controller.text.trim());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 360,
      child: Form(
        key: _form,
        child: AppTextField(
          key: widget.fieldKey,
          controller: _controller,
          autofocus: true,
          maxLength: widget.maxLength,
          label: widget.label,
          onSubmitted: (_) {
            final composing = _controller.value.composing;
            if (!composing.isValid || composing.isCollapsed) _save();
          },
          validator: (String? raw) {
            final String value = raw?.trim() ?? '';
            if (value.isEmpty) return '${widget.label}不能为空';
            if (value.runes.length > widget.maxLength) {
              return '最多 ${widget.maxLength} 个字符';
            }
            if (value.codeUnits.any((int c) => c < 32 || c == 127)) {
              return '不能包含控制字符';
            }
            return null;
          },
        ),
      ),
    ),
    actions: <Widget>[
      AppButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      AppButton.primary(onPressed: _save, child: Text(widget.confirmLabel)),
    ],
  );
}
