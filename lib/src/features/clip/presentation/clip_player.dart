import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/clip/application/clip_playhead.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/clip/presentation/playhead_redraw.dart';
import 'package:status_studio/src/features/source/domain/clip_source.dart';
import 'package:status_studio/src/routing/app_router.dart';
import 'package:status_studio/src/theme/app_theme.dart';
import 'package:video_player/video_player.dart';

/// The tallest the player gets: a vertical video or a 9:16 reel at full width
/// would fill the screen and push the controls off it.
const _framedMaxHeight = 260.0;

typedef VideoPlayerFactory = VideoPlayerController Function(File source);

/// Creates players, so tests can swap in one that never touches the platform.
final videoPlayerFactoryProvider = Provider<VideoPlayerFactory>(
  (ref) => VideoPlayerController.file,
);

/// Plays the downloaded [source] with play, pause and a seek bar over all of
/// it, and keeps [playhead] up to date (spec FR-5, FR-21). [clip] is only
/// marked on the bar and where "Play clip" starts. With [onlyRange] it plays
/// that range and nothing else.
class ClipPlayer extends ConsumerStatefulWidget {
  const ClipPlayer({
    super.key,
    required this.source,
    required this.clip,
    required this.playhead,
    this.videoOverlay,
    this.frame,
    this.onlyRange,
  });

  final ClipSource source;

  /// In video time. When set, the bar covers just this range, the player
  /// starts at its start and stops at its end, and "Play clip" is not shown
  /// (Fine-tune · Lyrics shows only the clip).
  final ClipRange? onlyRange;

  /// Drawn over the video, under the play button.
  final Widget? videoOverlay;

  /// Builds what is shown around the unframed video, with the output's
  /// aspect (the reel as it will look); without it the video is shown as it
  /// is.
  final Widget Function(BuildContext context, Widget video)? frame;
  final ClipPlayhead playhead;

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
    widget.playhead.attach(_seekToVideoTime);
    _player.addListener(_reportPlayhead);
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
    final only = _onlyRangeInFile;
    if (only != null) {
      await _player.seekTo(only.start);
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _routes.unsubscribe(this);
    widget.playhead.detach();
    _player.removeListener(_reportPlayhead);
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

  /// [ClipPlayer.onlyRange] in the clip file's own time.
  ClipRange? get _onlyRangeInFile {
    final only = widget.onlyRange;
    if (only == null) {
      return null;
    }
    return ClipRange(
      start: only.start - widget.source.offset,
      end: only.end - widget.source.offset,
    );
  }

  Future<void> _seekToVideoTime(Duration videoTime) {
    final fileTime = videoTime - widget.source.offset;
    final only = _onlyRangeInFile;
    if (only == null) {
      return _player.seekTo(fileTime);
    }
    final inRange = fileTime < only.start
        ? only.start
        : (fileTime > only.end ? only.end : fileTime);
    return _player.seekTo(inRange);
  }

  void _reportPlayhead() {
    final value = _player.value;
    final only = _onlyRangeInFile;
    if (only != null && value.isPlaying && value.position >= only.end) {
      unawaited(_player.pause());
    }
    widget.playhead.report(
      position: value.position + widget.source.offset,
      isPlaying: value.isPlaying,
    );
  }

  Future<void> _togglePlayback() async {
    if (_player.value.isPlaying) {
      await _player.pause();
      return;
    }
    final value = _player.value;
    final only = _onlyRangeInFile;
    if (only != null) {
      // Past the end, or before the start, playing begins at the start.
      if (value.position >= only.end || value.position < only.start) {
        await _player.seekTo(only.start);
      }
    } else if (value.position >= value.duration) {
      await _player.seekTo(Duration.zero);
    }
    await _player.play();
  }

  Future<void> _playClip() async {
    await _player.seekTo(_clipInFile.start);
    await _player.play();
  }

  /// The video, or the reel built around it by [ClipPlayer.frame], at most
  /// [_framedMaxHeight] high, with the overlay and the play button over it.
  Widget _stage(VideoPlayerValue value) {
    final video = VideoPlayer(_player);
    final frame = widget.frame;
    final Widget picture;
    if (!value.isInitialized) {
      picture = const AspectRatio(
        aspectRatio: 16 / 9,
        child: SizedBox.shrink(),
      );
    } else if (frame != null) {
      picture = frame(context, video);
    } else {
      picture = AspectRatio(aspectRatio: value.aspectRatio, child: video);
    }
    final stage = Stack(
      children: [
        picture,
        if (value.isInitialized && widget.videoOverlay != null)
          Positioned.fill(child: widget.videoOverlay!),
        // Over a crop window the middle belongs to dragging it.
        Positioned.fill(
          child: Align(
            alignment: widget.videoOverlay == null
                ? Alignment.center
                : Alignment.bottomLeft,
            child: Padding(
              padding: EdgeInsets.all(widget.videoOverlay == null ? 0 : 8),
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: _player,
                builder: (context, value, _) => _PlayButton(
                  playing: value.isPlaying,
                  onPressed: value.isInitialized ? _togglePlayback : null,
                ),
              ),
            ),
          ),
        ),
      ],
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: AppColors.surface)),
          SizedBox(
            width: double.infinity,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: _framedMaxHeight),
                child: stage,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_unplayable) {
      return const _Unplayable();
    }
    final value = _player.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stage(value),
        ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: _player,
          builder: (context, value, _) => _SeekBar(
            playhead: widget.playhead,
            span:
                _onlyRangeInFile ??
                ClipRange(start: Duration.zero, end: value.duration),
            markedClip: widget.onlyRange == null ? _clipInFile : null,
            offset: widget.source.offset,
            onSeek: value.isInitialized ? _player.seekTo : null,
          ),
        ),
        if (widget.onlyRange == null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: value.isInitialized ? _playClip : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play clip'),
            ),
          ),
      ],
    );
  }
}

