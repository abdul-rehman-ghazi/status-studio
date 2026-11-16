import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/presentation/auto_hiding_controls.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/clip/domain/clip_window.dart';
import 'package:status_studio/src/features/clip/presentation/clip_player.dart';
import 'package:status_studio/src/features/clip/presentation/not_in_clip_shade.dart';
import 'package:status_studio/src/features/join/domain/cut_file.dart';
import 'package:status_studio/src/features/topic/domain/cut_edits.dart';
import 'package:status_studio/src/features/topic/domain/topic_cut.dart';
import 'package:status_studio/src/theme/app_theme.dart';
import 'package:video_player/video_player.dart';

/// How far around a moved edge the sheet plays it (spec FR-39).
const _edgeReplay = Duration(seconds: 2);

/// What the Play sheet opens on, and what it can do (spec FR-39).
class CutPlayerStart {
  const CutPlayerStart({
    required this.file,
    required this.cut,
    required this.nudge,
    required this.download,
  });

  /// The moment with its margins, downloaded.
  final CutFile file;
  final TopicCut cut;

  /// Moves the moment's edges on Review cuts under the card's rules, and
  /// gives the moment as it now is (unchanged when the move was refused).
  final TopicCut Function({Duration startBy, Duration endBy}) nudge;

  /// Downloads [TopicCut] with its margins again, for a nudge past them.
  final Future<CutFile> Function(TopicCut cut) download;
}

/// Plays a moment with what is around it and trims it while it plays
/// (spec FR-37, FR-39).
Future<void> showCutPlayer(BuildContext context, CutPlayerStart start) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _CutPlayerSheet(start: start),
    );

class _CutPlayerSheet extends ConsumerStatefulWidget {
  const _CutPlayerSheet({required this.start});

  final CutPlayerStart start;

  @override
  ConsumerState<_CutPlayerSheet> createState() => _CutPlayerSheetState();
}

class _CutPlayerSheetState extends ConsumerState<_CutPlayerSheet> {
  late CutFile _file = widget.start.file;
  late TopicCut _cut = widget.start.cut;
  VideoPlayerController? _player;
  var _ready = false;
  var _downloading = false;

  /// Where playing pauses by itself, in the video's time.
  late Duration _stopAt = _cut.end;

  ClipWindow get _range => _file.covered;

  Duration get _position =>
      _file.fileStart + (_player?.value.position ?? Duration.zero);

  bool get _isPlaying => _player?.value.isPlaying ?? false;

  bool get _isIncluded => _position >= _cut.start && _position < _cut.end;

  @override
  void initState() {
    super.initState();
    unawaited(_openAndPlay());
  }

  Future<void> _openAndPlay() async {
    await _open(_cut.start);
    await _player?.play();
  }

  @override
  void dispose() {
    unawaited(_close());
    super.dispose();
  }

  /// Opens [_file] paused at [from].
  Future<void> _open(Duration from) async {
    final player = ref.read(videoPlayerFactoryProvider)(_file.file)
      ..addListener(_onTick);
    _player = player;
    await player.initialize();
    await player.seekTo(_file.positionOf(from));
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _close() async {
    final player = _player;
    _player = null;
    player?.removeListener(_onTick);
    await player?.dispose();
  }

  void _onTick() {
    if (_isPlaying && _position >= _stopAt) {
      unawaited(_player?.pause());
    }
    if (mounted) setState(() {});
  }

  /// Goes on from the playhead to the moment's end, or to the stretch's end
  /// once past it; at the stretch's end it starts again at the moment.
  Future<void> _togglePlay() async {
    final player = _player;
    if (player == null) {
      return;
    }
    if (_isPlaying) {
      await player.pause();
      return;
    }
    if (_position >= _range.end - const Duration(milliseconds: 100)) {
      await player.seekTo(_file.positionOf(_cut.start));
    }
    _stopAt = _position < _cut.end ? _cut.end : _range.end;
    await player.play();
  }

  Future<void> _seek(Duration time) async =>
      _player?.seekTo(_file.positionOf(time));

  Future<void> _nudge({
    Duration startBy = Duration.zero,
    Duration endBy = Duration.zero,
  }) async {
    final moved = widget.start.nudge(startBy: startBy, endBy: endBy);
    if (moved == _cut) {
      return;
    }
    setState(() => _cut = moved);
    final edge = startBy != Duration.zero ? moved.start : moved.end;
    if (!_covers(_range, moved)) {
      await _downloadAgain(moved);
    }
    await _replayAround(edge);
  }

  /// The nudge went past the downloaded stretch: the moment is fetched
  /// again with its margins, and the player reopened on it.
  Future<void> _downloadAgain(TopicCut moved) async {
    setState(() => _downloading = true);
    try {
      final file = await widget.start.download(moved);
      await _close();
      if (!mounted) {
        return;
      }
      setState(() {
        _file = file;
        _ready = false;
      });
      await _open(moved.start);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  /// Plays from a little before [edge] to a little after it (spec FR-39).
  Future<void> _replayAround(Duration edge) async {
    final player = _player;
    if (player == null || !_ready) {
      return;
    }
    final from = _clampedToRange(edge - _edgeReplay);
    _stopAt = _clampedToRange(edge + _edgeReplay);
    await player.seekTo(_file.positionOf(from));
    await player.play();
  }

  Duration _clampedToRange(Duration time) {
    if (time < _range.start) {
      return _range.start;
    }
    return time > _range.end ? _range.end : time;
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    final showsPicture = _ready && !_downloading && player != null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: showsPicture ? player.value.aspectRatio : 16 / 9,
              child: showsPicture
                  ? AutoHidingControls(
                      player: player,
                      picture: _Picture(
                        player: player,
                        isIncluded: _isIncluded,
                      ),
                      controls: [
                        Positioned.fill(
                          child: Center(
                            child: IconButton.filled(
                              tooltip: _isPlaying ? 'Pause' : 'Play',
                              iconSize: 32,
                              icon: Icon(
                                _isPlaying ? Icons.pause : Icons.play_arrow,
                              ),
                              onPressed: () => unawaited(_togglePlay()),
                            ),
                          ),
                        ),
                      ],
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
            _TrimBar(
              reading: (
                range: _range,
                included: ClipWindow(start: _cut.start, end: _cut.end),
                position: _clampedToRange(_position),
              ),
              onSeek: (time) => unawaited(_seek(time)),
            ),
            _EdgeNudges(
              label: 'Start',
              time: _cut.start,
              onNudge: (by) => unawaited(_nudge(startBy: by)),
            ),
            _EdgeNudges(
              label: 'End',
              time: _cut.end,
              onNudge: (by) => unawaited(_nudge(endBy: by)),
            ),
          ],
        ),
      ),
    );
  }
}

