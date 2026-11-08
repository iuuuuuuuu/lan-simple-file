// SPDX-License-Identifier: GPL-3.0-only

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';

import '../../app/theme/app_theme.dart';
import 'app_toast.dart';
import 'app_tooltip.dart';

export 'package:flutter_miuix/miuix.dart';

export 'app_tooltip.dart';

/// Application sizing and accessibility around the Miuix controls.
class AppButton extends StatelessWidget {
  const AppButton({super.key, required this.onPressed, required this.child})
    : primary = false,
      icon = null;
  const AppButton.primary({
    super.key,
    required this.onPressed,
    required this.child,
  }) : primary = true,
       icon = null;
  const AppButton.icon({
    super.key,
    required this.onPressed,
    required Widget label,
    required this.icon,
  }) : primary = false,
       child = label;

  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final bool primary;

  @override
  Widget build(BuildContext context) => MiuixButton(
    onPressed: onPressed,
    colors: primary ? MiuixButtonDefaults.buttonColorsPrimary(context) : null,
    minHeight: 36,
    insideMargin: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    child: icon == null
        ? child
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon!,
              const SizedBox(width: 6),
              Flexible(child: child),
            ],
          ),
  );
}

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.padding = const EdgeInsets.all(8),
    this.constraints,
    this.iconSize,
    this.color,
    this.selected = false,
  });
  final VoidCallback? onPressed;
  final Widget icon;
  final String? tooltip;
  final EdgeInsetsGeometry padding;
  final BoxConstraints? constraints;
  final double? iconSize;
  final Color? color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = MiuixTheme.of(context).colors;
    final button = MiuixIconButton(
      onPressed: onPressed,
      minWidth: constraints?.minWidth ?? 36,
      minHeight: constraints?.minHeight ?? 36,
      backgroundColor: selected ? colors.secondaryContainer : null,
      child: Padding(
        padding: padding,
        child: IconTheme.merge(
          data: IconThemeData(
            size: iconSize ?? 20,
            color: onPressed == null
                ? colors.disabledOnSecondaryVariant
                : color ?? (selected ? colors.primary : colors.onSurface),
          ),
          child: icon,
        ),
      ),
    );
    return tooltip == null
        ? button
        : AppTooltip(message: tooltip!, child: button);
  }
}

/// Miuix does not supply a FormField or a character limit; keep those contracts
/// here so name validation and composing input survive the component migration.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.label = '',
    this.placeholder = false,
    this.leading,
    this.trailing,
    this.autofocus = false,
    this.enabled = true,
    this.maxLength,
    this.minLines,
    this.maxLines = 1,
    this.style,
    this.keyboardType,
    this.textInputAction,
  });
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final String label;
  final bool placeholder;
  final Widget? leading;
  final Widget? trailing;
  final bool autofocus;
  final bool enabled;
  final int? maxLength;
  final int? minLines;
  final int? maxLines;
  final TextStyle? style;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  final _form = GlobalKey<FormFieldState<String>>();
  TextEditingController? _owned;
  TextEditingController get _controller => widget.controller ?? _owned!;
  TextEditingValue _previous = TextEditingValue.empty;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    if (widget.controller == null) _owned = TextEditingController();
    _previous = _controller.value;
    _controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(AppTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? _owned!).removeListener(_changed);
      _owned?.dispose();
      _owned = null;
      _attach();
    }
  }

  void _changed() {
    final limit = widget.maxLength;
    final value = _controller.value;
    if (limit != null) {
      final limited = LengthLimitingTextInputFormatter(
        limit,
        maxLengthEnforcement: MaxLengthEnforcement.truncateAfterCompositionEnds,
      ).formatEditUpdate(_previous, value);
      if (limited != value) {
        _controller.value = limited;
        return;
      }
    }
    _previous = _controller.value;
    _form.currentState?.didChange(_controller.text);
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormField<String>(
    key: _form,
    initialValue: _controller.text,
    validator: widget.validator,
    builder: (field) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MiuixTextField(
          controller: _controller,
          focusNode: widget.focusNode,
          label: widget.label,
          useLabelAsPlaceholder: widget.placeholder,
          leadingIcon: widget.leading,
          trailingIcon: widget.trailing,
          autofocus: widget.autofocus,
          enabled: widget.enabled,
          singleLine: widget.maxLines == 1,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          textStyle: widget.style ?? const TextStyle(fontSize: 14),
          insideMargin: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          onChanged: (_) => widget.onChanged?.call(_controller.text),
          onSubmitted: widget.onSubmitted,
        ),
        if (field.errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                field.errorText!,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
      ],
    ),
  );
}