/// A slider over the downloaded window, with the clip range marked under it.
/// It reads the playhead, not the player, so it moves smoothly between the
/// player's reports.
class _SeekBar extends StatefulWidget {
  const _SeekBar({
    required this.playhead,
    required this.span,
    required this.markedClip,
    required this.offset,
    required this.onSeek,
  });

  final ClipPlayhead playhead;

  /// What the bar covers, in the clip file's time.
  final ClipRange span;

  /// The clip to fill on the bar, or none when the bar is the clip.
  final ClipRange? markedClip;
  final Duration offset;
  final ValueChanged<Duration>? onSeek;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar>
    with SingleTickerProviderStateMixin {
  static const _trackInset = 10.0;

  /// Wide enough for `99:59.9` in digits of equal width, so the slider
  /// beside it never changes size as the time changes.
  static const _timeWidth = 64.0;

  late final PlayheadRedraw _redraw;

  @override
  void initState() {
    super.initState();
    _redraw = PlayheadRedraw(
      vsync: this,
      playhead: widget.playhead,
      isMounted: () => mounted,
      redraw: () => setState(() {}),
    );
  }

  @override
  void dispose() {
    _redraw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final startMilliseconds = widget.span.start.inMilliseconds;
    final spanMilliseconds = widget.span.length.inMilliseconds;
    if (spanMilliseconds <= 0) {
      return const SizedBox(height: 48);
    }
    final videoTime = widget.playhead.position;
    final shownMilliseconds = (videoTime - widget.offset).inMilliseconds.clamp(
      startMilliseconds,
      startMilliseconds + spanMilliseconds,
    );
    final onSeek = widget.onSeek;
    final marked = widget.markedClip;
    return Row(
      children: [
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _trackInset),
                  child: _ClipMarker(
                    startFraction: marked == null
                        ? null
                        : (marked.start.inMilliseconds - startMilliseconds) /
                              spanMilliseconds,
                    endFraction: marked == null
                        ? null
                        : (marked.end.inMilliseconds - startMilliseconds) /
                              spanMilliseconds,
                  ),
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  overlayShape: SliderComponentShape.noOverlay,
                  // Outline only: a coloured played part would hide the clip
                  // range marked under it.
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                ),
                child: Slider(
                  value: shownMilliseconds.toDouble(),
                  min: startMilliseconds.toDouble(),
                  max: (startMilliseconds + spanMilliseconds).toDouble(),
                  semanticFormatterCallback: (_) => 'Seek',
                  onChanged: onSeek == null
                      ? null
                      : (milliseconds) => onSeek(
                          Duration(milliseconds: milliseconds.round()),
                        ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: _timeWidth,
          child: Text(
            formatClipTime(videoTime),
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

const _trackHeight = 8.0;

class _ClipMarker extends StatelessWidget {
  const _ClipMarker({required this.startFraction, required this.endFraction});

  /// Both none: nothing is filled, only the outline shows.
  final double? startFraction;
  final double? endFraction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final start = startFraction;
        final end = endFraction;
        final left = constraints.maxWidth * (start ?? 0).clamp(0, 1);
        final right = constraints.maxWidth * (end ?? 0).clamp(0, 1);
        return Stack(
          alignment: Alignment.centerLeft,
          children: [
            // The whole window as an outline; only the clip is filled.
            SizedBox(
              height: _trackHeight,
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_trackHeight / 2),
                  border: Border.all(color: AppColors.textMuted),
                ),
              ),
            ),
            if (start != null && end != null)
              Positioned(
                left: left,
                width: right - left,
                height: _trackHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(_trackHeight / 2),
                  ),
                ),
              ),
          ],
        );
      },
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
      tooltip: playing ? 'Pause' : 'Play',
      iconSize: 32,
      onPressed: onPressed,
      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
    );
  }
}
