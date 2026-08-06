import 'package:feature_logcat/feature_logcat.dart';
import 'package:flutter_test/flutter_test.dart';

LogcatEntry _entry({
  LogLevel level = LogLevel.info,
  String tag = 'Tag',
  String message = 'message',
  int pid = 100,
}) => LogcatEntry(
  timestamp: DateTime(2026, 8, 6),
  pid: pid,
  tid: pid,
  level: level,
  tag: tag,
  message: message,
  raw: '$tag: $message',
);

void main() {
  group('level threshold', () {
    test('passes entries at or above the minimum', () {
      const filter = LogFilter(minLevel: LogLevel.warn);
      expect(filter.matches(_entry(level: LogLevel.error)), isTrue);
      expect(filter.matches(_entry(level: LogLevel.warn)), isTrue);
      expect(filter.matches(_entry(level: LogLevel.info)), isFalse);
      expect(filter.matches(_entry(level: LogLevel.verbose)), isFalse);
    });

    test('verbose is not treated as an active filter', () {
      expect(const LogFilter().isActive, isFalse);
      expect(const LogFilter(minLevel: LogLevel.debug).isActive, isTrue);
    });
  });

  group('text query', () {
    test('matches message or tag, case-insensitively by default', () {
      const filter = LogFilter(query: 'boot');
      expect(filter.matches(_entry(message: 'Boot completed')), isTrue);
      expect(filter.matches(_entry(tag: 'BootReceiver', message: 'x')), isTrue);
      expect(filter.matches(_entry(message: 'nothing here')), isFalse);
    });

    test('honours case sensitivity when asked', () {
      const filter = LogFilter(query: 'Boot', caseSensitive: true);
      expect(filter.matches(_entry(message: 'Boot done')), isTrue);
      expect(filter.matches(_entry(message: 'boot done')), isFalse);
    });

    test('applies a regex when enabled', () {
      const filter = LogFilter(query: r'^\d+ items$', useRegex: true);
      expect(filter.matches(_entry(message: '42 items')), isTrue);
      expect(filter.matches(_entry(message: 'about 42 items now')), isFalse);
    });

    test('an invalid regex shows everything instead of throwing', () {
      // The user is mid-typing "[abc"; the view must not blow up.
      const filter = LogFilter(query: '[unclosed', useRegex: true);
      expect(() => filter.matches(_entry()), returnsNormally);
      expect(filter.matches(_entry(message: 'anything')), isFalse);
      expect(filter.compile(), isNull);
    });
  });

  group('tag and pid sets', () {
    test('an empty set means no restriction', () {
      expect(const LogFilter().matches(_entry(tag: 'Anything')), isTrue);
    });

    test('restricts to the listed tags', () {
      const filter = LogFilter(tags: {'Wanted'});
      expect(filter.matches(_entry(tag: 'Wanted')), isTrue);
      expect(filter.matches(_entry(tag: 'Other')), isFalse);
    });

    test('restricts to the listed pids', () {
      const filter = LogFilter(pids: {42});
      expect(filter.matches(_entry(pid: 42)), isTrue);
      expect(filter.matches(_entry(pid: 43)), isFalse);
    });
  });

  group('unparsed entries', () {
    final trace = LogcatEntry.unparsed('\tat com.example.Foo.bar(Foo.java:42)');

    test('pass by default so crash output is never hidden', () {
      // A level filter of Error must not swallow the stack trace that follows
      // the error line -- that is precisely what the user is looking for.
      const filter = LogFilter(minLevel: LogLevel.error);
      expect(filter.matches(trace), isTrue);
    });

    test('can be excluded explicitly', () {
      const filter = LogFilter(includeUnparsed: false);
      expect(filter.matches(trace), isFalse);
    });
  });

  group('equality', () {
    test('equal filters compare equal so the view skips recompute', () {
      expect(
        const LogFilter(minLevel: LogLevel.warn, query: 'x'),
        const LogFilter(minLevel: LogLevel.warn, query: 'x'),
      );
    });

    test('set contents matter, not identity', () {
      expect(
        const LogFilter(tags: {'a', 'b'}),
        const LogFilter(tags: {'b', 'a'}),
      );
    });

    test('differing filters are unequal', () {
      expect(
        const LogFilter(query: 'a'),
        isNot(const LogFilter(query: 'b')),
      );
    });
  });
}
