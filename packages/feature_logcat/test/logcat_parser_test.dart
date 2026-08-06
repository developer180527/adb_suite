import 'package:feature_logcat/feature_logcat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LogcatParser threadtime', () {
    final parser = LogcatParser(now: DateTime(2026, 8, 6, 12));

    test('parses a standard line', () {
      final entry = parser.parse(
        '08-06 10:28:48.123  1234  5678 I ActivityManager: Displayed app',
      );
      expect(entry.isParsed, isTrue);
      expect(entry.pid, 1234);
      expect(entry.tid, 5678);
      expect(entry.level, LogLevel.info);
      expect(entry.tag, 'ActivityManager');
      expect(entry.message, 'Displayed app');
      expect(entry.timestamp, DateTime(2026, 8, 6, 10, 28, 48, 123));
    });

    test('parses every priority letter', () {
      for (final level in LogLevel.values) {
        final entry = parser.parse(
          '08-06 10:28:48.123  1 2 ${level.code} Tag: msg',
        );
        expect(entry.level, level, reason: 'for ${level.code}');
      }
    });

    test('handles a tag containing a colon', () {
      final entry = parser.parse(
        '08-06 10:28:48.123  1234  5678 D com.foo:remote: starting',
      );
      expect(entry.tag, 'com.foo:remote');
      expect(entry.message, 'starting');
    });

    test('handles an empty message', () {
      final entry = parser.parse('08-06 10:28:48.123  1234  5678 I Tag: ');
      expect(entry.isParsed, isTrue);
      expect(entry.message, '');
    });

    test('handles wide pid columns without losing alignment', () {
      final entry = parser.parse(
        '08-06 10:28:48.123 31234 31240 W SomeTag: careful',
      );
      expect(entry.pid, 31234);
      expect(entry.tid, 31240);
      expect(entry.level, LogLevel.warn);
    });
  });

  group('LogcatParser year handling', () {
    test('uses the explicit year from -v year', () {
      final parser = LogcatParser(now: DateTime(2026, 8, 6));
      final entry = parser.parse(
        '2024-03-15 10:28:48.123  1  2 I Tag: old entry',
      );
      expect(entry.timestamp!.year, 2024);
      expect(entry.timestamp!.month, 3);
    });

    test('assumes the current year when the modifier is absent', () {
      final parser = LogcatParser(now: DateTime(2026, 8, 6));
      final entry = parser.parse('03-15 10:28:48.123  1  2 I Tag: msg');
      expect(entry.timestamp!.year, 2026);
    });

    test('rolls back a year for December logs read in January', () {
      // Without this, a December entry read on Jan 2 lands 11 months in the
      // future and sorts to the top of the view.
      final parser = LogcatParser(now: DateTime(2026, 1, 2));
      final entry = parser.parse('12-28 10:28:48.123  1  2 I Tag: msg');
      expect(entry.timestamp!.year, 2025);
      expect(entry.timestamp!.month, 12);
    });

    test('tolerates a day of clock skew without rolling back', () {
      final parser = LogcatParser(now: DateTime(2026, 6, 15, 23, 0));
      final entry = parser.parse('06-16 01:00:00.000  1  2 I Tag: msg');
      expect(entry.timestamp!.year, 2026);
    });
  });

  group('LogcatParser non-entry lines', () {
    final parser = LogcatParser(now: DateTime(2026, 8, 6));

    test('keeps the buffer banner rather than dropping it', () {
      final entry = parser.parse('--------- beginning of main');
      expect(entry.isParsed, isFalse);
      expect(entry.raw, '--------- beginning of main');
    });

    test('keeps stack trace continuation lines', () {
      const line = '\tat com.example.Foo.bar(Foo.java:42)';
      final entry = parser.parse(line);
      expect(entry.isParsed, isFalse);
      expect(entry.isContinuation, isTrue);
      expect(entry.message, line);
    });

    test('an unknown priority letter is not silently mislabelled', () {
      final entry = parser.parse('08-06 10:28:48.123  1  2 X Tag: msg');
      expect(entry.isParsed, isFalse);
    });
  });

  group('LineAssembler', () {
    test('holds a partial line until the rest arrives', () {
      final assembler = LineAssembler();
      // The exact hazard: logcat chunks break on socket boundaries, so a line
      // routinely spans two reads.
      expect(assembler.add('08-06 10:28:48.123  1  2 I Ta'), isEmpty);
      expect(assembler.add('g: hello\n'), [
        '08-06 10:28:48.123  1  2 I Tag: hello',
      ]);
    });

    test('splits several lines in one chunk', () {
      final assembler = LineAssembler();
      expect(assembler.add('one\ntwo\nthree\n'), ['one', 'two', 'three']);
    });

    test('strips carriage returns', () {
      expect(LineAssembler().add('one\r\ntwo\r\n'), ['one', 'two']);
    });

    test('flush returns a trailing fragment with no newline', () {
      final assembler = LineAssembler();
      assembler.add('complete\npartial');
      expect(assembler.flush(), 'partial');
      expect(assembler.flush(), isNull);
    });

    test('a line split one byte at a time still reassembles', () {
      final assembler = LineAssembler();
      const line = 'hello world';
      final out = <String>[];
      for (final ch in '$line\n'.split('')) {
        out.addAll(assembler.add(ch));
      }
      expect(out, [line]);
    });
  });
}
