import 'dart:async';
import 'dart:convert';

import 'package:adb_core/adb_core.dart';
import 'package:flutter/foundation.dart';

import 'dart:io';

import '../file_opener.dart';
import '../remote_file_server.dart';
import 'preview_kind.dart';

/// Loads whatever a viewer needs for one file, and nothing more.
///
/// The point of the whole preview stack is that a file is *not* downloaded to
/// be looked at:
///  - text reads a window off the front,
///  - hex reads one page at the current offset,
///  - images and media are served over the local HTTP bridge and streamed.
///
/// Only a decoder that genuinely needs the whole file ever pulls it.
class PreviewController extends ChangeNotifier {
  PreviewController({
    required AdbSession session,
    required RemoteFileServer server,
    required this.entry,
    FileOpener? opener,
  }) : _session = session,
       _server = server,
       _opener = opener,
       kind = detectPreviewKind(entry.name);

  final AdbSession _session;
  final RemoteFileServer _server;

  /// Needed only by viewers that cannot stream. PDFium and QuickLook both
  /// require a real path on disk, so those kinds fetch a cached copy.
  final FileOpener? _opener;
  final AdbFileEntry entry;
  final PreviewKind kind;

  RemoteFile? _file;
  Uri? _url;
  File? _localFile;
  String? _text;
  Uint8List? _hex;
  int _hexOffset = 0;
  bool _loading = false;
  bool _truncated = false;
  Object? _error;

  bool get isLoading => _loading;
  Object? get error => _error;

  /// Streaming URL for image and media viewers. Null until [load] finishes.
  Uri? get url => _url;

  /// Cached local copy, for viewers that need a real file. Null for kinds that
  /// stream.
  File? get localFile => _localFile;

  /// Decoded text window, for [PreviewKind.text].
  String? get text => _text;

  /// True when [text] is only the head of a larger file.
  bool get isTruncated => _truncated;

  /// Current hex page.
  Uint8List? get hexBytes => _hex;
  int get hexOffset => _hexOffset;

  int get size => _file?.size ?? entry.size;
  bool get canPageForward => _hexOffset + kHexPageSize < size;
  bool get canPageBack => _hexOffset > 0;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final file = await RemoteFile.open(_session, entry.path);
      _file = file;

      switch (kind) {
        case PreviewKind.image:
        case PreviewKind.video:
        case PreviewKind.audio:
          // Served, not downloaded. The viewer pulls only what it renders.
          _url = await _server.publish(entry.path);

        case PreviewKind.pdf:
        case PreviewKind.document:
          // PDFium and QuickLook both need a path on disk. Documents are
          // small, so a cached copy is a fair trade -- unlike video, where
          // downloading first would defeat the point.
          final opener = _opener;
          if (opener == null) {
            _url = await _server.publish(entry.path);
          } else {
            _localFile = await opener.ensureLocal(entry);
          }

        case PreviewKind.text:
          final window = file.size.clamp(0, kTextPreviewWindow);
          final bytes = await file.read(0, window);
          _truncated = file.size > window;
          // Device files are frequently not valid UTF-8 (logs with binary
          // fragments, latin-1 configs). Replacing bad sequences shows
          // something useful instead of throwing.
          _text = utf8.decode(bytes, allowMalformed: true);

        case PreviewKind.archive:
        case PreviewKind.binary:
          await _loadHexPage(0);
      }
    } on Object catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Loads the whole text file rather than just the head window.
  Future<void> loadFullText() async {
    final file = _file;
    if (file == null || kind != PreviewKind.text) return;

    _loading = true;
    notifyListeners();
    try {
      final bytes = await file.read(0, file.size);
      _text = utf8.decode(bytes, allowMalformed: true);
      _truncated = false;
    } on Object catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> hexPage(int offset) async {
    if (offset < 0 || offset >= size) return;
    await _loadHexPage(offset);
    notifyListeners();
  }

  Future<void> hexNext() => hexPage(_hexOffset + kHexPageSize);
  Future<void> hexPrevious() =>
      hexPage((_hexOffset - kHexPageSize).clamp(0, size));

  Future<void> _loadHexPage(int offset) async {
    final file = _file;
    if (file == null) return;
    _hexOffset = offset;
    _hex = await file.read(offset, kHexPageSize);
  }

  @override
  void dispose() {
    // Release the handle so a closed tab stops being reachable over HTTP.
    final url = _url;
    if (url != null) _server.unpublish(url);
    super.dispose();
  }
}
