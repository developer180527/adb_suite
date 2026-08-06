import 'package:flutter/material.dart';

import '../state/tabs_controller.dart';

/// Safari/Finder-style tab strip.
///
/// Hidden entirely when only one tab is open — a lone tab is visual noise, and
/// Finder does the same.
class BrowserTabBar extends StatelessWidget {
  const BrowserTabBar({
    required this.controller,
    required this.onNewTab,
    super.key,
  });

  final TabsController controller;
  final VoidCallback onNewTab;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.hasMultiple) return const SizedBox.shrink();

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
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: controller.tabs.length,
                  itemBuilder: (context, i) => _Tab(
                    label: controller.tabs[i].title,
                    selected: i == controller.activeIndex,
                    onTap: () => controller.select(i),
                    onClose: () => controller.closeTab(i),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, size: 16),
                tooltip: 'New Tab  ⌘T',
                visualDensity: VisualDensity.compact,
                onPressed: onNewTab,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.onClose,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClose;

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
    );
  }
}
