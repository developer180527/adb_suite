/// Live CPU, memory, and battery statistics for a connected device.
///
/// One batched shell invocation per tick keeps the transport overhead flat and
/// the readings coherent with each other.
library;

export 'src/models/battery_stats.dart';
export 'src/models/cpu_stats.dart';
export 'src/models/memory_stats.dart';
export 'src/stats_parsers.dart';
export 'src/stats_service.dart';
export 'src/widgets/stats_panel.dart';
