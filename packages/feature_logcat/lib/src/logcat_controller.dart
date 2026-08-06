import 'dart:async';

import 'package:flutter/foundation.dart';

import 'log_ring_buffer.dart';
import 'logcat_service.dart';
import 'models/log_filter.dart';
import 'models/logcat_entry.dart';

/// Holds the log buffer and drives repaints.
///
/// The core constraint: logcat sustains ~12,000 lines/second on a real device.
/// Notifying listeners per entry would queue tens of thousands of rebuilds per
/// second. Instead, arriving entries accumulate and listeners are notified at
/// most once per [flushInterval], which keeps the frame budget intact while
/// still feeling live.
class LogcatController extends ChangeNotifier {
  LogcatController({
    required LogcatService service,
    int capacity = 50000,
    this.flushInterval = const Duration(milliseconds: 100),
  }) : _service = service,
       _entries = LogRingBuffer<LogcatEntry>(capacity);

  final LogcatService _service;
  final LogRingBuffer<LogcatEntry> _entries;
  final Duration flushInterval;

  StreamSubscription<LogcatEntry>? _subscription;
  Timer? _flushTimer;
  bool _dirty = false;

  LogFilter _filter = LogFilter.empty;
  List<LogcatEntry> _visible = const [];
  bool _paused = false;
  Object? _error;

  /// Entries passing the current filter, oldest first.
  List<LogcatEntry> get visible => _visible;

  LogFilter get filter => _filter;
  bool get isRunning => _subscription != null;
  bool get isPaused => _paused;
  Object? get error => _error;

  int get totalCount => _entries.length;
  int get droppedCount => _entries.droppedCount;

  /// Distinct tags seen so far, for populating a tag filter menu.
  Set<String> get knownTags => {
    for (final entry in _entries)
      if (entry.tag != null) entry.tag!,
  };

  Future<void> start({bool includeExisting = true}) async {
    if (_subscription != null) return;
    _error = null;

    if (includeExisting) {
      try {
        _entries.addAll(await _service.dump(tail: 2000));
        _recomputeVisible();
        notifyListeners();
      } on Object catch (e) {
        _error = e;
        notifyListeners();
      }
    }

    _subscription = _service.watch().listen(
      _onEntry,
      onError: (Object e) {
        _error = e;
        notifyListeners();
      },
      onDone: () {
        _subscription = null;
        notifyListeners();
      },
    );
  }

  /// Stops following. Entries already captured stay in the buffer.
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _flushTimer?.cancel();
    _flushTimer = null;
    notifyListeners();
  }

  /// Freezes the view without dropping the connection, so scrolling back
  /// through history is not fighting a moving list.
  ///
  /// Entries continue to accumulate while paused and appear on resume.
  void setPaused(bool paused) {
    if (_paused == paused) return;
    _paused = paused;
    if (!paused && _dirty) _flush();
    notifyListeners();
  }

  void setFilter(LogFilter filter) {
    if (_filter == filter) return;
    _filter = filter;
    _recomputeVisible();
    notifyListeners();
  }

  /// Clears the local buffer. Does not touch the device-side buffer.
  void clearLocal() {
    _entries.clear();
    _visible = const [];
    notifyListeners();
  }

  /// Clears both the device buffer and the local one.
  Future<void> clearAll() async {
    await _service.clear();
    clearLocal();
  }

  void _onEntry(LogcatEntry entry) {
    _entries.add(entry);
    _dirty = true;
    // Coalesce: schedule one flush and let everything arriving in the window
    // ride along with it.
    _flushTimer ??= Timer(flushInterval, _flush);
  }

  void _flush() {
    _flushTimer = null;
    if (!_dirty || _paused) return;
    _dirty = false;
    _recomputeVisible();
    notifyListeners();
  }

  void _recomputeVisible() {
    if (!_filter.isActive) {
      _visible = _entries.toList(growable: false);
      return;
    }
    // Compile the regex once for the whole pass rather than per entry.
    final regex = _filter.compile();
    _visible = [
      for (final entry in _entries)
        if (_filter.matches(entry, compiledRegex: regex)) entry,
    ];
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
