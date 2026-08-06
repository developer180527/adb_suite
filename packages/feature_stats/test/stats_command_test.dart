import 'package:feature_stats/feature_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StatsService.command shell safety', () {
    test('the delimiter contains no shell comment character', () {
      // Regression: the delimiter was '###ADBSTATS###'. In sh, '#' begins a
      // comment when it starts a word, so `echo ###X###; cat /proc/stat`
      // commented out the entire rest of the line and every section came back
      // empty -- with no error, because echo still exited 0.
      expect(StatsService.delimiter, isNot(contains('#')));
    });

    test('every delimiter echo is single-quoted', () {
      final echoes = RegExp(r'echo\s+(\S+)')
          .allMatches(StatsService.command)
          .map((m) => m.group(1)!)
          .toList();

      expect(echoes, isNotEmpty);
      for (final arg in echoes) {
        expect(
          arg.startsWith("'"),
          isTrue,
          reason: 'unquoted echo argument "$arg" is exposed to shell parsing',
        );
      }
    });

    test('the command carries no unquoted shell metacharacters', () {
      // Strip single-quoted spans, then check what the shell would interpret.
      final unquoted = StatsService.command.replaceAll(RegExp("'[^']*'"), '');
      for (final char in ['#', '`', r'$', '&', '|', '<', '>']) {
        expect(
          unquoted,
          isNot(contains(char)),
          reason: 'unquoted "$char" changes how the shell parses the command',
        );
      }
    });

    test('samples all four sections in the order sample() expects', () {
      // sample() indexes sections positionally, so order is load-bearing.
      final order = ['/proc/stat', '/proc/meminfo', '/proc/uptime', 'dumpsys battery'];
      var cursor = 0;
      for (final needle in order) {
        final at = StatsService.command.indexOf(needle, cursor);
        expect(at, greaterThanOrEqualTo(0), reason: 'missing $needle');
        cursor = at;
      }
    });

    test('has one delimiter per section', () {
      final count = StatsService.delimiter.allMatches(StatsService.command).length;
      expect(count, 4);
    });
  });
}
