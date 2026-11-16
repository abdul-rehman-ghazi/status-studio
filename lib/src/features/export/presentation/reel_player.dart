import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  /// A new one each try: a controller that failed to open can't open again.
  VideoPlayerController? _player;
  var _ready = false;

  /// Why the last try to open failed; null while opening or once open.
  Object? _failure;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  /// A file that won't open keeps the thumbnail, with Play to try again
  /// and the player's reason under it (M77): Save and Share still work.
  Future<void> _open() async {
    final player = ref.read(videoPlayerFactoryProvider)(
      File(widget.reel.videoPath),
    );
    _player = player;
    try {
      await player.initialize();
    } on Object catch (failure) {
      _player = null;
      unawaited(player.dispose());
      if (mounted) setState(() => _failure = failure);
      return;
    }
    player.addListener(_rewindAtEnd);
    if (mounted) {
      setState(() => _ready = true);
    }
  }

  void _tryAgain() {
    setState(() => _failure = null);
    unawaited(_open());
  }

  void _rewindAtEnd() {
    final player = _player;
    if (player != null && player.value.isCompleted) {
      unawaited(player.seekTo(Duration.zero));
    }
  }

  @override
  void dispose() {
    final player = _player;
    player?.removeListener(_rewindAtEnd);
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    if (!_ready || player == null) {
      return _closedPicture();
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(_togglePlay(player)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          VideoPlayer(player),
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: player,
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
            child: _ReelSeekBar(player: player),
          ),
        ],
      ),
    );
  }

  /// The thumbnail while opening; after a failure, Play to try again.
  Widget _closedPicture() {
    final failure = _failure;
    if (failure == null) {
      return widget.fallback;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _tryAgain,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.fallback,
          const _PlayBadge(),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: _OpenFailure(failure),
          ),
        ],
      ),
    );
  }

  Future<void> _togglePlay(VideoPlayerController player) =>
      player.value.isPlaying ? player.pause() : player.play();
}

/// The player's own words, small, so a report from the phone says why the
/// reel didn't open (M77).
class _OpenFailure extends StatelessWidget {
  const _OpenFailure(this.failure);

  final Object failure;

  @override
  Widget build(BuildContext context) {
    final reason = switch (failure) {
      PlatformException(:final code, :final message) => '$code: $message',
      _ => '$failure',
    };
    return Text(
      "Couldn't play here. $reason",
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: PictureMarkColors.light),
    );
  }
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
