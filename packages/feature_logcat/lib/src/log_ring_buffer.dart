import 'dart:collection';

/// Fixed-capacity circular buffer.
///
/// Logcat on a real device sustains roughly 12,000 lines/second (measured on a
/// Galaxy A71). An unbounded list grows without limit and a `List.removeAt(0)`
/// is O(n) per line, so both approaches fall over within seconds. This keeps
/// append and eviction at O(1) and memory flat.
class LogRingBuffer<T> extends IterableBase<T> {
  LogRingBuffer(this.capacity)
    : assert(capacity > 0, 'capacity must be positive'),
      _slots = List<T?>.filled(capacity, null);

  final int capacity;
  final List<T?> _slots;

  /// Index of the next write.
  int _head = 0;
  int _length = 0;

  /// Total ever added, including evicted entries. Useful for "N dropped".
  int _totalAdded = 0;

  @override
  int get length => _length;
  int get totalAdded => _totalAdded;
  int get droppedCount => _totalAdded - _length;
  bool get isFull => _length == capacity;

  void add(T value) {
    _slots[_head] = value;
    _head = (_head + 1) % capacity;
    if (_length < capacity) _length++;
    _totalAdded++;
  }

  void addAll(Iterable<T> values) {
    for (final value in values) {
      add(value);
    }
  }

  /// Oldest-first indexing, so index 0 is the top of the log view.
  T operator [](int index) {
    if (index < 0 || index >= _length) {
      throw RangeError.index(index, this, 'index', null, _length);
    }
    final start = (_head - _length + capacity) % capacity;
    return _slots[(start + index) % capacity] as T;
  }

  void clear() {
    _slots.fillRange(0, capacity, null);
    _head = 0;
    _length = 0;
    _totalAdded = 0;
  }

  @override
  Iterator<T> get iterator => _RingIterator<T>(this);
}

class _RingIterator<T> implements Iterator<T> {
  _RingIterator(this._buffer);

  final LogRingBuffer<T> _buffer;
  int _index = -1;

  @override
  T get current => _buffer[_index];

  @override
  bool moveNext() => ++_index < _buffer.length;
}
