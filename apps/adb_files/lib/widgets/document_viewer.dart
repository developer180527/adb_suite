import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Multi-page PDF rendering via PDFium.
///
/// Unlike media, this needs a real file: PDFium reads the cross-reference
/// table at the end and then jumps around, which a forward-only stream cannot
/// serve. PDFs are small enough that a cached copy is a fair trade.
class DevicePdfViewer extends StatelessWidget {
  const DevicePdfViewer({required this.file, super.key});

  final File file;

  @override
  Widget build(BuildContext context) {
    return PdfViewer.file(
      file.path,
      params: const PdfViewerParams(margin: 8),
    );
  }
}

/// Renders documents Flutter cannot, by asking macOS to do it.
///
/// `qlmanage` is the command-line face of QuickLook — the same machinery
/// Finder uses when you press space. It can render Word, Excel, PowerPoint,
/// Pages, Numbers, Keynote, RTF, and EPUB because the OS and installed apps
/// supply the plugins. There is no Flutter renderer for any of those, and
/// writing one is out of the question, so borrowing the platform's is the
/// only realistic way to preview them.
///
/// Two honest limits: it is macOS-only, and it produces a **thumbnail of the
/// first page**, not a scrollable document.
class QuickLookViewer extends StatefulWidget {
  const QuickLookViewer({
    required this.file,
    required this.name,
    this.onOpenExternally,
    super.key,
  });

  final File file;
  final String name;
  final VoidCallback? onOpenExternally;

  /// QuickLook is only available on macOS.
  static bool get isSupported => Platform.isMacOS;

  @override
  State<QuickLookViewer> createState() => _QuickLookViewerState();
}

class _QuickLookViewerState extends State<QuickLookViewer> {
  File? _thumbnail;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_render());
  }

  @override
  void didUpdateWidget(QuickLookViewer old) {
    super.didUpdateWidget(old);
    if (old.file.path != widget.file.path) unawaited(_render());
  }

  Future<void> _render() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final output = await Directory.systemTemp.createTemp('ql');
      // -t renders a thumbnail, -s sets the long edge in points. 2000 is
      // large enough that body text in a Word document stays legible.
      final result = await Process.run('qlmanage', [
        '-t',
        '-s', '2000',
        '-o', output.path,
        widget.file.path,
      ]).timeout(const Duration(seconds: 30));

      // qlmanage exits 0 even when it produces nothing, so the output
      // directory is the real success signal.
      final produced = output
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.png'))
          .toList();

      if (produced.isEmpty) {
        throw StateError(
          'QuickLook produced no preview. '
          '${result.stderr.toString().trim()}',
        );
      }

      if (!mounted) return;
      setState(() {
        _thumbnail = produced.first;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Rendering preview…'),
          ],
        ),
      );
    }

    final thumbnail = _thumbnail;
    if (thumbnail == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.description_outlined,
                size: 44,
                color: theme.disabledColor,
              ),
              const SizedBox(height: 12),
              Text('No preview available', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                'macOS has no QuickLook plugin for this format. Installing the '
                'app that owns it usually adds one.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  '$_error',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.disabledColor,
                  ),
                ),
              ],
              if (widget.onOpenExternally != null) ...[
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: widget.onOpenExternally,
                  child: const Text('Open in default app'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Container(
          color: theme.colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 15, color: theme.hintColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'First-page preview, rendered by macOS QuickLook',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (widget.onOpenExternally != null)
                TextButton(
                  onPressed: widget.onOpenExternally,
                  child: const Text('Open in default app'),
                ),
            ],
          ),
        ),
        Expanded(
          child: ColoredBox(
            color: Colors.black.withValues(alpha: 0.2),
            child: InteractiveViewer(
              maxScale: 6,
              child: Center(
                child: Image.file(thumbnail, filterQuality: FilterQuality.high),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
