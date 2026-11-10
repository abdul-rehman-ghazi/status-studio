import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/features/clip/application/clip_playhead.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/clip/presentation/clip_player.dart';
import 'package:status_studio/src/features/source/application/clip_source_controller.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// The clip player once the kept video is open (FR-5); until then, a
/// message.
class ClipSourcePlayer extends ConsumerStatefulWidget {
  const ClipSourcePlayer({
    super.key,
    required this.video,
    required this.clip,
    required this.playhead,
    this.videoOverlay,
    this.frame,
    this.onlyRange,
  });

  final SourceVideo video;
  final ClipRange clip;
  final ClipPlayhead playhead;

  /// Drawn over the video once it plays.
  final Widget? videoOverlay;

  /// See [ClipPlayer.frame].
  final Widget Function(BuildContext context, Widget video)? frame;

  /// See [ClipPlayer.onlyRange].
  final ClipRange? onlyRange;

  @override
  ConsumerState<ClipSourcePlayer> createState() => ClipSourcePlayerState();
}

class ClipSourcePlayerState extends ConsumerState<ClipSourcePlayer> {
  @override
  void initState() {
    super.initState();
    // Providers can't change during build, so the video opens after the
    // first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _openVideo();
      }
    });
  }

  void _openVideo() {
    unawaited(
      ref
          .read(clipSourceProvider(widget.video.videoId).notifier)
          .open(widget.video),
    );
  }

  @override
  Widget build(BuildContext context) {
    // unwrapPrevious: a retry shows the opening message, not the earlier
    // failure.
    final source = ref
        .watch(clipSourceProvider(widget.video.videoId))
        .unwrapPrevious();
    if (source.value case final clipSource?) {
      return ClipPlayer(
        key: ValueKey(clipSource.file.path),
        source: clipSource,
        clip: widget.clip,
        playhead: widget.playhead,
        videoOverlay: widget.videoOverlay,
        frame: widget.frame,
        onlyRange: widget.onlyRange,
      );
    }
    if (source.error case final error?) {
      return _PlayerMessage(text: errorMessageFor(error));
    }
    return const _PlayerMessage(text: 'Opening the video…');
  }
}

class _PlayerMessage extends StatelessWidget {
  const _PlayerMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(child: HintText(text)),
      ),
    );
  }
}

/// Holds the player's place while it is released (see Fine-tune · Video).
class ClipPlayerPlaceholder extends StatelessWidget {
  const ClipPlayerPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlayerMessage(text: 'Paused while you edit the lyrics.');
  }
}
