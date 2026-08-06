import 'package:adb_core/adb_core.dart';

/// The outcome of listing a directory.
///
/// This type exists because the sync protocol cannot express the difference:
/// `LIST` on a directory the shell user cannot read returns an *empty listing*,
/// not an error (verified on a Galaxy A71 against `/data/data`). Rendering that
/// as an empty folder is a real bug — every locked directory would silently
/// look empty and the user would think their files were gone.
sealed class DirectoryListing {
  const DirectoryListing(this.path);

  final String path;
}

class DirectoryContents extends DirectoryListing {
  const DirectoryContents(super.path, this.entries);

  final List<AdbFileEntry> entries;

  bool get isEmpty => entries.isEmpty;
}

/// The directory exists but is not readable by the shell user.
class DirectoryDenied extends DirectoryListing {
  const DirectoryDenied(super.path);
}

class DirectoryMissing extends DirectoryListing {
  const DirectoryMissing(super.path);
}

/// The path exists but is a file, not a directory.
class DirectoryNotADirectory extends DirectoryListing {
  const DirectoryNotADirectory(super.path);
}

/// Something else went wrong — a transport error, a protocol failure.
class DirectoryFailed extends DirectoryListing {
  const DirectoryFailed(super.path, this.error);

  final Object error;
}
