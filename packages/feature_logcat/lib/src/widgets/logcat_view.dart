import 'package:adb_ui/adb_ui.dart';
import 'package:flutter/material.dart';

import '../logcat_controller.dart';
import '../models/log_level.dart';
import '../models/logcat_entry.dart';

/// Colour per priority. Tuned for both themes rather than using raw
/// Colors.red/green, which vanish against a dark background.
class LogLevelColors {
  static Color of(LogLevel? level, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return switch (level) {
      LogLevel.verbose => dark ? const Color(0xFF9E9E9E) : const Color(0xFF757575),
      LogLevel.debug => dark ? const Color(0xFF64B5F6) : const Color(0xFF1565C0),
      LogLevel.info => dark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
      LogLevel.warn => dark ? const Color(0xFFFFB74D) : const Color(0xFFE65100),
      LogLevel.error => dark ? const Color(0xFFE57373) : const Color(0xFFC62828),
      LogLevel.fatal => dark ? const Color(0xFFF48FB1) : const Color(0xFFAD1457),
      null => dark ? const Color(0xFF757575) : const Color(0xFF9E9E9E),
    };
  }
}

/// Scrolling log view with follow-tail behaviour.
class LogcatView extends StatefulWidget {
  const LogcatView({required this.controller, super.key});

  final LogcatController controller;

  @override
  State<LogcatView> createState() => _LogcatViewState();
}

class _LogcatViewState extends State<LogcatView> {
  final _scrollController = ScrollController();
  bool _followTail = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onUpdate);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    // Scrolling away from the bottom means the user is reading history, so
    // stop yanking them back. Returning to the bottom re-arms follow.
    final position = _scrollController.position;
    final atBottom = position.pixels >= position.maxScrollExtent - 24;
    if (atBottom != _followTail) setState(() => _followTail = atBottom);
  }

  void _onUpdate() {
    if (!_followTail || !mounted) return;
    // Jump after the frame the new entries are laid out in, or maxScrollExtent
    // is still the old value.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_followTail || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final entries = widget.controller.visible;

        if (widget.controller.error != null && entries.isEmpty) {
          return Center(child: Text('${widget.controller.error}'));
        }
        if (entries.isEmpty) {
          return Center(
            child: Text(
              widget.controller.filter.isActive
                  ? 'No entries match the filter'
                  : 'Waiting for output…',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }

        return Stack(
          children: [
            // itemExtent keeps scrolling O(1) with tens of thousands of rows;
            // without it Flutter measures every child to compute extent.
            ListView.builder(
              controller: _scrollController,
              itemCount: entries.length,
              itemExtent: 20,
              itemBuilder: (context, i) => _LogRow(entry: entries[i]),
            ),
            if (!_followTail)
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton.small(
                  onPressed: () {
                    setState(() => _followTail = true);
                    _scrollController.jumpTo(
                      _scrollController.position.maxScrollExtent,
                    );
                  },
                  child: const Icon(Icons.arrow_downward),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final LogcatEntry entry;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final color = LogLevelColors.of(entry.level, brightness);
    final style = TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'monospace'],
      fontSize: 12,
      height: 1.35,
      color: color,
    );

    if (!entry.isParsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          entry.raw,
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry.timestamp != null) ...[
            Text(formatClock(entry.timestamp!), style: style),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: 14,
            child: Text(
              entry.level!.code,
              style: style.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(
            width: 140,
            child: Text(
              entry.tag ?? '',
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.message,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Level threshold, search box, and pause/clear controls.
class LogcatToolbar extends StatelessWidget {
  const LogcatToolbar({required this.controller, super.key});

  final LogcatController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final filter = controller.filter;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              DropdownButton<LogLevel>(
                value: filter.minLevel,
                underline: const SizedBox.shrink(),
                onChanged: (level) {
                  if (level != null) {
                    controller.setFilter(filter.copyWith(minLevel: level));
                  }
                },
                items: [
                  for (final level in LogLevel.values)
                    DropdownMenuItem(
                      value: level,
                      child: Text(
                        level.label,
                        style: TextStyle(
                          color: LogLevelColors.of(
                            level,
                            Theme.of(context).brightness,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Filter…',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: 'Regular expression',
                      icon: Icon(
                        Icons.code,
                        size: 18,
                        color: filter.useRegex
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      onPressed: () => controller.setFilter(
                        filter.copyWith(useRegex: !filter.useRegex),
                      ),
                    ),
                  ),
                  onChanged: (q) =>
                      controller.setFilter(filter.copyWith(query: q)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: controller.isPaused ? 'Resume' : 'Pause',
                icon: Icon(
                  controller.isPaused ? Icons.play_arrow : Icons.pause,
                ),
                onPressed: () => controller.setPaused(!controller.isPaused),
              ),
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.delete_outline),
                onPressed: controller.clearLocal,
              ),
              const SizedBox(width: 8),
              Text(
                '${controller.visible.length} / ${controller.totalCount}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}
