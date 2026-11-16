import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/presentation/screen_title.dart';
import 'package:status_studio/src/features/join/application/background_clip_maker.dart';
import 'package:status_studio/src/features/join/application/clip_maker.dart';
import 'package:status_studio/src/features/join/domain/join_errors.dart';
import 'package:status_studio/src/features/join/domain/making_progress.dart';
import 'package:status_studio/src/features/join/presentation/making_view.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/source/application/is_video_kept.dart';
import 'package:status_studio/src/features/topic/application/link_session_saver.dart';
import 'package:status_studio/src/features/topic/domain/moment_source.dart';
import 'package:status_studio/src/features/topic/domain/topic_request.dart';
import 'package:status_studio/src/routing/app_router.dart';

/// Use the whole video on From a link (spec FR-52): the video downloads as
/// one cut, shown as Make the clip shows its cuts, then Fine-tune opens
/// on it in place of this screen. Cancel and Back return to From a link.
class WholeLinkScreen extends ConsumerStatefulWidget {
  const WholeLinkScreen({required this.request, super.key});

  final TopicRequest request;

  @override
  ConsumerState<WholeLinkScreen> createState() => _WholeLinkScreenState();
}

class _WholeLinkScreenState extends ConsumerState<WholeLinkScreen> {
  MakingProgress? _making;
  Object? _failure;

  @override
  void initState() {
    super.initState();
    _keepLinkFacts();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_make()));
  }

  /// History's row for the link shows its title and thumbnail, and its New
  /// reads the page again, from these facts (spec FR-44, FR-52), as Review
  /// cuts keeps them.
  void _keepLinkFacts() {
    if (widget.request.source case LinkedMoments(:final video)) {
      unawaited(ref.read(linkSessionSaverProvider).saveVideo(video));
    }
  }

  @override
  void dispose() {
    if (_making != null) {
      unawaited(ref.read(backgroundClipMakerProvider).cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const ScreenTitle('Whole video')),
      body: Center(child: _body()),
    );
  }

  Widget _body() {
    if (_failure case final failure?) {
      return MakeFailureView(
        failure: failure,
        onTryAgain: () => unawaited(_make()),
        onBack: () => context.pop(),
      );
    }
    return MakingView(
      progress: _making ?? const ReadingStreams(),
      onCancel: () => unawaited(ref.read(backgroundClipMakerProvider).cancel()),
    );
  }

  Future<void> _make() async {
    setState(() {
      _failure = null;
      _making = const ReadingStreams();
    });
    try {
      final made = await ref.read(backgroundClipMakerProvider).make(
        ClipOrder.wholeVideo(widget.request),
        (progress) {
          if (mounted) setState(() => _making = progress);
        },
      );
      _making = null;
      if (!mounted) {
        return;
      }
      ref.invalidate(isVideoKeptProvider);
      ref.read(reelDraftProvider.notifier).setVideoOn(made.video, made.clip);
      context.pushReplacement(AppRoutes.fineTune);
    } on DownloadCancelledException {
      _making = null;
      if (mounted) context.pop();
    } on Object catch (failure) {
      // Every failure shows on the screen; none may reach the zone.
      _making = null;
      if (mounted) setState(() => _failure = failure);
    }
  }
}
