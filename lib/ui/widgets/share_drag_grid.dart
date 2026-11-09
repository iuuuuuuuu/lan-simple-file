// SPDX-License-Identifier: GPL-3.0-only
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/tokens.dart';
import '../../core/contracts/contracts.dart';
import 'app_controls.dart';

class ShareDragData {
  const ShareDragData(this.id);
  final String id;
}

/// Keeps scrolling and drag feedback local; the page owns persisted ordering.
class ShareDragGrid extends StatefulWidget {
  const ShareDragGrid({
    super.key,
    required this.shares,
    required this.itemBuilder,
    required this.itemExtent,
    required this.padding,
    required this.enabled,
    required this.onPlace,
    this.onDragUpdate,
    this.onDragEnd,
  });

  final List<ShareRecord> shares;
  final Widget Function(ShareRecord) itemBuilder;
  final double itemExtent;
  final EdgeInsets padding;
  final bool enabled;
  final void Function(String share, String target, bool after) onPlace;
  final ValueChanged<Offset>? onDragUpdate;
  final VoidCallback? onDragEnd;

  @override
  State<ShareDragGrid> createState() => _ShareDragGridState();
}

class _ShareDragGridState extends State<ShareDragGrid> {
  EdgeDraggingAutoScroller? _autoScroller;
  String? _dragging;
  Offset? _dragPosition;

  void _scrollAtPointer() {
    final scroller = _autoScroller;
    final pointer = _dragPosition;
    if (!mounted || scroller == null || pointer == null) return;
    final viewport =
        scroller.scrollable.context.findRenderObject()! as RenderBox;
    final local = viewport.globalToLocal(pointer);
    if (local.dy < -24 ||
        local.dy > viewport.size.height + 24 ||
        local.dx < 0 ||
        local.dx > viewport.size.width) {
      scroller.stopAutoScroll();
      return;
    }
    scroller.startAutoScrollIfNecessary(
      Rect.fromCenter(center: pointer, width: 48, height: 96),
    );
  }

  void _endDrag() {
    _autoScroller?.stopAutoScroll();
    _autoScroller = null;
    _dragPosition = null;
    widget.onDragEnd?.call();
    if (mounted) setState(() => _dragging = null);
  }

  @override
  void dispose() {
    _autoScroller?.stopAutoScroll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = ((constraints.maxWidth - 24) / 280).floor().clamp(1, 5);
      return GridView.builder(
        key: const ValueKey('my-shares-grid'),
        padding: widget.padding,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: widget.itemExtent,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: widget.shares.length,
        itemBuilder: (context, index) {
          final share = widget.shares[index];
          final id = share.id.value;
          return _ShareDropPosition(
            key: ValueKey('share-drag-$id'),
            vertical: columns == 1,
            dragging: _dragging == id,
            enabled: widget.enabled,
            id: id,
            onPlace: (source, after) => widget.onPlace(source, id, after),
            child: LongPressDraggable<ShareDragData>(
              data: ShareDragData(id),
              maxSimultaneousDrags: widget.enabled ? 1 : 0,
              delay: const Duration(milliseconds: 350),
              dragAnchorStrategy: pointerDragAnchorStrategy,
              feedbackOffset: Offset.zero,
              onDragStarted: () => setState(() => _dragging = id),
              onDragUpdate: (details) {
                widget.onDragUpdate?.call(details.globalPosition);
                _autoScroller ??= EdgeDraggingAutoScroller(
                  Scrollable.of(context),
                  velocityScalar: 18,
                  onScrollViewScrolled: _scrollAtPointer,
                );
                _dragPosition = details.globalPosition;
                _scrollAtPointer();
              },
              onDragCompleted: _endDrag,
              onDraggableCanceled: (_, _) => _endDrag(),
              feedback: InheritedTheme.captureAll(
                context,
                Material(
                  type: MaterialType.transparency,
                  child: SizedBox(
                    width: 240,
                    child: MiuixCard(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Icon(
                              share.kind == 'folder'
                                  ? LucideIcons.folder
                                  : LucideIcons.file,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                share.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              child: Opacity(
                opacity: _dragging == id ? .35 : 1,
                child: widget.itemBuilder(share),
              ),
            ),
          );
        },
      );
    },
  );
}

class _ShareDropPosition extends StatefulWidget {
  const _ShareDropPosition({
    super.key,
    required this.id,
    required this.vertical,
    required this.dragging,
    required this.enabled,
    required this.onPlace,
    required this.child,
  });
  final String id;
  final bool vertical;
  final bool dragging;
  final bool enabled;
  final void Function(String source, bool after) onPlace;
  final Widget child;

  @override
  State<_ShareDropPosition> createState() => _ShareDropPositionState();
}

class _ShareDropPositionState extends State<_ShareDropPosition>
    with AutomaticKeepAliveClientMixin {
  bool _after = false;

  @override
  bool get wantKeepAlive => widget.dragging;

  @override
  void didUpdateWidget(covariant _ShareDropPosition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dragging != widget.dragging) updateKeepAlive();
  }

  bool _isAfter(Offset global) {
    final box = context.findRenderObject()! as RenderBox;
    final local = box.globalToLocal(global);
    return widget.vertical
        ? local.dy >= box.size.height / 2
        : local.dx >= box.size.width / 2;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return DragTarget<ShareDragData>(
      onWillAcceptWithDetails: (details) {
        if (!widget.enabled || details.data.id == widget.id) return false;
        _after = _isAfter(details.offset);
        return true;
      },
      onMove: (details) {
        final after = _isAfter(details.offset);
        if (after != _after) setState(() => _after = after);
      },
      onAcceptWithDetails: (details) =>
          widget.onPlace(details.data.id, _isAfter(details.offset)),
      builder: (context, candidates, rejected) => Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (candidates.isNotEmpty)
            Positioned(
              top: widget.vertical && _after ? null : 0,
              bottom: widget.vertical && !_after ? null : 0,
              left: !widget.vertical && _after ? null : 0,
              right: !widget.vertical && !_after ? null : 0,
              height: widget.vertical ? 3 : null,
              width: widget.vertical ? null : 3,
              child: IgnorePointer(
                child: ColoredBox(
                  color: Theme.of(context).extension<LanFileTokens>()!.accent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