class AppListTile extends StatelessWidget {
  const AppListTile({
    super.key,
    this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.dense = false,
    this.enabled = true,
  });
  final Widget? title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool dense;
  final bool enabled;

  @override
  Widget build(BuildContext context) => MiuixBasicComponent(
    onClick: onTap,
    enabled: enabled,
    startAction: leading,
    endActions: trailing == null ? null : [Flexible(child: trailing!)],
    insideMargin: EdgeInsets.symmetric(
      horizontal: 14,
      vertical: dense ? 8 : 12,
    ),
    content: [
      if (title != null)
        DefaultTextStyle.merge(
          style: const TextStyle(fontSize: 14),
          child: title!,
        ),
      if (subtitle != null)
        DefaultTextStyle.merge(
          style: TextStyle(
            fontSize: 12,
            color: MiuixTheme.of(context).colors.onSurfaceVariantSummary,
          ),
          child: subtitle!,
        ),
    ],
  );
}

class AppCheckboxTile extends StatelessWidget {
  const AppCheckboxTile({
    super.key,
    required this.value,
    required this.onChanged,
    required this.title,
    this.subtitle,
  });
  final bool value;
  final ValueChanged<bool?>? onChanged;
  final Widget title;
  final Widget? subtitle;

  @override
  Widget build(BuildContext context) => AppListTile(
    title: title,
    subtitle: subtitle,
    onTap: onChanged == null ? null : () => onChanged!(!value),
    trailing: MiuixCheckbox(value: value, onChanged: onChanged),
  );
}

class AppMenuItem<T> {
  const AppMenuItem({
    required this.value,
    required this.label,
    this.enabled = true,
  });
  final T value;
  final String label;
  final bool enabled;
}

class AppMenuButton<T> extends StatelessWidget {
  const AppMenuButton({
    super.key,
    required this.itemBuilder,
    required this.onSelected,
    this.tooltip = '更多',
    this.icon,
    this.enabled = true,
    this.iconSize = 20,
    this.padding = EdgeInsets.zero,
    this.constraints,
  });
  final List<AppMenuItem<T>> Function(BuildContext) itemBuilder;
  final ValueChanged<T> onSelected;
  final String tooltip;
  final Widget? icon;
  final bool enabled;
  final double iconSize;
  final EdgeInsetsGeometry padding;
  final BoxConstraints? constraints;

  @override
  Widget build(BuildContext context) => AppIconButton(
    tooltip: tooltip,
    icon: icon ?? const Icon(Icons.more_horiz),
    iconSize: iconSize,
    padding: padding,
    constraints: constraints,
    onPressed: !enabled
        ? null
        : () async {
            final box = context.findRenderObject()! as RenderBox;
            final overlay =
                Overlay.of(context).context.findRenderObject()! as RenderBox;
            final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
            final selected = await showAppMenu<T>(
              context: context,
              position: RelativeRect.fromRect(
                Rect.fromLTWH(
                  origin.dx,
                  origin.dy + box.size.height,
                  box.size.width,
                  0,
                ),
                Offset.zero & overlay.size,
              ),
              items: itemBuilder(context),
            );
            // Wait for the menu host to unmount before actions can remove its anchor.
            if (selected != null && context.mounted) onSelected(selected);
          },
  );
}

/// Navigator owns the result and back handling; Miuix owns panel and dimming.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) async {
  AppToast.dismiss();
  final route = RawDialogRoute<T>(
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    pageBuilder: (routeContext, _, _) => AppMiuixTheme(
      child: _AppDialogOptions(
        barrierDismissible: barrierDismissible,
        child: CallbackShortcuts(
          bindings: {
            if (barrierDismissible)
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  Navigator.of(routeContext).pop(),
          },
          child: MiuixScaffold(
            containerColor: Colors.transparent,
            contentWindowInsets: EdgeInsets.zero,
            content: (_) => Builder(builder: builder),
          ),
        ),
      ),
    ),
  );
  final result = await Navigator.of(context).push(route);
  await route.completed;
  return result;
}

