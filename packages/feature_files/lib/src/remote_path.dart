/// POSIX path helpers for device paths.
///
/// `package:path` follows the *host* platform's conventions, so on Windows it
/// would build `\`-separated paths for an Android device. Device paths are
/// always POSIX, so they get their own helpers.
class RemotePath {
  const RemotePath._();

  static const root = '/';

  /// Joins [parent] and [name], collapsing duplicate separators.
  static String join(String parent, String name) {
    if (name.startsWith('/')) return normalize(name);
    if (parent.isEmpty || parent == root) return '/$name';
    final base = parent.endsWith('/')
        ? parent.substring(0, parent.length - 1)
        : parent;
    return normalize('$base/$name');
  }

  /// The containing directory. The parent of `/` is `/`.
  static String parent(String path) {
    final normalized = normalize(path);
    if (normalized == root) return root;
    final index = normalized.lastIndexOf('/');
    if (index <= 0) return root;
    return normalized.substring(0, index);
  }

  /// The final component. The basename of `/` is `/`.
  static String basename(String path) {
    final normalized = normalize(path);
    if (normalized == root) return root;
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }

  /// Extension without the dot, lowercased. Empty when there is none.
  ///
  /// A leading dot marks a hidden file, not an extension: `.bashrc` has no
  /// extension.
  static String extension(String path) {
    final name = basename(path);
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  /// Collapses `//`, resolves `.` and `..`, and strips a trailing slash.
  static String normalize(String path) {
    if (path.isEmpty) return root;
    final absolute = path.startsWith('/');
    final parts = <String>[];

    for (final segment in path.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        // Refuse to escape above root -- `/..` is `/`, not a path outside it.
        if (parts.isNotEmpty && parts.last != '..') {
          parts.removeLast();
        } else if (!absolute) {
          parts.add('..');
        }
        continue;
      }
      parts.add(segment);
    }

    if (parts.isEmpty) return absolute ? root : '.';
    return (absolute ? '/' : '') + parts.join('/');
  }

  /// Every ancestor from root down to [path], for a breadcrumb bar.
  static List<String> ancestors(String path) {
    final normalized = normalize(path);
    if (normalized == root) return [root];

    final crumbs = <String>[root];
    final buffer = StringBuffer();
    for (final segment in normalized.split('/').where((s) => s.isNotEmpty)) {
      buffer.write('/$segment');
      crumbs.add(buffer.toString());
    }
    return crumbs;
  }

  /// True when [path] is [ancestor] or sits beneath it.
  static bool isWithin(String ancestor, String path) {
    final a = normalize(ancestor);
    final p = normalize(path);
    if (a == root) return true;
    return p == a || p.startsWith('$a/');
  }

  /// Appends ` (2)`, ` (3)`, … before the extension until the name is unused.
  /// Used when a transfer would overwrite something.
  static String deduplicate(String name, Set<String> taken) {
    if (!taken.contains(name)) return name;

    final dot = name.lastIndexOf('.');
    final hasExtension = dot > 0 && dot < name.length - 1;
    final stem = hasExtension ? name.substring(0, dot) : name;
    final suffix = hasExtension ? name.substring(dot) : '';

    for (var i = 2; ; i++) {
      final candidate = '$stem ($i)$suffix';
      if (!taken.contains(candidate)) return candidate;
    }
  }
}
