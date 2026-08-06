import 'dart:math' as math;

import 'package:adb_ui/adb_ui.dart';
import 'package:flutter/material.dart';

import '../stats_service.dart';

/// Dashboard of the latest [DeviceStats], with a rolling CPU sparkline.
class StatsPanel extends StatelessWidget {
  const StatsPanel({
    required this.stats,
    this.cpuHistory = const [],
    super.key,
  });

  final DeviceStats? stats;

  /// Recent overall-CPU readings, oldest first.
  final List<double> cpuHistory;

  @override
  Widget build(BuildContext context) {
    final current = stats;
    if (current == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CpuCard(stats: current, history: cpuHistory),
          const SizedBox(height: 12),
          _MemoryCard(stats: current),
          const SizedBox(height: 12),
          _BatteryCard(stats: current),
          if (current.uptime != null) ...[
            const SizedBox(height: 12),
            _Tile(
              label: 'Uptime',
              value: formatDuration(current.uptime!),
            ),
          ],
        ],
      ),
    );
  }
}

class _CpuCard extends StatelessWidget {
  const _CpuCard({required this.stats, required this.history});

  final DeviceStats stats;
  final List<double> history;

  @override
  Widget build(BuildContext context) {
    final overall = stats.cpu.overall;
    return _Card(
      title: 'CPU',
      // The first sample has no baseline to diff against.
      trailing: Text(
        overall == null ? 'sampling…' : formatPercent(overall),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (history.length > 1)
            SizedBox(
              height: 48,
              child: CustomPaint(
                painter: _SparklinePainter(
                  values: history,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          if (stats.cpu.perCore.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < stats.cpu.perCore.length; i++)
                  _CoreBar(index: i, usage: stats.cpu.perCore[i]),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CoreBar extends StatelessWidget {
  const _CoreBar({required this.index, required this.usage});

  final int index;
  final double? usage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 56,
      child: Column(
        children: [
          Text('$index', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          LinearProgressIndicator(
            value: usage ?? 0,
            minHeight: 6,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
          const SizedBox(height: 2),
          Text(
            formatPercent(usage),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({required this.stats});

  final DeviceStats stats;

  @override
  Widget build(BuildContext context) {
    final memory = stats.memory;
    return _Card(
      title: 'Memory',
      trailing: Text(
        '${formatBytes(memory.used)} / ${formatBytes(memory.total)}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(value: memory.usedFraction, minHeight: 8),
          const SizedBox(height: 10),
          Row(
            children: [
              // "Available" is the honest pressure signal; "free" looks
              // alarmingly low on Android because the page cache uses it.
              _Tile(label: 'Available', value: formatBytes(memory.available)),
              _Tile(label: 'Cached', value: formatBytes(memory.cached)),
              if (memory.swapTotal > 0)
                _Tile(
                  label: 'Swap',
                  value: '${formatBytes(memory.swapUsed)} '
                      '(${formatPercent(memory.swapUsedFraction)})',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BatteryCard extends StatelessWidget {
  const _BatteryCard({required this.stats});

  final DeviceStats stats;

  @override
  Widget build(BuildContext context) {
    final battery = stats.battery;
    final scheme = Theme.of(context).colorScheme;

    return _Card(
      title: 'Battery',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (battery.isCharging)
            Icon(Icons.bolt, size: 18, color: scheme.primary),
          Text(
            formatPercent(battery.percent),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
      child: Row(
        children: [
          _Tile(
            label: 'Temperature',
            value: '${battery.temperature.toStringAsFixed(1)} °C',
            // Above ~45 °C the device throttles and measurements stop being
            // comparable, so flag it rather than showing a bare number.
            highlight: battery.isHot,
          ),
          _Tile(label: 'Voltage', value: '${battery.voltage} mV'),
          _Tile(label: 'Health', value: battery.health.name),
          _Tile(label: 'Status', value: battery.status.name),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: highlight ? theme.colorScheme.error : null,
              fontWeight: highlight ? FontWeight.bold : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    // Fixed 0..1 scale rather than auto-scaling to the data: an autoscaled
    // idle device shows dramatic-looking spikes that are actually noise.
    final path = Path();
    final step = size.width / (values.length - 1);
    for (var i = 0; i < values.length; i++) {
      final x = i * step;
      final y = size.height * (1 - values[i].clamp(0.0, 1.0));
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()..color = color.withValues(alpha: 0.15),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values.length != values.length ||
      old.color != color ||
      (values.isNotEmpty && old.values.lastOrNull != values.lastOrNull);
}

/// Keeps the last [capacity] CPU readings for the sparkline.
class CpuHistory {
  CpuHistory({this.capacity = 60});

  final int capacity;
  final List<double> _values = [];

  List<double> get values => List.unmodifiable(_values);

  void add(double? usage) {
    if (usage == null) return;
    _values.add(usage);
    if (_values.length > capacity) {
      _values.removeRange(0, _values.length - capacity);
    }
  }

  double get peak => _values.isEmpty ? 0 : _values.reduce(math.max);

  void clear() => _values.clear();
}
