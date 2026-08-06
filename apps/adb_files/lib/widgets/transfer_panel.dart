import 'package:adb_ui/adb_ui.dart';
import 'package:feature_files/feature_files.dart';
import 'package:flutter/material.dart';

/// Collapsible transfer queue, docked at the bottom.
class TransferPanel extends StatelessWidget {
  const TransferPanel({
    required this.manager,
    required this.expanded,
    required this.onToggle,
    super.key,
  });

  final TransferManager manager;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: manager,
      builder: (context, _) {
        final jobs = manager.jobs;
        if (jobs.isEmpty) return const SizedBox.shrink();

        final theme = Theme.of(context);
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Header(manager: manager, expanded: expanded, onToggle: onToggle),
              if (expanded)
                ConstrainedBox(
                  // Bounded so a hundred queued files cannot eat the window.
                  constraints: const BoxConstraints(maxHeight: 190),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: jobs.length,
                    itemBuilder: (context, i) => _JobRow(
                      job: jobs[jobs.length - 1 - i], // newest first
                      onCancel: () => manager.cancel(jobs[jobs.length - 1 - i]),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.manager,
    required this.expanded,
    required this.onToggle,
  });

  final TransferManager manager;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = manager.pendingCount;
    final current = manager.current;

    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(expanded ? Icons.expand_more : Icons.expand_less, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                pending == 0
                    ? 'Transfers complete'
                    : current == null
                    ? '$pending queued'
                    : '${current.name}'
                          '${pending > 1 ? "  (+${pending - 1} queued)" : ""}',
                style: theme.textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (manager.isBusy) ...[
              SizedBox(
                width: 120,
                child: LinearProgressIndicator(
                  value: manager.overallFraction,
                  minHeight: 4,
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: manager.cancelAll,
                child: const Text('Cancel all'),
              ),
            ] else
              TextButton(
                onPressed: manager.clearFinished,
                child: const Text('Clear'),
              ),
          ],
        ),
      ),
    );
  }
}

class _JobRow extends StatelessWidget {
  const _JobRow({required this.job, required this.onCancel});

  final TransferJob job;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (icon, color) = switch (job.state) {
      TransferState.completed => (Icons.check_circle, theme.colorScheme.primary),
      TransferState.failed => (Icons.error, theme.colorScheme.error),
      TransferState.cancelled => (Icons.cancel, theme.disabledColor),
      _ => (
        job.direction == TransferDirection.pull
            ? Icons.download
            : Icons.upload,
        theme.colorScheme.onSurfaceVariant,
      ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 5, 8, 5),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  job.name,
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (job.state == TransferState.running) ...[
                  const SizedBox(height: 3),
                  LinearProgressIndicator(value: job.fraction, minHeight: 3),
                ],
                if (job.state == TransferState.failed && job.error != null)
                  Text(
                    '${job.error}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 150,
            child: Text(
              _detail(job),
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall,
            ),
          ),
          SizedBox(
            width: 32,
            child: job.isFinished
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 14),
                    onPressed: onCancel,
                    tooltip: 'Cancel',
                    padding: EdgeInsets.zero,
                  ),
          ),
        ],
      ),
    );
  }

  static String _detail(TransferJob job) {
    switch (job.state) {
      case TransferState.queued:
        return 'Queued';
      case TransferState.cancelled:
        return 'Cancelled';
      case TransferState.failed:
        return 'Failed';
      case TransferState.completed:
        final elapsed = job.finishedAt != null && job.startedAt != null
            ? job.finishedAt!.difference(job.startedAt!)
            : null;
        return elapsed == null
            ? formatBytes(job.bytes)
            : '${formatBytes(job.bytes)} in ${formatDuration(elapsed)}';
      case TransferState.running:
        final rate = job.rate;
        final size = job.total == null
            ? formatBytes(job.bytes)
            : '${formatBytes(job.bytes)} / ${formatBytes(job.total!)}';
        return rate == null ? size : '$size · ${formatRate(rate)}';
    }
  }
}
