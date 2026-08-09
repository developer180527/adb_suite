import 'package:adb_ui/adb_ui.dart';
import 'package:feature_logcat/feature_logcat.dart';
import 'package:feature_stats/feature_stats.dart';
import 'package:flutter/material.dart';

/// Counts along the bottom, in the order they answer questions.
///
/// "How much am I looking at", then "how much is hidden", then "am I losing
/// lines" — the last being the one that quietly invalidates a debugging
/// session if nobody notices it.
class ConsoleStatusBar extends StatelessWidget {
  const ConsoleStatusBar({
    required this.controller,
    this.stats,
    super.key,
  });

  final LogcatController controller;
  final DeviceStats? stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = controller.visible.length;
    final total = controller.totalCount;
    final dropped = controller.droppedCount;
    final filtered = controller.filter.isActive;

    return Container(
      height: 26,
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _Stat(
            label: filtered ? '$visible of $total lines' : '$total lines',
            icon: Icons.subject,
          ),
          if (filtered) ...[
            const SizedBox(width: 14),
            _Stat(
              label: 'filtered',
              icon: Icons.filter_list,
              color: theme.colorScheme.primary,
            ),
          ],
          if (dropped > 0) ...[
            const SizedBox(width: 14),
            // The buffer is a ring, so this is not a warning about the device
            // but about this window: lines that scrolled past capacity are
            // gone, and a conclusion drawn from what remains may be wrong.
            Tooltip(
              message:
                  '$dropped lines fell out of the ring buffer and are no '
                  'longer available. Narrow the filter or pause to keep up.',
              child: _Stat(
                label: '$dropped dropped',
                icon: Icons.report_gmailerrorred_outlined,
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const Spacer(),
          if (controller.error != null) ...[
            _Stat(
              label: 'logcat error',
              icon: Icons.error_outline,
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: 14),
          ],
          if (stats?.uptime case final uptime?) ...[
            _Stat(label: 'up ${_uptime(uptime)}', icon: Icons.schedule),
            const SizedBox(width: 14),
          ],
          if (stats != null)
            _Stat(
              // formatPercent renders a null reading as an em dash, which is
              // the right answer on the first tick.
              label: '${formatPercent(stats!.cpu.overall)} CPU',
              icon: Icons.memory,
            ),
        ],
      ),
    );
  }

  static String _uptime(Duration d) {
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.icon, this.color});

  final String label;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: tint),
        const SizedBox(width: 5),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(color: tint),
        ),
      ],
    );
  }
}
