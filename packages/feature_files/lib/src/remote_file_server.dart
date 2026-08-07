import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:adb_core/adb_core.dart';

import 'remote_path.dart';

/// Serves device files over local HTTP so players can stream and seek them.
///
/// A media player cannot read from ADB, but every player already speaks HTTP
/// range requests — that is how web video seeking works. This bridges the two:
/// an incoming `Range` header becomes a [RemoteFile] range read, and the bytes
/// are streamed straight through.
///
/// The point is that **nothing is downloaded**. Scrubbing a two-hour video
/// fetches only the parts actually played, and no copy ever lands on disk.
/// Measured on a Galaxy A71 over USB: ~8.8 MB/s with ~80 ms seek latency,
/// which comfortably carries 1080p.
///
/// ## Access control
///
/// The server binds to loopback only and mints a random token per session.
/// Files must be [publish]ed explicitly and are addressed by opaque handle —
/// device paths never appear in a URL. Without that, any process on the
/// machine could read the whole device through this port.
class RemoteFileServer {
  RemoteFileServer(this._session);

  final AdbSession _session;

  HttpServer? _server;
  late final String _token = _randomToken();
  final Map<String, RemoteFile> _published = {};
  int _nextHandle = 1;

  bool get isRunning => _server != null;
  int? get port => _server?.port;

  Future<void> start() async {
    if (_server != null) return;
    // Port 0 lets the OS pick a free one; loopback only, never 0.0.0.0.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    unawaited(_serve(server));
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _published.clear();
    await server?.close(force: true);
  }

  /// Makes a device file reachable and returns its URL.
  ///
  /// Publishing stats the file once so range requests can be answered without
  /// asking the device for its size again.
  Future<Uri> publish(String remotePath) async {
    await start();
    final file = await RemoteFile.open(_session, remotePath);

    // Reuse the handle if this path is already published, so repeatedly
    // previewing one file does not leak entries.
    for (final entry in _published.entries) {
      if (entry.value.path == file.path) {
        return _urlFor(entry.key, file.path);
      }
    }

    final handle = '${_nextHandle++}';
    _published[handle] = file;
    return _urlFor(handle, file.path);
  }

  void unpublish(Uri url) {
    final handle = _handleOf(url);
    if (handle != null) _published.remove(handle);
  }

  Uri _urlFor(String handle, String path) {
    // The basename is carried as a trailing segment purely so players show a
    // sensible title and infer the type; the handle is what resolves it.
    final name = Uri.encodeComponent(RemotePath.basename(path));
    return Uri.parse('http://127.0.0.1:${_server!.port}/$_token/$handle/$name');
  }

  String? _handleOf(Uri url) {
    final segments = url.pathSegments;
    if (segments.length < 2 || segments[0] != _token) return null;
    return segments[1];
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      // Never let a handler failure take the server down mid-playback.
      unawaited(
        _handle(request).catchError((Object _) async {
          try {
            await request.response.close();
          } on Object {
            // Client already gone.
          }
        }),
      );
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;

    final handle = _handleOf(request.uri);
    final file = handle == null ? null : _published[handle];
    if (file == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    if (request.method != 'GET' && request.method != 'HEAD') {
      response.statusCode = HttpStatus.methodNotAllowed;
      await response.close();
      return;
    }

    response.headers
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.contentTypeHeader, _mimeFor(file.path))
      // These bytes are a live view of the device; caching them would show
      // stale content after the file changes.
      ..set(HttpHeaders.cacheControlHeader, 'no-store');

    final range = _parseRange(
      request.headers.value(HttpHeaders.rangeHeader),
      file.size,
    );

    if (range == null && request.headers.value(HttpHeaders.rangeHeader) != null) {
      // A syntactically valid but unsatisfiable range.
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */${file.size}');
      await response.close();
      return;
    }

    final start = range?.start ?? 0;
    final end = range?.end ?? (file.size == 0 ? 0 : file.size - 1);
    final length = file.size == 0 ? 0 : end - start + 1;

    if (range != null) {
      response.statusCode = HttpStatus.partialContent;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/${file.size}',
      );
    }
    response.headers.contentLength = length;

    // Players issue a HEAD (or a zero-length probe) first to learn the size
    // before deciding how to stream.
    if (request.method == 'HEAD' || length == 0) {
      await response.close();
      return;
    }

    try {
      await response.addStream(file.readStream(start, length));
    } on Object {
      // The player seeked or closed the tab; abandoning the read is normal.
    } finally {
      try {
        await response.close();
      } on Object {
        // Already closed by the client.
      }
    }
  }

  /// Parses a single `bytes=` range. Multi-range requests are not supported;
  /// no media player uses them.
  static ({int start, int end})? _parseRange(String? header, int size) {
    if (header == null || !header.startsWith('bytes=')) return null;
    final spec = header.substring(6).split(',').first.trim();
    if (spec.isEmpty || size == 0) return null;

    final dash = spec.indexOf('-');
    if (dash < 0) return null;

    final startText = spec.substring(0, dash);
    final endText = spec.substring(dash + 1);

    int start;
    int end;

    if (startText.isEmpty) {
      // `bytes=-500` means the *last* 500 bytes.
      final suffix = int.tryParse(endText);
      if (suffix == null || suffix <= 0) return null;
      start = suffix >= size ? 0 : size - suffix;
      end = size - 1;
    } else {
      final parsed = int.tryParse(startText);
      if (parsed == null) return null;
      start = parsed;
      end = endText.isEmpty ? size - 1 : (int.tryParse(endText) ?? size - 1);
    }

    if (start < 0 || start >= size) return null;
    if (end >= size) end = size - 1;
    if (end < start) return null;

    return (start: start, end: end);
  }

  static String _mimeFor(String path) => switch (RemotePath.extension(path)) {
    'mp4' || 'm4v' => 'video/mp4',
    'mkv' => 'video/x-matroska',
    'webm' => 'video/webm',
    'mov' => 'video/quicktime',
    'avi' => 'video/x-msvideo',
    '3gp' => 'video/3gpp',
    'mp3' => 'audio/mpeg',
    'm4a' || 'aac' => 'audio/mp4',
    'wav' => 'audio/wav',
    'flac' => 'audio/flac',
    'ogg' || 'opus' => 'audio/ogg',
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'pdf' => 'application/pdf',
    'txt' || 'log' => 'text/plain; charset=utf-8',
    'json' => 'application/json',
    'xml' => 'application/xml',
    'html' || 'htm' => 'text/html; charset=utf-8',
    _ => 'application/octet-stream',
  };

  static String _randomToken() {
    final random = Random.secure();
    return List.generate(
      24,
      (_) => '0123456789abcdef'[random.nextInt(16)],
    ).join();
  }
}
