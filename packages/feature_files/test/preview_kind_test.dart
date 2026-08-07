import 'package:feature_files/feature_files.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('detectPreviewKind', () {
    test('recognises images Flutter can actually decode', () {
      for (final name in ['a.jpg', 'a.JPEG', 'a.png', 'a.gif', 'a.webp']) {
        expect(detectPreviewKind(name), PreviewKind.image, reason: name);
      }
    });

    test('sends HEIC to the binary viewer rather than a broken image box', () {
      // Modern Android cameras produce HEIC and Flutter cannot decode it.
      // Claiming it is an image would render an error placeholder with no
      // explanation; the hex viewer at least says something true.
      expect(detectPreviewKind('IMG_0001.heic'), PreviewKind.binary);
    });

    test('recognises video and audio containers', () {
      expect(detectPreviewKind('clip.mp4'), PreviewKind.video);
      expect(detectPreviewKind('clip.mkv'), PreviewKind.video);
      expect(detectPreviewKind('song.mp3'), PreviewKind.audio);
      expect(detectPreviewKind('song.flac'), PreviewKind.audio);
    });

    test('treats source and config files as text', () {
      for (final name in ['a.dart', 'a.json', 'a.log', 'build.gradle', 'a.yml']) {
        expect(detectPreviewKind(name), PreviewKind.text, reason: name);
      }
    });

    test('an extensionless file is assumed to be text', () {
      // Usually a script or config; showing it as hex would be unhelpful.
      expect(detectPreviewKind('README'), PreviewKind.text);
      expect(detectPreviewKind('Makefile'), PreviewKind.text);
    });

    test('a dotfile is text, not an extension match', () {
      // ".bashrc" has no extension -- "bashrc" is the whole name.
      expect(detectPreviewKind('.bashrc'), PreviewKind.text);
    });

    test('office formats are documents, not binary', () {
      // These have no Flutter renderer, so they route to a platform viewer
      // rather than dumping hex at the user.
      for (final name in ['a.docx', 'a.xlsx', 'a.pptx', 'a.rtf', 'a.epub']) {
        expect(detectPreviewKind(name), PreviewKind.document, reason: name);
      }
    });

    test('pdf is its own kind, separate from other documents', () {
      // PDF has a real cross-platform renderer; the rest do not.
      expect(detectPreviewKind('manual.pdf'), PreviewKind.pdf);
    });

    test('archives are their own kind', () {
      expect(detectPreviewKind('app.apk'), PreviewKind.archive);
      expect(detectPreviewKind('bundle.zip'), PreviewKind.archive);
    });

    test('unknown binary extensions fall through to binary', () {
      expect(detectPreviewKind('firmware.img'), PreviewKind.binary);
      expect(detectPreviewKind('db.sqlite'), PreviewKind.binary);
    });

    test('detection is case-insensitive', () {
      expect(detectPreviewKind('MOVIE.MP4'), PreviewKind.video);
      expect(detectPreviewKind('Photo.PNG'), PreviewKind.image);
    });

    test('only video and audio are marked as streaming', () {
      expect(PreviewKind.video.streams, isTrue);
      expect(PreviewKind.audio.streams, isTrue);
      expect(PreviewKind.image.streams, isFalse);
      expect(PreviewKind.text.streams, isFalse);
    });
  });
}