class _AppDialogOptions extends InheritedWidget {
  const _AppDialogOptions({
    required this.barrierDismissible,
    required super.child,
  });
  final bool barrierDismissible;
  @override
  bool updateShouldNotify(_AppDialogOptions oldWidget) =>
      barrierDismissible != oldWidget.barrierDismissible;
}

class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    this.title,
    required this.content,
    this.actions = const [],
    this.maxWidth = 560,
  });
  final Widget? title;
  final Widget content;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Bound scrollable contents before the Miuix panel adds its own margins.
    final height = math.max(
      80.0,
      math.min(
            media.size.height * .66,
            media.size.height -
                media.viewInsets.bottom -
                media.padding.vertical -
                32,
          ) -
          48,
    );
    return MiuixOverlayDialog(
      show: true,
      maxWidth: maxWidth,
      renderInRootScaffold: false,
      onDismissRequest:
          context
                  .dependOnInheritedWidgetOfExactType<_AppDialogOptions>()
                  ?.barrierDismissible ==
              false
          ? null
          : () => Navigator.of(context).pop(),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: DefaultTextStyle.merge(
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  child: title!,
                ),
              ),
            Flexible(child: SingleChildScrollView(child: content)),
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.body,
    this.backgroundColor,
    this.bottomNavigationBar,
    this.appBar,
    this.extendBody = false,
    this.resizeToAvoidBottomInset = true,
  });
  final Widget body;
  final Color? backgroundColor;
  final Widget? bottomNavigationBar;
  final Widget? appBar;
  final bool extendBody;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) => AppMiuixTheme(
    child: Padding(
      padding: EdgeInsets.only(
        bottom: resizeToAvoidBottomInset
            ? MediaQuery.viewInsetsOf(context).bottom
            : 0,
      ),
      child: MiuixScaffold(
        containerColor: backgroundColor,
        contentWindowInsets: EdgeInsets.zero,
        topBar: appBar,
        bottomBar: bottomNavigationBar,
        content: (padding) => Padding(
          padding: extendBody ? EdgeInsets.only(top: padding.top) : padding,
          child: MediaQuery.removeViewInsets(
            context: context,
            removeBottom: resizeToAvoidBottomInset,
            child: body,
          ),
        ),
      ),
    ),
  );
}

class AppDivider extends StatelessWidget {
  const AppDivider({
    super.key,
    this.height = 1,
    this.thickness = .75,
    this.indent = 0,
    this.endIndent = 0,
    this.color,
  });
  final double height;
  final double thickness;
  final double indent;
  final double endIndent;
  final Color? color;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: math.max(height, thickness),
    child: Center(
      child: Padding(
        padding: EdgeInsets.only(left: indent, right: endIndent),
        child: MiuixHorizontalDivider(thickness: thickness, color: color),
      ),
    ),
  );
}

class AppVerticalDivider extends StatelessWidget {
  const AppVerticalDivider({super.key, this.width = 1, this.color});
  final double width;
  final Color? color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: MiuixVerticalDivider(color: color),
  );
}

Future<T?> showAppMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<AppMenuItem<T>> items,
}) => showAppDialog<T>(
  context: context,
  builder: (context) => MiuixOverlayListPopup(
    show: true,
    anchorBounds: Rect.fromLTWH(position.left, position.top, 0, 0),
    renderInRootScaffold: false,
    enableWindowDim: false,
    popupPositionProvider: MiuixListPopupDefaults.contextMenuPosition,
    onDismissRequest: () => Navigator.of(context).pop(),
    content: AppMenuList(
      children: [
        for (final item in items)
          AppListTile(
            title: Text(item.label),
            enabled: item.enabled,
            dense: true,
            onTap: () => Navigator.of(context).pop(item.value),
          ),
      ],
    ),
  ),
);

class AppMenuList extends StatelessWidget {
  const AppMenuList({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
          FocusScope.of(context).nextFocus(),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
          FocusScope.of(context).previousFocus(),
    },
    child: MiuixListPopupColumn(children: children),
  );
}
