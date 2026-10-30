import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/clip/domain/clip_playback.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/theme/app_theme.dart';
import 'package:video_player/video_player.dart';

typedef VideoPlayerFactory = VideoPlayerController Function(File source);

/// Creates players, so tests can swap in one that never touches the platform.
final videoPlayerFactoryProvider = Provider<VideoPlayerFactory>(
  (ref) => VideoPlayerController.file,
);

/// Plays [clip] out of [source], from its start, stopping at its end.
class ClipPlayer extends ConsumerStatefulWidget {
  const ClipPlayer({super.key, required this.source, required this.clip});

  final File source;
  final ClipRange clip;

  @override
  ConsumerState<ClipPlayer> createState() => _ClipPlayerState();
}

class _ClipPlayerState extends ConsumerState<ClipPlayer> {
  late final VideoPlayerController _player = ref.read(
    videoPlayerFactoryProvider,
  )(widget.source);

  @override
  void initState() {
    super.initState();
    _player.addListener(_stopAtClipEnd);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _player.initialize();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _player.removeListener(_stopAtClipEnd);
    unawaited(_player.dispose());
    super.dispose();
  }

  void _stopAtClipEnd() {
    final value = _player.value;
    if (value.isPlaying && shouldStopPlayback(value.position, widget.clip)) {
      unawaited(_player.pause());
    }
  }

  Future<void> _togglePlayback() async {
    if (_player.value.isPlaying) {
      await _player.pause();
      return;
    }
    await _player.seekTo(widget.clip.start);
    await _player.play();
  }

  @override
  Widget build(BuildContext context) {
    final value = _player.value;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: value.isInitialized ? value.aspectRatio : 16 / 9,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Positioned.fill(child: ColoredBox(color: AppColors.surface)),
            if (value.isInitialized) VideoPlayer(_player),
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: _player,
              builder: (context, value, _) => _PlayButton(
                playing: value.isPlaying,
                onPressed: value.isInitialized ? _togglePlayback : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.onPressed});

  final bool playing;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      tooltip: playing ? 'Pause' : 'Play clip',
      iconSize: 32,
      onPressed: onPressed,
      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
    );
  }
}
