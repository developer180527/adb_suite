import 'package:feature_logcat/feature_logcat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LogRingBuffer', () {
    test('keeps insertion order before wrapping', () {
      final buffer = LogRingBuffer<int>(5)..addAll([1, 2, 3]);
      expect(buffer.toList(), [1, 2, 3]);
      expect(buffer.length, 3);
      expect(buffer.isFull, isFalse);
    });

    test('evicts oldest first once full', () {
      final buffer = LogRingBuffer<int>(3)..addAll([1, 2, 3, 4, 5]);
      expect(buffer.toList(), [3, 4, 5]);
      expect(buffer.length, 3);
      expect(buffer.isFull, isTrue);
    });

    test('tracks how many entries were dropped', () {
      final buffer = LogRingBuffer<int>(3)..addAll([1, 2, 3, 4, 5]);
      expect(buffer.totalAdded, 5);
      expect(buffer.droppedCount, 2);
    });

    test('indexes oldest-first across the wrap point', () {
      final buffer = LogRingBuffer<int>(3)..addAll([1, 2, 3, 4]);
      expect(buffer[0], 2);
      expect(buffer[1], 3);
      expect(buffer[2], 4);
    });

    test('rejects out-of-range indices', () {
      final buffer = LogRingBuffer<int>(3)..add(1);
      expect(() => buffer[1], throwsRangeError);
      expect(() => buffer[-1], throwsRangeError);
    });

    test('clear resets length and counters', () {
      final buffer = LogRingBuffer<int>(3)..addAll([1, 2, 3, 4]);
      buffer.clear();
      expect(buffer.length, 0);
      expect(buffer.droppedCount, 0);
      expect(buffer.toList(), isEmpty);
    });

    test('a capacity-1 buffer keeps only the newest', () {
      final buffer = LogRingBuffer<int>(1)..addAll([1, 2, 3]);
      expect(buffer.toList(), [3]);
    });

    test('rejects a non-positive capacity', () {
      expect(() => LogRingBuffer<int>(0), throwsA(isA<AssertionError>()));
    });

    test('stays flat in memory and fast under sustained load', () {
      // Roughly one second of real logcat output on a Galaxy A71.
      final buffer = LogRingBuffer<int>(50000);
      final watch = Stopwatch()..start();
      for (var i = 0; i < 120000; i++) {
        buffer.add(i);
      }
      watch.stop();

      expect(buffer.length, 50000);
      expect(buffer.first, 70000); // oldest surviving entry
      expect(buffer.last, 119999);
      // A List.removeAt(0) implementation takes minutes to do this.
      expect(watch.elapsedMilliseconds, lessThan(1000));
    });
  });
}
