import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/clip/presentation/clip_player.dart';
import 'package:status_studio/src/features/join/domain/cut_file.dart';
import 'package:status_studio/src/features/topic/domain/topic_cut.dart';
import 'package:video_player/video_player.dart';

/// Plays [cut] from its downloaded [file] in a sheet (spec FR-37): play,
/// pause and a seek bar over the moment only.
Future<void> showCutPlayer(BuildContext context, CutFile file, TopicCut cut) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _CutPlayerSheet(file: file, cut: cut),
    );

class _CutPlayerSheet extends ConsumerStatefulWidget {
  const _CutPlayerSheet({required this.file, required this.cut});

  final CutFile file;
  final TopicCut cut;

  @override
  ConsumerState<_CutPlayerSheet> createState() => _CutPlayerSheetState();
}

class _CutPlayerSheetState extends ConsumerState<_CutPlayerSheet> {
  late final VideoPlayerController _player = ref.read(
    videoPlayerFactoryProvider,
  )(widget.file.file);
  var _ready = false;

  Duration get _start => widget.file.positionOf(widget.cut.start);

  Duration get _end => widget.file.positionOf(widget.cut.end);

  @override
  void initState() {
    super.initState();
    _player.addListener(_onTick);
    unawaited(_open());
  }

  Future<void> _open() async {
    await _player.initialize();
    await _player.seekTo(_start);
    await _player.play();
    if (mounted) setState(() => _ready = true);
  }

  /// The file holds whole segments around the moment; playing stops at the
  /// moment's end.
  void _onTick() {
    final value = _player.value;
    if (value.isPlaying && value.position >= _end) {
      unawaited(_player.pause());
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _player.removeListener(_onTick);
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_player.value.isPlaying) {
      await _player.pause();
      return;
    }
    if (_player.value.position >= _end) {
      await _player.seekTo(_start);
    }
    await _player.play();
  }

  @override
  Widget build(BuildContext context) {
    final value = _player.value;
    final elapsed = _clamped(value.position - _start);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: _ready ? value.aspectRatio : 16 / 9,
              child: _ready
                  ? VideoPlayer(_player)
                  : const Center(child: CircularProgressIndicator()),
            ),
            Row(
              children: [
                IconButton(
                  tooltip: value.isPlaying ? 'Pause' : 'Play',
                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                  onPressed: _ready ? () => unawaited(_togglePlay()) : null,
                ),
                Expanded(
                  child: Slider(
                    max: widget.cut.length.inMilliseconds.toDouble(),
                    value: elapsed.inMilliseconds.toDouble(),
                    onChanged: _ready
                        ? (milliseconds) => unawaited(
                            _player.seekTo(
                              _start +
                                  Duration(milliseconds: milliseconds.round()),
                            ),
                          )
                        : null,
                  ),
                ),
                Text(formatTimestamp(widget.cut.start + elapsed)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Duration _clamped(Duration elapsed) {
    if (elapsed < Duration.zero) {
      return Duration.zero;
    }
    return elapsed > widget.cut.length ? widget.cut.length : elapsed;
  }
}
