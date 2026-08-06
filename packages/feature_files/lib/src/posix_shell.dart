/// Shell quoting for arguments interpolated into device commands.
///
/// The sync protocol covers listing, stat, and transfer, but has no delete,
/// mkdir, rename, or copy — those must go through `sh` on the device. That
/// means filenames, which are arbitrary user data, end up inside a command
/// string.
///
/// Android filenames legitimately contain spaces, quotes, `$`, backticks,
/// semicolons, and newlines. Without correct quoting these break the command
/// at best, and at worst execute part of a filename. A file literally named
/// `; rm -rf /sdcard` must be deletable without deleting anything else.
class PosixShell {
  const PosixShell._();

  /// Wraps [value] so the shell treats it as one literal argument.
  ///
  /// Uses single quotes, inside which every character is literal. The only
  /// character needing care is `'` itself, which cannot appear inside a
  /// single-quoted string — it is closed, escaped, and reopened, producing the
  /// standard `'\''` sequence.
  static String quote(String value) {
    if (value.isEmpty) return "''";

    // Fast path: an unambiguously safe argument needs no quoting. Kept
    // deliberately narrow -- anything outside this set gets quoted.
    if (_safe.hasMatch(value)) return value;

    return "'${value.replaceAll("'", r"'\''")}'";
  }

  /// Quotes several arguments and joins them with spaces.
  static String quoteAll(Iterable<String> values) =>
      values.map(quote).join(' ');

  static final _safe = RegExp(r'^[A-Za-z0-9_@%+=:,./-]+$');
}
