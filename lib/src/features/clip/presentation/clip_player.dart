import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/clip/domain/clip_playback.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/source/domain/clip_source.dart';
import 'package:status_studio/src/routing/app_router.dart';
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

  final ClipSource source;

  /// In video time; the player works in the clip file's time.
  final ClipRange clip;

  @override
  ConsumerState<ClipPlayer> createState() => _ClipPlayerState();
}

class _ClipPlayerState extends ConsumerState<ClipPlayer> with RouteAware {
  late final VideoPlayerController _player = ref.read(
    videoPlayerFactoryProvider,
  )(widget.source.file);
  late final RouteObserver<ModalRoute<void>> _routes = ref.read(
    routeObserverProvider,
  );
  var _unplayable = false;

  @override
  void initState() {
    super.initState();
    _player.addListener(_stopAtClipEnd);
    unawaited(_initialize());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context) case final route?) {
      _routes.subscribe(this, route);
    }
  }

  Future<void> _initialize() async {
    try {
      await _player.initialize();
    } catch (_) {
      // An unsupported codec or a damaged file; say so instead of showing a
      // player that never starts.
      if (mounted) {
        setState(() => _unplayable = true);
      }
      return;
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _routes.unsubscribe(this);
    _player.removeListener(_stopAtClipEnd);
    unawaited(_player.dispose());
    super.dispose();
  }

  /// Another screen now covers this one; the clip must not play on behind it.
  @override
  void didPushNext() {
    if (_player.value.isPlaying) {
      unawaited(_player.pause());
    }
  }

  /// [ClipPlayer.clip] moved into the clip file's own time.
  ClipRange get _clipInFile => ClipRange(
    start: widget.clip.start - widget.source.offset,
    end: widget.clip.end - widget.source.offset,
  );

  void _stopAtClipEnd() {
    final value = _player.value;
    if (value.isPlaying && shouldStopPlayback(value.position, _clipInFile)) {
      unawaited(_player.pause());
    }
  }

  Future<void> _togglePlayback() async {
    if (_player.value.isPlaying) {
      await _player.pause();
      return;
    }
    await _player.seekTo(_clipInFile.start);
    await _player.play();
  }

  @override
  Widget build(BuildContext context) {
    if (_unplayable) {
      return const _Unplayable();
    }
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

class _Unplayable extends StatelessWidget {
  const _Unplayable();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text(
            "Couldn't play this video.",
            style: TextStyle(color: AppColors.textMuted),
          ),
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
