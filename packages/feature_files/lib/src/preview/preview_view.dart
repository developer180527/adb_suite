import 'package:adb_ui/adb_ui.dart';
import 'package:flutter/material.dart';

import 'preview_controller.dart';
import 'preview_kind.dart';

/// Supplies a viewer for one [PreviewKind].
///
/// Returning null falls back to the built-in viewer for that kind.
///
/// Viewers are injected rather than implemented here so `feature_files` stays
/// free of video-decoding and PDF-rendering dependencies. Those are large
/// native libraries (libmpv, PDFium) that have no business in the iPad build
/// or in a tool that never previews media.
typedef PreviewViewerBuilder = Widget? Function(
  BuildContext context,
  PreviewController controller,
);

/// Renders one previewed file.
class PreviewView extends StatelessWidget {
  const PreviewView({
    required this.controller,
    this.builders = const {},
    this.onOpenExternally,
    super.key,
  });

  final PreviewController controller;

  /// Per-kind overrides. Anything absent uses the built-in viewer.
  final Map<PreviewKind, PreviewViewerBuilder> builders;

  /// "Open in the desktop app" escape hatch, for formats with no viewer.
  final void Function()? onOpenExternally;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.error != null) {
          return _Message(
            icon: Icons.error_outline,
            title: 'Could not preview this file',
            detail: '${controller.error}',
            action: onOpenExternally == null
                ? null
                : ('Open in default app', onOpenExternally!),
          );
        }
        if (controller.isLoading && controller.url == null &&
            controller.text == null && controller.hexBytes == null) {
          return const Center(child: CircularProgressIndicator());
        }

        // An injected viewer wins; otherwise fall back to what is built in.
        final injected = builders[controller.kind]?.call(context, controller);
        if (injected != null) return injected;

        return switch (controller.kind) {
          PreviewKind.image => _ImageViewer(controller: controller),
          PreviewKind.video || PreviewKind.audio => _Message(
            icon: controller.kind == PreviewKind.audio
                ? Icons.audiotrack
                : Icons.movie_outlined,
            title: 'Streaming ready',
            detail: 'This file is served locally and can be streamed without '
                'downloading it.',
            action: onOpenExternally == null
                ? null
                : ('Open in default player', onOpenExternally!),
          ),
          PreviewKind.text => _TextViewer(controller: controller),
          PreviewKind.pdf || PreviewKind.document => _Message(
            icon: Icons.description_outlined,
            title: 'No viewer for this document',
            detail: 'Open it in a desktop app to read it.',
            action: onOpenExternally == null
                ? null
                : ('Open in default app', onOpenExternally!),
          ),
          PreviewKind.archive ||
          PreviewKind.binary => _HexViewer(controller: controller),
        };
      },
    );
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.controller});

  final PreviewController controller;

  @override
  Widget build(BuildContext context) {
    final url = controller.url;
    if (url == null) return const Center(child: CircularProgressIndicator());

    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.25),
      // InteractiveViewer gives pinch/scroll zoom and panning for free.
      child: InteractiveViewer(
        maxScale: 8,
        child: Center(
          child: Image.network(
            url.toString(),
            // Streamed from the device through the local bridge; nothing is
            // written to disk.
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              final total = progress.expectedTotalBytes;
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      value: total == null
                          ? null
                          : progress.cumulativeBytesLoaded / total,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${formatBytes(progress.cumulativeBytesLoaded)}'
                      '${total == null ? "" : " / ${formatBytes(total)}"}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              );
            },
            errorBuilder: (context, error, stack) => _Message(
              icon: Icons.broken_image_outlined,
              title: 'Could not decode this image',
              detail: 'Flutter cannot decode every format Android produces — '
                  'HEIC in particular.',
            ),
          ),
        ),
      ),
    );
  }
}

class _TextViewer extends StatelessWidget {
  const _TextViewer({required this.controller});

  final PreviewController controller;

  @override
  Widget build(BuildContext context) {
    final text = controller.text;
    if (text == null) return const Center(child: CircularProgressIndicator());

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.isTruncated)
          Container(
            color: theme.colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 15, color: theme.hintColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Showing the first ${formatBytes(kTextPreviewWindow)} of '
                    '${formatBytes(controller.size)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: controller.isLoading
                      ? null
                      : controller.loadFullText,
                  child: const Text('Load all'),
                ),
              ],
            ),
          ),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                text,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontFamilyFallback: ['Menlo', 'Consolas', 'monospace'],
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HexViewer extends StatelessWidget {
  const _HexViewer({required this.controller});

  final PreviewController controller;

  @override
  Widget build(BuildContext context) {
    final bytes = controller.hexBytes;
    if (bytes == null) return const Center(child: CircularProgressIndicator());

    final theme = Theme.of(context);
    const perRow = 16;
    final rows = (bytes.length / perRow).ceil();

    return Column(
      children: [
        Container(
          color: theme.colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Offset 0x${controller.hexOffset.toRadixString(16)} of '
                  '${formatBytes(controller.size)}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 18),
                onPressed:
                    controller.canPageBack ? controller.hexPrevious : null,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 18),
                onPressed:
                    controller.canPageForward ? controller.hexNext : null,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: rows,
            itemExtent: 18,
            itemBuilder: (context, row) {
              final start = row * perRow;
              final end = (start + perRow).clamp(0, bytes.length);
              final slice = bytes.sublist(start, end);

              final hex = slice
                  .map((b) => b.toRadixString(16).padLeft(2, '0'))
                  .join(' ')
                  .padRight(perRow * 3 - 1);
              // Non-printable bytes render as '.', the usual hex-dump idiom.
              final ascii = slice
                  .map((b) => b >= 0x20 && b < 0x7F
                      ? String.fromCharCode(b)
                      : '.')
                  .join();

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '${(controller.hexOffset + start).toRadixString(16).padLeft(8, '0')}  '
                  '$hex  $ascii',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontFamilyFallback: ['Menlo', 'Consolas', 'monospace'],
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.detail,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final (String, void Function())? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: theme.disabledColor),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: action!.$2, child: Text(action!.$1)),
            ],
          ],
        ),
      ),
    );
  }
}
