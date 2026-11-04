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

/// The clip player once the clip's window is downloaded (FR-15); until
/// then, how far the download has got.
class ClipSourcePlayer extends ConsumerStatefulWidget {
  const ClipSourcePlayer({
    super.key,
    required this.video,
    required this.clip,
    required this.playhead,
    this.videoOverlay,
    this.frame,
  });

  final SourceVideo video;
  final ClipRange clip;
  final ClipPlayhead playhead;

  /// Drawn over the video once it plays.
  final Widget? videoOverlay;

  /// See [ClipPlayer.frame].
  final Widget Function(BuildContext context, Widget video)? frame;

  @override
  ConsumerState<ClipSourcePlayer> createState() => ClipSourcePlayerState();
}

class ClipSourcePlayerState extends ConsumerState<ClipSourcePlayer> {
  @override
  void initState() {
    super.initState();
    // Providers can't change during build, so the first download waits for
    // the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _prepareFor(widget.clip);
      }
    });
  }

  @override
  void didUpdateWidget(ClipSourcePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.clip != oldWidget.clip) {
      // A nudge past the downloaded window needs a new one; inside it this
      // does nothing.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _prepareFor(widget.clip);
        }
      });
    }
  }

  void _prepareFor(ClipRange clip) {
    unawaited(
      ref
          .read(clipSourceProvider(widget.video.videoId).notifier)
          .prepareFor(widget.video, clip),
    );
  }

  @override
  Widget build(BuildContext context) {
    final videoId = widget.video.videoId;
    // unwrapPrevious: a new window or a retry shows progress, not the
    // earlier file or failure.
    final source = ref.watch(clipSourceProvider(videoId)).unwrapPrevious();
    if (source.value case final clipSource?) {
      return ClipPlayer(
        key: ValueKey(clipSource.file.path),
        source: clipSource,
        clip: widget.clip,
        playhead: widget.playhead,
        videoOverlay: widget.videoOverlay,
        frame: widget.frame,
      );
    }
    if (source.error case final error?) {
      return _PlayerMessage(text: errorMessageFor(error));
    }
    final fraction = ref.watch(clipSourceProgressProvider(videoId));
    final percent = (fraction * 100).round();
    return _PlayerMessage(text: 'Downloading clip… $percent %');
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
          color: AppColors.surface,
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
