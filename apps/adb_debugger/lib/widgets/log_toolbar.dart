import 'package:feature_logcat/feature_logcat.dart';
import 'package:flutter/material.dart';

/// Everything that changes what the log shows, in one row.
///
/// Ordered by how often it is reached for: capture state first, then the
/// search that narrows it, then the level that narrows it further. Destructive
/// and occasional controls sit on the right, away from the ones used every
/// minute.
class LogToolbar extends StatefulWidget {
  const LogToolbar({
    required this.controller,
    required this.deviceName,
    required this.railVisible,
    required this.onToggleRail,
    required this.onCopy,
    required this.onDisconnect,
    this.encrypted,
    super.key,
  });

  final LogcatController controller;
  final String deviceName;

  /// Null when the transport cannot say — see feature_connect.
  final bool? encrypted;

  final bool railVisible;
  final VoidCallback onToggleRail;
  final VoidCallback onCopy;
  final VoidCallback onDisconnect;

  @override
  State<LogToolbar> createState() => _LogToolbarState();
}

class _LogToolbarState extends State<LogToolbar> {
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _query.text = widget.controller.filter.query;
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  LogFilter get _filter => widget.controller.filter;

  void _apply(LogFilter next) => widget.controller.setFilter(next);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paused = widget.controller.isPaused;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          // Pause is the single most-used control in a log viewer: something
          // scrolled past and you want it to stop *now*. It reads as a toggle,
          // not a stop button, because the capture keeps running underneath.
          Tooltip(
            message: paused ? 'Resume  ⌘R' : 'Pause  ⌘R',
            child: FilledButton.tonalIcon(
              onPressed: () => widget.controller.setPaused(!paused),
              icon: Icon(paused ? Icons.play_arrow : Icons.pause, size: 16),
              label: Text(paused ? 'Paused' : 'Live'),
              style: FilledButton.styleFrom(
                backgroundColor: paused
                    ? theme.colorScheme.errorContainer
                    : theme.colorScheme.secondaryContainer,
                foregroundColor: paused
                    ? theme.colorScheme.onErrorContainer
                    : theme.colorScheme.onSecondaryContainer,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 32),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.playlist_remove, size: 18),
            tooltip: 'Clear this view  ⌘K',
            onPressed: widget.controller.clearLocal,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            tooltip: 'Clear the device buffer too',
            onPressed: () => widget.controller.clearAll(),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: TextField(
              controller: _query,
              decoration: InputDecoration(
                hintText: 'Filter by tag or message',
                prefixIcon: const Icon(Icons.search, size: 16),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 14),
                        onPressed: () {
                          _query.clear();
                          _apply(_filter.copyWith(query: ''));
                          setState(() {});
                        },
                      ),
              ),
              style: theme.textTheme.bodySmall,
              onChanged: (value) {
                _apply(_filter.copyWith(query: value));
                setState(() {});
              },
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: 'Treat the filter as a regular expression',
            child: IconButton(
              isSelected: _filter.useRegex,
              selectedIcon: Icon(
                Icons.data_object,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              icon: const Icon(Icons.data_object, size: 18),
              onPressed: () => _apply(
                _filter.copyWith(useRegex: !_filter.useRegex),
              ),
            ),
          ),
          const SizedBox(width: 8),

          _LevelSelector(
            value: _filter.minLevel,
            onChanged: (level) => _apply(_filter.copyWith(minLevel: level)),
          ),

          const SizedBox(width: 12),
          const VerticalDivider(width: 1, indent: 6, endIndent: 6),
          const SizedBox(width: 8),

          _DeviceChip(name: widget.deviceName, encrypted: widget.encrypted),
          IconButton(
            icon: const Icon(Icons.copy_all_outlined, size: 18),
            tooltip: 'Copy visible lines  ⌘C',
            onPressed: widget.onCopy,
          ),
          IconButton(
            isSelected: widget.railVisible,
            icon: const Icon(Icons.monitor_heart_outlined, size: 18),
            tooltip: widget.railVisible ? 'Hide vitals' : 'Show vitals',
            onPressed: widget.onToggleRail,
          ),
          IconButton(
            icon: const Icon(Icons.logout, size: 18),
            tooltip: 'Disconnect',
            onPressed: widget.onDisconnect,
          ),
        ],
      ),
    );
  }
}

/// Minimum level, as a menu rather than six chips.
///
/// Levels are ordered and the filter is "this and above", so a row of toggles
/// would imply they can be picked independently when they cannot.
class _LevelSelector extends StatelessWidget {
  const _LevelSelector({required this.value, required this.onChanged});

  final LogLevel value;
  final ValueChanged<LogLevel> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MenuAnchor(
      builder: (context, controller, _) => TextButton.icon(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: Icon(Icons.filter_list, size: 16, color: levelColor(value, theme)),
        label: Text('${value.label}+', style: theme.textTheme.bodySmall),
        style: TextButton.styleFrom(minimumSize: const Size(0, 32)),
      ),
      menuChildren: [
        for (final level in LogLevel.values)
          MenuItemButton(
            leadingIcon: Icon(
              level == value ? Icons.check : Icons.circle,
              size: level == value ? 16 : 8,
              color: levelColor(level, theme),
            ),
            onPressed: () => onChanged(level),
            child: Text(level.label),
          ),
      ],
    );
  }
}

/// Level colours, shared so the toolbar and the log body cannot disagree.
Color levelColor(LogLevel level, ThemeData theme) => switch (level) {
  LogLevel.verbose => theme.colorScheme.onSurfaceVariant,
  LogLevel.debug => theme.colorScheme.tertiary,
  LogLevel.info => theme.colorScheme.primary,
  LogLevel.warn => const Color(0xFFE0A030),
  LogLevel.error => theme.colorScheme.error,
  LogLevel.fatal => theme.colorScheme.error,
};

class _DeviceChip extends StatelessWidget {
  const _DeviceChip({required this.name, this.encrypted});

  final String name;
  final bool? encrypted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Same rule as adb_files: only an unencrypted session earns an icon.
    // Decorating a healthy state teaches people to stop looking at it.
    final warn = encrypted == false;

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: warn
            ? '$name — connected over the legacy ADB protocol, which is not '
                  'encrypted.'
            : name,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              warn ? Icons.lock_open : Icons.smartphone,
              size: 14,
              color: warn ? theme.colorScheme.error : theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
