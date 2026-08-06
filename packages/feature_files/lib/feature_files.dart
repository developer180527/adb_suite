/// Remote file browsing, transfer, and management.
///
/// Listing, stat, and transfer ride the sync protocol; delete, mkdir, rename,
/// and copy have no sync equivalent and go through the shell with every path
/// quoted by [PosixShell].
library;

export 'src/file_browser_controller.dart';
export 'src/file_service.dart';
export 'src/models/directory_listing.dart';
export 'src/models/file_sort.dart';
export 'src/posix_shell.dart';
export 'src/remote_path.dart';
export 'src/transfer_manager.dart';
export 'src/widgets/file_browser.dart';
export 'src/file_opener.dart';
export 'src/models/file_action.dart';
export 'src/directory_walk.dart';
