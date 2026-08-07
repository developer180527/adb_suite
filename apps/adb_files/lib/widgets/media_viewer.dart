import 'package:adb_ui/adb_ui.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Audio and video playback, streamed from the device.
///
/// libmpv is pointed at the local HTTP bridge rather than a downloaded file,
/// so playback starts as soon as the first bytes arrive and seeking fetches
/// only the part being played. A two-hour video never lands on disk.
class MediaViewer extends StatefulWidget {
  const MediaViewer({
    required this.url,
    required this.isAudio,
    required this.title,
    super.key,
  });

  final Uri url;
  final bool isAudio;
  final String title;

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  late final Player _player;
  VideoController? _video;

  @override
  void initState() {
    super.initState();
    _player = Player();
    if (!widget.isAudio) _video = VideoController(_player);
    // autoPlay is deliberate: opening a media file is an explicit request to
    // watch it, and a preview tab that sits silent looks broken.
    _player.open(Media(widget.url.toString()));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isAudio) {
      final video = _video;
      if (video == null) return const Center(child: CircularProgressIndicator());
      return ColoredBox(
        color: Colors.black,
        child: Video(controller: video, controls: AdaptiveVideoControls),
      );
    }

    return _AudioPlayer(player: _player, title: widget.title);
  }
}

/// Audio has no video surface, so it gets its own transport bar.
class _AudioPlayer extends StatelessWidget {
  const _AudioPlayer({required this.player, required this.title});

  final Player player;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.audiotrack, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 24),
              StreamBuilder<Duration>(
                stream: player.stream.position,
                builder: (context, positionSnapshot) {
                  final position = positionSnapshot.data ?? Duration.zero;
                  return StreamBuilder<Duration>(
                    stream: player.stream.duration,
                    builder: (context, durationSnapshot) {
                      final duration = durationSnapshot.data ?? Duration.zero;
                      final max = duration.inMilliseconds.toDouble();
                      return Column(
                        children: [
                          Slider(
                            // Clamped because position can briefly exceed
                            // duration while libmpv is still probing.
                            value: max <= 0
                                ? 0
                                : position.inMilliseconds
                                      .clamp(0, duration.inMilliseconds)
                                      .toDouble(),
                            max: max <= 0 ? 1 : max,
                            onChanged: max <= 0
                                ? null
                                : (v) => player.seek(
                                    Duration(milliseconds: v.round()),
                                  ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  formatDuration(position),
                                  style: theme.textTheme.bodySmall,
                                ),
                                Text(
                                  formatDuration(duration),
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 8),
              StreamBuilder<bool>(
                stream: player.stream.playing,
                builder: (context, snapshot) {
                  final playing = snapshot.data ?? false;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.replay_10),
                        onPressed: () => player.seek(
                          player.state.position - const Duration(seconds: 10),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        iconSize: 34,
                        icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                        onPressed: player.playOrPause,
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.forward_10),
                        onPressed: () => player.seek(
                          player.state.position + const Duration(seconds: 10),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              // Buffering is visible because the bytes are coming off a phone
              // over USB, not off local disk.
              StreamBuilder<bool>(
                stream: player.stream.buffering,
                builder: (context, snapshot) => SizedBox(
                  height: 20,
                  child: (snapshot.data ?? false)
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Buffering from device…',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
