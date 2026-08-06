/// Logcat capture, filtering, and display.
///
/// The service streams entries as fast as the device emits them; the
/// controller owns buffering and repaint coalescing. Keeping those separate is
/// what makes ~12,000 lines/second survivable in a UI.
library;

export 'src/log_ring_buffer.dart';
export 'src/logcat_controller.dart';
export 'src/logcat_parser.dart';
export 'src/logcat_service.dart';
export 'src/models/log_filter.dart';
export 'src/models/log_level.dart';
export 'src/models/logcat_entry.dart';
export 'src/widgets/logcat_view.dart';
