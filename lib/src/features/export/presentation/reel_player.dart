import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/clip/presentation/clip_player.dart';
import 'package:status_studio/src/features/library/domain/recent_reel.dart';
import 'package:status_studio/src/theme/app_theme.dart';
import 'package:video_player/video_player.dart';

/// The exported reel, played as it will be saved or shared (spec FR-10).
/// Tap to play or pause, drag the bar to seek; it goes back to the start
/// when it ends. [fallback]
/// shows until the file opens, and stays if it won't open.
class ReelPlayer extends ConsumerStatefulWidget {
  const ReelPlayer({super.key, required this.reel, required this.fallback});

  final RecentReel reel;
  final Widget fallback;

  @override
  ConsumerState<ReelPlayer> createState() => _ReelPlayerState();
}

class _ReelPlayerState extends ConsumerState<ReelPlayer> {
  late final VideoPlayerController _player = ref.read(
    videoPlayerFactoryProvider,
  )(File(widget.reel.videoPath));
  var _ready = false;

  @override
  void initState() {
    super.initState();
    _player.addListener(_rewindAtEnd);
    unawaited(_open());
  }

  /// A file that won't open keeps the thumbnail: Save and Share still work.
  Future<void> _open() async {
    try {
      await _player.initialize();
    } on Object {
      return;
    }
    if (mounted) {
      setState(() => _ready = true);
    }
  }

  void _rewindAtEnd() {
    if (_player.value.isCompleted) {
      unawaited(_player.seekTo(Duration.zero));
    }
  }

  @override
  void dispose() {
    _player.removeListener(_rewindAtEnd);
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return widget.fallback;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _togglePlay,
      child: Stack(
        fit: StackFit.expand,
        children: [
          VideoPlayer(_player),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: _player,
            builder: (context, value, _) =>
                value.isPlaying ? const SizedBox.shrink() : const _PlayBadge(),
          ),
          // Positioned, not Align: a Slider fills any bounded height it is
          // given and centres its track, which would put the bar mid-video
          // and swallow the play/pause tap.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ReelSeekBar(player: _player),
          ),
        ],
      ),
    );
  }

  Future<void> _togglePlay() =>
      _player.value.isPlaying ? _player.pause() : _player.play();
}

/// Shows how far the reel has played; tap or drag it to seek (spec FR-10).
/// A full-height slider rather than `VideoProgressIndicator`, whose 4 px bar
/// was too thin to grab and didn't visibly fill on the phone.
class _ReelSeekBar extends StatelessWidget {
  const _ReelSeekBar({required this.player});

  final VideoPlayerController player;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: player,
      builder: (context, value, _) {
        final durationMilliseconds = value.duration.inMilliseconds;
        if (durationMilliseconds <= 0) {
          return const SizedBox.shrink();
        }
        final playedMilliseconds = value.position.inMilliseconds.clamp(
          0,
          durationMilliseconds,
        );
        return Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: _trackInset),
                child: _OutlinedTrack(
                  playedFraction: playedMilliseconds / durationMilliseconds,
                ),
              ),
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                overlayShape: SliderComponentShape.noOverlay,
                // The outline and fill are drawn by _OutlinedTrack, as on
                // Fine-tune's seek bar.
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
                thumbColor: context.palette.accent,
              ),
              child: Slider(
                value: playedMilliseconds.toDouble(),
                max: durationMilliseconds.toDouble(),
                semanticFormatterCallback: (_) => 'Seek',
                onChanged: (milliseconds) => unawaited(
                  player.seekTo(Duration(milliseconds: milliseconds.round())),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

const _trackInset = 10.0;
const _trackHeight = 8.0;

/// The whole reel as an outline, filled up to the played position.
class _OutlinedTrack extends StatelessWidget {
  const _OutlinedTrack({required this.playedFraction});

  final double playedFraction;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(_trackHeight / 2);
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        height: _trackHeight,
        width: double.infinity,
        child: DecoratedBox(
          // Fixed light colour: the track sits on the video in both themes.
          decoration: BoxDecoration(
            borderRadius: shape,
            border: Border.all(color: PictureMarkColors.light),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: playedFraction.clamp(0, 1),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.palette.accent,
                borderRadius: shape,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayBadge extends StatelessWidget {
  const _PlayBadge();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: PictureMarkColors.scrim.withValues(alpha: 0.55),
          shape: BoxShape.circle,
        ),
        child: const Padding(
          padding: EdgeInsets.all(14),
          // Fixed light colour: the scrim is black in both themes, and the
          // theme's icon colour is dark in the light theme.
          child: Icon(
            Icons.play_arrow_rounded,
            size: 40,
            color: PictureMarkColors.light,
          ),
        ),
      ),
    );
  }
}
