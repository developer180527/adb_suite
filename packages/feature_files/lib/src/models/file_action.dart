import 'package:adb_core/adb_core.dart';

/// Every operation the browser can perform on a selection.
///
/// Kept as data rather than being hard-coded into the context menu so the
/// toolbar, keyboard shortcuts, and menu all offer exactly the same set and
/// agree on when each is available.
enum FileAction {
  open('Open', 'Download and open in the default app'),
  openWith('Reveal Download', 'Download and show in the file manager'),
  download('Download…', 'Save a copy locally'),
  rename('Rename…', 'Change the name'),
  duplicate('Duplicate', 'Copy alongside the original'),
  delete('Delete', 'Remove from the device'),
  newFolder('New Folder…', 'Create a folder here'),
  copyPath('Copy Path', 'Copy the device path to the clipboard'),
  refresh('Refresh', 'Re-read this directory'),
  properties('Get Info', 'Show details');

  const FileAction(this.label, this.description);

  final String label;
  final String description;

  /// Whether this action makes sense for the given selection.
  ///
  /// Centralised so a disabled toolbar button and a greyed menu item can never
  /// disagree about what is possible.
  bool isEnabledFor(List<AdbFileEntry> selection) {
    final one = selection.length == 1;
    final any = selection.isNotEmpty;

    return switch (this) {
      // Opening a directory means navigating, which the row tap already does;
      // as an action it only applies to a single file.
      FileAction.open => one && !selection.single.isDirectory,
      FileAction.openWith => one && !selection.single.isDirectory,
      // Folders download recursively, so a mixed selection is fine.
      FileAction.download => any,
      FileAction.rename => one,
      // `cp -r` handles folders, so duplicating one is fine.
      FileAction.duplicate => one,
      FileAction.delete => any,
      FileAction.newFolder => true,
      FileAction.copyPath => any,
      FileAction.refresh => true,
      FileAction.properties => one,
    };
  }

  /// Actions shown when right-clicking a row, in order, with nulls marking
  /// separators.
  static const List<FileAction?> rowMenu = [
    FileAction.open,
    FileAction.openWith,
    FileAction.download,
    null,
    FileAction.rename,
    FileAction.duplicate,
    FileAction.delete,
    null,
    FileAction.copyPath,
    FileAction.properties,
  ];

  /// Actions shown when right-clicking empty space.
  static const List<FileAction?> backgroundMenu = [
    FileAction.newFolder,
    FileAction.refresh,
  ];
}