bool _covers(ClipWindow range, TopicCut cut) =>
    range.start <= cut.start && cut.end <= range.end;

/// The video, dimmed with "Not in the clip" outside the moment.
class _Picture extends StatelessWidget {
  const _Picture({required this.player, required this.isIncluded});

  final VideoPlayerController player;
  final bool isIncluded;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [VideoPlayer(player), if (!isIncluded) const NotInClipShade()],
    );
  }
}

/// What the bar shows: the downloaded stretch, the moment in it, and the
/// playhead, all in the video's time.
typedef _BarReading = ({
  ClipWindow range,
  ClipWindow included,
  Duration position,
});

/// The stretch as a bar: the moment in the accent colour, the rest grey,
/// the playhead as a dot; a tap or drag seeks.
class _TrimBar extends StatelessWidget {
  const _TrimBar({required this.reading, required this.onSeek});

  final _BarReading reading;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        void seekTo(double dx) => onSeek(_timeAt(dx, constraints.maxWidth));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => seekTo(details.localPosition.dx),
          onHorizontalDragUpdate: (details) => seekTo(details.localPosition.dx),
          child: SizedBox(
            height: 40,
            child: CustomPaint(
              painter: _TrimBarPainter(
                reading: reading,
                colours: (
                  outside: palette.textMuted.withValues(alpha: 0.35),
                  included: palette.accent,
                  playhead: palette.textPrimary,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Duration _timeAt(double dx, double width) {
    final fraction = (dx / width).clamp(0.0, 1.0);
    final span = reading.range.end - reading.range.start;
    return reading.range.start + span * fraction;
  }
}

typedef _BarColours = ({Color outside, Color included, Color playhead});

class _TrimBarPainter extends CustomPainter {
  const _TrimBarPainter({required this.reading, required this.colours});

  final _BarReading reading;
  final _BarColours colours;

  static const _trackHeight = 6.0;
  static const _playheadRadius = 7.0;

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.height / 2;
    _drawTrack(canvas, (0, size.width), middle, colours.outside);
    _drawTrack(
      canvas,
      (
        _xOf(reading.included.start, size.width),
        _xOf(reading.included.end, size.width),
      ),
      middle,
      colours.included,
    );
    canvas.drawCircle(
      Offset(_xOf(reading.position, size.width), middle),
      _playheadRadius,
      Paint()..color = colours.playhead,
    );
  }

  void _drawTrack(
    Canvas canvas,
    (double, double) span,
    double middle,
    Color colour,
  ) {
    final (left, right) = span;
    canvas.drawRRect(
      RRect.fromLTRBR(
        left,
        middle - _trackHeight / 2,
        right,
        middle + _trackHeight / 2,
        const Radius.circular(_trackHeight / 2),
      ),
      Paint()..color = colour,
    );
  }

  double _xOf(Duration time, double width) {
    final span = reading.range.end - reading.range.start;
    if (span <= Duration.zero) {
      return 0;
    }
    final fraction =
        (time - reading.range.start).inMicroseconds / span.inMicroseconds;
    return width * fraction.clamp(0.0, 1.0);
  }

  @override
  bool shouldRepaint(_TrimBarPainter old) =>
      old.reading != reading || old.colours != colours;
}

/// "Start 1:02:13.5" with − and + of 0.5 s (spec FR-39).
class _EdgeNudges extends StatelessWidget {
  const _EdgeNudges({
    required this.label,
    required this.time,
    required this.onNudge,
  });

  final String label;
  final Duration time;
  final ValueChanged<Duration> onNudge;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text('$label ${formatClipTime(time)}')),
        IconButton(
          tooltip: '$label 0.5 s earlier',
          icon: const Icon(Icons.remove),
          onPressed: () => onNudge(-cutNudge),
        ),
        IconButton(
          tooltip: '$label 0.5 s later',
          icon: const Icon(Icons.add),
          onPressed: () => onNudge(cutNudge),
        ),
      ],
    );
  }
}
