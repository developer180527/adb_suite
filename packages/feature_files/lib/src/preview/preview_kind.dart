import '../remote_path.dart';

/// How a file should be previewed.
enum PreviewKind {
  image,
  video,
  audio,
  text,
  pdf,

  /// Office and rich-text formats. No Flutter renderer exists for these, so
  /// they depend on an injected platform viewer (macOS QuickLook) and fall
  /// back to "open externally" elsewhere.
  document,

  archive,

  /// No viewer — falls back to the hex dump.
  binary;

  bool get streams => this == video || this == audio;
}

/// Extensions that reliably decode in Flutter's image pipeline.
///
/// HEIC is excluded on purpose: it is what modern Android cameras produce, but
/// Flutter cannot decode it, so it goes to the binary viewer with an honest
/// message rather than rendering a broken image box.
const _imageExtensions = {
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp',
};

const _videoExtensions = {
  'mp4', 'm4v', 'mkv', 'webm', 'mov', 'avi', '3gp', 'flv', 'ts',
};

const _audioExtensions = {
  'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus', 'amr', 'mid',
};

/// Anything a monospace viewer can usefully show. Deliberately broad — a file
/// with no extension at all is still worth trying as text.
const _textExtensions = {
  'txt', 'log', 'md', 'json', 'xml', 'yaml', 'yml', 'ini', 'conf', 'cfg',
  'csv', 'tsv', 'html', 'htm', 'css', 'js', 'ts', 'dart', 'java', 'kt',
  'kts', 'py', 'rb', 'go', 'rs', 'c', 'h', 'cpp', 'hpp', 'cs', 'swift',
  'sh', 'bash', 'zsh', 'sql', 'toml', 'properties', 'gradle', 'pro',
  'gitignore', 'env', 'lock', 'patch', 'diff',
};

/// Formats macOS QuickLook can render but Flutter cannot.
const _documentExtensions = {
  'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
  'pages', 'numbers', 'key', 'rtf', 'odt', 'ods', 'odp', 'epub',
};

const _archiveExtensions = {
  'zip', 'apk', 'jar', 'aar', 'ipa', 'aab',
};

PreviewKind detectPreviewKind(String name) {
  final extension = RemotePath.extension(name);

  if (_imageExtensions.contains(extension)) return PreviewKind.image;
  if (_videoExtensions.contains(extension)) return PreviewKind.video;
  if (_audioExtensions.contains(extension)) return PreviewKind.audio;
  if (_textExtensions.contains(extension)) return PreviewKind.text;
  if (extension == 'pdf') return PreviewKind.pdf;
  if (_documentExtensions.contains(extension)) return PreviewKind.document;
  if (_archiveExtensions.contains(extension)) return PreviewKind.archive;

  // Dotfiles and extensionless files are usually configuration or scripts.
  if (extension.isEmpty) return PreviewKind.text;

  return PreviewKind.binary;
}

/// Largest slice a text viewer will pull up front.
///
/// Logs on a device are routinely hundreds of megabytes; rendering one whole
/// would hang the UI and pull it over the wire for no benefit. The viewer
/// reads a window and says so.
const int kTextPreviewWindow = 256 * 1024;

/// How much of a file the hex viewer shows per page.
const int kHexPageSize = 4 * 1024;
