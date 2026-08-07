import 'package:flutter/material.dart';

import '../state/tabs_controller.dart';

/// Safari/Finder-style tab strip.
///
/// Hidden entirely when only one tab is open — a lone tab is visual noise, and
/// Finder does the same.
class BrowserTabBar extends StatefulWidget {
  const BrowserTabBar({
    required this.controller,
    required this.onNewTab,
    this.onDetach,
    super.key,
  });

  final TabsController controller;
  final VoidCallback onNewTab;

  /// Called when a tab is dragged far enough out of the strip to be torn off
  /// into its own window. Null disables tear-off.
  final void Function(int index)? onDetach;

  @override
  State<BrowserTabBar> createState() => _BrowserTabBarState();
}

class _BrowserTabBarState extends State<BrowserTabBar> {
  /// How far a tab must be dragged away from the strip before releasing it
  /// detaches. Chrome uses roughly this; small enough to feel intentional,
  /// large enough that a sloppy click never tears a tab off by accident.
  static const double _detachThreshold = 56;

  int? _draggingIndex;
  Offset _dragOffset = Offset.zero;

  bool get _willDetach => _dragOffset.distance > _detachThreshold;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        if (!widget.controller.hasMultiple) return const SizedBox.shrink();

        final theme = Theme.of(context);
        return Container(
          height: 32,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: widget.controller.tabs.length,
                      itemBuilder: (context, i) => _Tab(
                        label: widget.controller.tabs[i].title,
                        selected: i == widget.controller.activeIndex,
                        // The tab being torn off dims in place, so it is
                        // obvious which one is moving.
                        dimmed: _draggingIndex == i && _willDetach,
                        onTap: () => widget.controller.select(i),
                        onClose: () => widget.controller.closeTab(i),
                        onDragStart: widget.onDetach == null
                            ? null
                            : () => setState(() {
                                _draggingIndex = i;
                                _dragOffset = Offset.zero;
                              }),
                        onDragUpdate: (delta) =>
                            setState(() => _dragOffset += delta),
                        onDragEnd: () {
                          final index = _draggingIndex;
                          final detach = _willDetach;
                          setState(() {
                            _draggingIndex = null;
                            _dragOffset = Offset.zero;
                          });
                          if (detach && index != null) {
                            widget.onDetach?.call(index);
                          }
                        },
                      ),
                    ),
                    if (_draggingIndex != null && _willDetach)
                      const Positioned.fill(child: _DetachHint()),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 16),
                tooltip: 'New Tab  ⌘T',
                visualDensity: VisualDensity.compact,
                onPressed: widget.onNewTab,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Shown once a drag has passed the detach threshold.
///
/// Flutter cannot see a pointer leave the window, so there is no way to show
/// a real dragged-out preview the way Chrome does. Saying what will happen on
/// release is the honest substitute.
class _DetachHint extends StatelessWidget {
  const _DetachHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      child: Container(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.92),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.open_in_new, size: 14),
            const SizedBox(width: 8),
            Text(
              'Release to open in a new window',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.onClose,
    this.dimmed = false,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
  });

  final String label;
  final bool selected;
  final bool dimmed;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback? onDragStart;
  final void Function(Offset delta)? onDragUpdate;
  final VoidCallback? onDragEnd;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        // Middle-click closes, as in every browser.
        onTertiaryTapUp: (_) => widget.onClose(),
        onPanStart: widget.onDragStart == null
            ? null
            : (_) {
                // Select first, so the tab that tears off is the one the user
                // is looking at.
                widget.onTap();
                widget.onDragStart!();
              },
        onPanUpdate: (d) => widget.onDragUpdate?.call(d.delta),
        onPanEnd: (_) => widget.onDragEnd?.call(),
        onPanCancel: () => widget.onDragEnd?.call(),
        child: Opacity(
          opacity: widget.dimmed ? 0.4 : 1,
          child: Container(
          constraints: const BoxConstraints(minWidth: 110, maxWidth: 200),
          decoration: BoxDecoration(
            color: widget.selected
                ? theme.colorScheme.surface
                : Colors.transparent,
            border: Border(
              right: BorderSide(color: theme.dividerColor),
              bottom: BorderSide(
                color: widget.selected
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          padding: const EdgeInsets.only(left: 12, right: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: widget.selected ? FontWeight.w600 : null,
                  ),
                ),
              ),
              // The close button only appears on hover or when active, so the
              // strip stays calm with many tabs open.
              SizedBox(
                width: 20,
                child: (_hovering || widget.selected)
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 12),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.onClose,
                      )
                    : null,
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
