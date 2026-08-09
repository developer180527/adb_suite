import 'package:feature_stats/feature_stats.dart';
import 'package:flutter/material.dart';

/// Device vitals beside the log, not behind a tab.
///
/// A fixed width rather than a flexible one: the log is what reflows when the
/// window resizes, because a column of numbers has a natural size and a wall
/// of text does not.
///
/// The body is [StatsPanel] verbatim — the same widget `adb_files` shows —
/// including its own CPU history chart. An earlier version drew a second
/// sparkline above it, which duplicated the reading, collided with the header,
/// and would have been free to disagree with the panel underneath it.
class VitalsRail extends StatelessWidget {
  const VitalsRail({
    required this.stats,
    required this.cpuHistory,
    this.error,
    super.key,
  });

  final DeviceStats? stats;

  /// Passed through to [StatsPanel], which owns the chart.
  final List<double> cpuHistory;

  /// Non-null when sampling failed. The log keeps running regardless — this is
  /// the fragile half of the window and must not take the useful half with it.
  final Object? error;

  static const width = 268.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: width,
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                Text('Vitals', style: theme.textTheme.titleSmall),
                const Spacer(),
                if (stats != null)
                  Text(
                    _age(stats!.sampledAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.disabledColor,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Vitals unavailable.\n\n$error',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            )
          else
            Expanded(
              child: StatsPanel(stats: stats, cpuHistory: cpuHistory),
            ),
        ],
      ),
    );
  }

  static String _age(DateTime at) {
    final seconds = DateTime.now().difference(at).inSeconds;
    return seconds <= 1 ? 'live' : '${seconds}s ago';
  }
}
