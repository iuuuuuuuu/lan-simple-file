// SPDX-License-Identifier: GPL-3.0-only

import 'package:flutter/material.dart';
import 'package:flutter_miuix/miuix.dart';

class AppTooltip extends StatefulWidget {
  const AppTooltip({super.key, required this.message, required this.child});
  final String message;
  final Widget child;

  @override
  State<AppTooltip> createState() => _AppTooltipState();
}

class _AppTooltipState extends State<AppTooltip> {
  final _portal = OverlayPortalController();
  final _visibility = MiuixTooltipState();

  @override
  void initState() {
    super.initState();
    _visibility.addListener(_sync);
  }

  void _sync() {
    if (_visibility.isVisible) {
      _portal.show();
    } else {
      _portal.hide();
    }
  }

  @override
  void dispose() {
    _visibility.removeListener(_sync);
    _visibility.dispose();
    super.dispose();
  }

  // Miuix 1.3.0's TooltipBox invalidates an OverlayEntry during build on
  // updates. A portal keeps the Miuix surface attached to its anchor and theme.
  @override
  Widget build(BuildContext context) => Semantics(
    tooltip: widget.message,
    child: OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayChildBuilder: (context, info) {
        final anchor = MatrixUtils.transformRect(
          info.childPaintTransform,
          Offset.zero & info.childSize,
        );
        return IgnorePointer(
          child: CustomSingleChildLayout(
            delegate: _TooltipPosition(anchor),
            child: MiuixPlainTooltip(
              scope: MiuixTooltipScope(
                positioning: MiuixTooltipAnchorPosition.below,
                anchorBounds: anchor,
              ),
              child: Text(widget.message),
            ),
          ),
        );
      },
      child: MouseRegion(
        onEnter: (_) => _visibility.show(),
        onExit: (_) => _visibility.dismiss(),
        child: Listener(
          onPointerDown: (_) => _visibility.dismiss(),
          child: GestureDetector(
            onLongPress: _visibility.show,
            behavior: HitTestBehavior.deferToChild,
            child: widget.child,
          ),
        ),
      ),
    ),
  );
}

class _TooltipPosition extends SingleChildLayoutDelegate {
  const _TooltipPosition(this.anchor);
  final Rect anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen().deflate(const EdgeInsets.all(8));

  @override
  Offset getPositionForChild(Size size, Size childSize) => positionDependentBox(
    size: size,
    childSize: childSize,
    target: anchor.center,
    verticalOffset: anchor.height / 2 + 8,
    preferBelow: true,
    margin: 8,
  );

  @override
  bool shouldRelayout(_TooltipPosition oldDelegate) =>
      anchor != oldDelegate.anchor;
}
