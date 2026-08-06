import 'package:feature_files/feature_files.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PosixShell.quote', () {
    test('leaves an unambiguously safe path unquoted', () {
      expect(PosixShell.quote('/sdcard/Download'), '/sdcard/Download');
      expect(PosixShell.quote('file_name-1.2.txt'), 'file_name-1.2.txt');
    });

    test('quotes an empty string so it stays a real argument', () {
      // Bare empty text would vanish from the command and shift every
      // subsequent argument left.
      expect(PosixShell.quote(''), "''");
    });

    test('quotes spaces', () {
      expect(PosixShell.quote('/sdcard/My Files'), "'/sdcard/My Files'");
    });

    test('neutralises command separators', () {
      // A file really can be named this. It must be treated as a name.
      expect(
        PosixShell.quote('; rm -rf /sdcard'),
        "'; rm -rf /sdcard'",
      );
      expect(PosixShell.quote('a && b'), "'a && b'");
      expect(PosixShell.quote('a | b'), "'a | b'");
    });

    test('neutralises command substitution', () {
      expect(PosixShell.quote(r'$(whoami)'), r"'$(whoami)'");
      expect(PosixShell.quote('`id`'), "'`id`'");
      expect(PosixShell.quote(r'${HOME}'), r"'${HOME}'");
    });

    test('neutralises globs so they are not expanded', () {
      expect(PosixShell.quote('*.jpg'), "'*.jpg'");
      expect(PosixShell.quote('file?.txt'), "'file?.txt'");
      expect(PosixShell.quote('[abc].txt'), "'[abc].txt'");
    });

    test('neutralises the comment character', () {
      // Precisely the bug that silently emptied the stats command.
      expect(PosixShell.quote('#notes.txt'), "'#notes.txt'");
    });

    test('escapes an embedded single quote', () {
      // Single quotes cannot nest, so the string is closed, the quote is
      // escaped, and the string reopens: it's -> 'it'\''s'
      expect(PosixShell.quote("it's"), r"'it'\''s'");
    });

    test('handles a name that is only quotes', () {
      expect(PosixShell.quote("'"), r"''\'''");
      expect(PosixShell.quote("''"), r"''\'''\'''");
    });

    test('handles a double quote without special-casing it', () {
      expect(PosixShell.quote('say "hi"'), '\'say "hi"\'');
    });

    test('quotes newlines and tabs', () {
      expect(PosixShell.quote('line1\nline2'), "'line1\nline2'");
      expect(PosixShell.quote('a\tb'), "'a\tb'");
    });

    test('quotes non-ASCII names', () {
      // Safe for the shell, but outside the conservative unquoted set, so
      // they get quoted rather than passed through.
      expect(PosixShell.quote('写真.jpg'), "'写真.jpg'");
      expect(PosixShell.quote('café 🎉.txt'), "'café 🎉.txt'");
    });

    test('a leading dash stays inside quotes so it is not read as a flag',
        () {
      expect(PosixShell.quote('-rf'), '-rf');
      // The conservative set allows a bare dash, so callers must place `--`
      // before user paths; verify quoting at least does not make it worse.
      expect(PosixShell.quote('- weird name'), "'- weird name'");
    });

    test('quoteAll joins several arguments', () {
      expect(
        PosixShell.quoteAll(['/a b', 'c;d']),
        "'/a b' 'c;d'",
      );
    });
  });

  group('quoting round trip', () {
    // What `sh` does with a single-quoted string: everything between the
    // quotes is literal, and '\'' is the escape for a quote.
    String shellInterpret(String quoted) {
      final buffer = StringBuffer();
      var i = 0;
      var inQuotes = false;
      while (i < quoted.length) {
        final ch = quoted[i];
        if (ch == "'") {
          inQuotes = !inQuotes;
          i++;
        } else if (ch == r'\' && !inQuotes && i + 1 < quoted.length) {
          buffer.write(quoted[i + 1]);
          i += 2;
        } else {
          buffer.write(ch);
          i++;
        }
      }
      return buffer.toString();
    }

    test('every hostile name survives quoting unchanged', () {
      const names = [
        'simple.txt',
        'with space.txt',
        "it's mine.txt",
        r'$(rm -rf /).txt',
        '; echo pwned',
        '`id`.txt',
        '写真 🎉.jpg',
        '--flag-looking',
        "quote'in'middle",
        'tab\there',
        '*',
        '',
      ];

      for (final name in names) {
        expect(
          shellInterpret(PosixShell.quote(name)),
          name,
          reason: 'round trip failed for "$name"',
        );
      }
    });
  });
}
