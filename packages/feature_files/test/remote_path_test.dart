import 'package:feature_files/feature_files.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalize', () {
    test('collapses duplicate separators', () {
      expect(RemotePath.normalize('/sdcard//Download'), '/sdcard/Download');
    });

    test('strips a trailing slash', () {
      expect(RemotePath.normalize('/sdcard/Download/'), '/sdcard/Download');
    });

    test('resolves . and ..', () {
      expect(RemotePath.normalize('/sdcard/./Download'), '/sdcard/Download');
      expect(RemotePath.normalize('/sdcard/DCIM/../Download'), '/sdcard/Download');
    });

    test('refuses to escape above root', () {
      // `/..` must stay at root; letting it climb out would let a crafted
      // path address the whole filesystem from a sandboxed start point.
      expect(RemotePath.normalize('/..'), '/');
      expect(RemotePath.normalize('/../../etc'), '/etc');
    });

    test('empty and root normalize to root', () {
      expect(RemotePath.normalize(''), '/');
      expect(RemotePath.normalize('/'), '/');
    });
  });

  group('join', () {
    test('joins a name onto a directory', () {
      expect(RemotePath.join('/sdcard', 'a.txt'), '/sdcard/a.txt');
    });

    test('does not double the separator', () {
      expect(RemotePath.join('/sdcard/', 'a.txt'), '/sdcard/a.txt');
    });

    test('joining onto root gives a single slash', () {
      expect(RemotePath.join('/', 'sdcard'), '/sdcard');
    });

    test('an absolute name replaces the parent', () {
      expect(RemotePath.join('/sdcard', '/etc/hosts'), '/etc/hosts');
    });
  });

  group('parent and basename', () {
    test('splits a normal path', () {
      expect(RemotePath.parent('/sdcard/DCIM/a.jpg'), '/sdcard/DCIM');
      expect(RemotePath.basename('/sdcard/DCIM/a.jpg'), 'a.jpg');
    });

    test('root is its own parent', () {
      expect(RemotePath.parent('/'), '/');
      expect(RemotePath.basename('/'), '/');
    });

    test('a top-level entry has root as its parent', () {
      expect(RemotePath.parent('/sdcard'), '/');
      expect(RemotePath.basename('/sdcard'), 'sdcard');
    });

    test('a trailing slash does not produce an empty basename', () {
      expect(RemotePath.basename('/sdcard/DCIM/'), 'DCIM');
    });
  });

  group('extension', () {
    test('returns the lowercased extension', () {
      expect(RemotePath.extension('/a/PHOTO.JPG'), 'jpg');
    });

    test('a dotfile has no extension', () {
      // .bashrc is a hidden file, not a file of type "bashrc".
      expect(RemotePath.extension('/home/.bashrc'), '');
    });

    test('a trailing dot is not an extension', () {
      expect(RemotePath.extension('/a/name.'), '');
    });

    test('uses the last dot', () {
      expect(RemotePath.extension('/a/archive.tar.gz'), 'gz');
    });

    test('no dot means no extension', () {
      expect(RemotePath.extension('/a/README'), '');
    });
  });

  group('ancestors', () {
    test('builds a breadcrumb trail from root', () {
      expect(RemotePath.ancestors('/sdcard/DCIM/Camera'), [
        '/',
        '/sdcard',
        '/sdcard/DCIM',
        '/sdcard/DCIM/Camera',
      ]);
    });

    test('root alone is a single crumb', () {
      expect(RemotePath.ancestors('/'), ['/']);
    });
  });

  group('isWithin', () {
    test('recognises descendants', () {
      expect(RemotePath.isWithin('/sdcard', '/sdcard/DCIM'), isTrue);
      expect(RemotePath.isWithin('/sdcard', '/sdcard'), isTrue);
    });

    test('rejects siblings and prefix look-alikes', () {
      expect(RemotePath.isWithin('/sdcard', '/data'), isFalse);
      // The dangerous case: string-prefix matching would call this a child.
      expect(RemotePath.isWithin('/sdcard', '/sdcard2/x'), isFalse);
    });

    test('everything is within root', () {
      expect(RemotePath.isWithin('/', '/anything/here'), isTrue);
    });
  });

  group('deduplicate', () {
    test('leaves an unused name alone', () {
      expect(RemotePath.deduplicate('a.txt', {'b.txt'}), 'a.txt');
    });

    test('inserts the counter before the extension', () {
      expect(RemotePath.deduplicate('a.txt', {'a.txt'}), 'a (2).txt');
    });

    test('keeps counting past existing duplicates', () {
      expect(
        RemotePath.deduplicate('a.txt', {'a.txt', 'a (2).txt'}),
        'a (3).txt',
      );
    });

    test('appends to an extensionless name', () {
      expect(RemotePath.deduplicate('README', {'README'}), 'README (2)');
    });

    test('treats a dotfile as extensionless', () {
      expect(RemotePath.deduplicate('.env', {'.env'}), '.env (2)');
    });
  });
}
