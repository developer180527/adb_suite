import 'dart:async';
import 'dart:io';

import 'package:adb_core/adb_core.dart';
import 'package:feature_files/feature_files.dart';
import 'package:flutter/material.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

/// Accepts files dragged in from Finder and uploads them to the current
/// directory.
class UploadDropTarget extends StatefulWidget {
  const UploadDropTarget({
    required this.child,
    required this.onFilesDropped,
    required this.destinationLabel,
    super.key,
  });

  final Widget child;
  final void Function(List<String> localPaths) onFilesDropped;

  /// Shown in the drop overlay so the user knows where files will land.
  final String destinationLabel;

  @override
  State<UploadDropTarget> createState() => _UploadDropTargetState();
}

class _UploadDropTargetState extends State<UploadDropTarget> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DropRegion(
      formats: const [Formats.fileUri],
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: (event) {
        final hasFiles = event.session.items.any(
          (item) => item.canProvide(Formats.fileUri),
        );
        if (hasFiles != _hovering) setState(() => _hovering = hasFiles);
        return hasFiles ? DropOperation.copy : DropOperation.none;
      },
      onDropLeave: (_) => setState(() => _hovering = false),
      onPerformDrop: (event) async {
        setState(() => _hovering = false);

        final paths = <String>[];
        for (final item in event.session.items) {
          final reader = item.dataReader;
          if (reader == null) continue;

          final completer = Completer<String?>();
          reader.getValue<Uri>(Formats.fileUri, (uri) {
            completer.complete(uri?.toFilePath());
          }, onError: (_) => completer.complete(null));

          final path = await completer.future;
          if (path != null) paths.add(path);
        }

        if (paths.isNotEmpty) widget.onFilesDropped(paths);
      },
      child: Stack(
        children: [
          widget.child,
          if (_hovering)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.colorScheme.primary,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.upload_file),
                          const SizedBox(width: 10),
                          Text('Copy to ${widget.destinationLabel}'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Makes a file row draggable out to Finder.
///
/// The file is fetched to the local cache when the drag *starts*, and the
/// cached path is then handed over as a plain file URI.
///
/// The nicer design would be a virtual file, downloading only once the user
/// actually drops. That is not available here: `DataWriterItem.addVirtualFile`
/// asserts on `virtualFileSupported`, which is false on macOS even though the
/// documentation says drag-and-drop virtual files work there. Revisit if that
/// assert is relaxed upstream.
///
/// Consequence: dragging a large uncached file pauses at drag start for the
/// length of the transfer (~32 MB/s over USB). Small files are imperceptible;
/// a big video is not. [onFetchStart] lets the UI say something about it.
class DraggableFileRow extends StatelessWidget {
  const DraggableFileRow({
    required this.entry,
    required this.opener,
    required this.child,
    this.onFetchStart,
    this.onFetchEnd,
    super.key,
  });

  final AdbFileEntry entry;
  final FileOpener opener;
  final Widget child;
  final void Function(AdbFileEntry)? onFetchStart;
  final void Function(AdbFileEntry, Object? error)? onFetchEnd;

  @override
  Widget build(BuildContext context) {
    // Directories need a recursive pull, which is not supported yet, so they
    // are simply not draggable rather than failing part-way through a drop.
    if (entry.isDirectory) return child;

    return DragItemWidget(
      allowedOperations: () => const [DropOperation.copy],
      dragItemProvider: (request) async {
        final alreadyCached = opener.isFresh(entry);
        if (!alreadyCached) onFetchStart?.call(entry);

        try {
          final file = await opener.ensureLocal(entry);
          if (!alreadyCached) onFetchEnd?.call(entry, null);

          final item = DragItem(
            localData: {'remotePath': entry.path},
            suggestedName: entry.name,
          );
          item.add(Formats.fileUri(file.uri));
          return item;
        } on Object catch (e) {
          onFetchEnd?.call(entry, e);
          // Returning null cancels the drag rather than dropping an empty file.
          return null;
        }
      },
      child: DraggableWidget(child: child),
    );
  }
}

/// True when a dropped path is a directory, which needs a recursive push we
/// do not support yet.
bool isLocalDirectory(String path) =>
    FileSystemEntity.isDirectorySync(path);
