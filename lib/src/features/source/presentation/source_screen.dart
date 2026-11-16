import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/core/presentation/bottom_action.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/presentation/screen_title.dart';
import 'package:status_studio/src/core/presentation/section_label.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/source/application/is_video_kept.dart';
import 'package:status_studio/src/features/source/application/video_thumbnail.dart';
import 'package:status_studio/src/features/source/data/local_video_importer.dart';
import 'package:status_studio/src/features/source/data/video_picker.dart';
import 'package:status_studio/src/features/source/domain/incoming_video.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/topic/domain/moment_source.dart';
import 'package:status_studio/src/features/topic/domain/topic_request.dart';
import 'package:status_studio/src/features/topic/presentation/replace_unfinished_dialog.dart';
import 'package:status_studio/src/features/topic/presentation/script_fields.dart';
import 'package:status_studio/src/routing/app_router.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// Step 1: bring in a video, by the gallery picker or by a share (spec FR-1).
/// Links have their own screen (FR-35).
///
/// A [sharedVideo] is imported at once; like a picked one, it waits for the
/// user to choose a script or none (spec FR-29), so nothing is uploaded
/// unasked. On Android the kept video's card is followed by Output
/// language, Get the script (Review cuts) and Use the whole video
/// (Fine-tune) (FR-51); iOS keeps Next: video.
class SourceScreen extends ConsumerStatefulWidget {
  const SourceScreen({this.sharedVideo, super.key});

  final IncomingVideo? sharedVideo;

  @override
  ConsumerState<SourceScreen> createState() => _SourceScreenState();
}

class _SourceScreenState extends ConsumerState<SourceScreen> {
  Future<SourceVideo>? _videoRequest;

  /// The kept video, once [_videoRequest] succeeds.
  SourceVideo? _video;

  /// Counts imports, so only the newest one's conversion shows on the card.
  var _importNumber = 0;
  int? _convertingImport;
  var _conversionFraction = 0.0;

  @override
  void initState() {
    super.initState();
    final shared = widget.sharedVideo;
    if (shared == null) {
      unawaited(_recoverLostPick());
      return;
    }
    // The card's FutureBuilder reports a failed import.
    final request = _importVideo(shared.path, shared.displayName)..ignore();
    _videoRequest = request;
    unawaited(_keepWhenImported(request));
  }

  @override
  Widget build(BuildContext context) {
    final hasVideo = _videoRequest != null;
    return Scaffold(
      appBar: AppBar(title: const ScreenTitle('New reel')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SectionLabel('Video'),
          OutlinedButton.icon(
            onPressed: _chooseVideo,
            icon: const Icon(Icons.video_library_outlined),
            label: Text(hasVideo ? 'Choose another video' : 'Choose a video'),
          ),
          if (_videoRequest case final request?)
            _VideoCard(
              request: request,
              conversionFraction: _convertingImport == _importNumber
                  ? _conversionFraction
                  : null,
            ),
          const SizedBox(height: 8),
          const HintText(
            'Trim it in another app first, or share it to Status Studio.',
          ),
          if (_momentsOffered) ?_momentChoices(),
        ],
      ),
      bottomNavigationBar: _momentsOffered
          ? null
          : BottomAction(
              child: FilledButton(
                onPressed: hasVideo ? () => unawaited(_openVideoStep()) : null,
                child: const Text('Next: video'),
              ),
            ),
    );
  }

  /// Review cuts and the join exist on Android only (spec FR-51).
  bool get _momentsOffered => defaultTargetPlatform == TargetPlatform.android;

  Widget? _momentChoices() {
    final video = _video;
    if (video == null) {
      return null;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        ScriptFields(
          key: ValueKey(video.videoId),
          source: LocalMoments(video),
          onGet: (request) => unawaited(_getScript(request)),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => unawaited(_openVideoStep()),
          child: const Text('Use the whole video'),
        ),
      ],
    );
  }

  /// One unfinished piece of work per video (spec FR-43, FR-51): starting
  /// again asks first, then deletes the old one.
  Future<void> _getScript(TopicRequest request) async {
    if (!await clearUnfinishedLinkWork(context, ref, request.source.key)) {
      return;
    }
    if (mounted) await context.push(AppRoutes.reviewCuts, extra: request);
  }

  Future<void> _keepWhenImported(Future<SourceVideo> request) async {
    try {
      final video = await request;
      if (mounted && identical(request, _videoRequest)) {
        setState(() => _video = video);
      }
    } on Object {
      // The card shows why.
    }
  }

  Future<void> _chooseVideo() async {
    final VideoPickResult picked;
    try {
      picked = await ref.read(videoPickerProvider).pickVideo();
    } on VideoPickFailedException catch (failure) {
      _showVideo(Future<SourceVideo>.error(failure));
      return;
    }
    if (picked is VideoPicked) {
      _showVideo(_importVideo(picked.path, picked.displayName));
    }
  }

  Future<void> _recoverLostPick() async {
    final LostVideoResult lost;
    try {
      lost = await ref.read(videoPickerProvider).retrieveLostVideo();
    } on VideoPickFailedException {
      return;
    }
    if (lost is LostVideoFound && mounted && _videoRequest == null) {
      _showVideo(_importVideo(lost.video.path, lost.video.displayName));
    }
  }

  /// The card shows a failure once it builds; ignore() keeps the error from
  /// being reported as unhandled before then.
  void _showVideo(Future<SourceVideo> request) {
    if (!mounted) {
      return;
    }
    request.ignore();
    setState(() {
      _videoRequest = request;
      _video = null;
    });
    unawaited(_keepWhenImported(request));
  }

  Future<SourceVideo> _importVideo(String path, String displayName) async {
    final number = ++_importNumber;
    final importer = await ref.read(localVideoImporterProvider.future);
    final video = await importer.importVideo(
      path: path,
      displayName: displayName,
      onConversionProgress: (fraction) => _showConversion(number, fraction),
    );
    // Recent rows that asked for this video again can open now.
    if (mounted) {
      ref.invalidate(isVideoKeptProvider);
    }
    return video;
  }

  void _showConversion(int importNumber, double fraction) {
    if (!mounted || importNumber != _importNumber) {
      return;
    }
    setState(() {
      _convertingImport = importNumber;
      _conversionFraction = fraction;
    });
  }

  /// Opens Fine-tune · Video once the chosen video is in (spec FR-1, M30).
  /// Nothing is uploaded from here: lyrics are asked for on Lyrics. A failed
  /// import stays on this screen, and so does one replaced by another choice
  /// meanwhile.
  Future<void> _openVideoStep() async {
    final request = _videoRequest;
    if (request == null) {
      return;
    }
    final SourceVideo video;
    try {
      video = await request;
    } catch (_) {
      // The video card already shows why; stay on this screen. Not only
      // Exceptions: nothing here may reach the zone as an unhandled error.
      return;
    }
    // Another video was chosen while this one was still importing.
    if (!mounted || !identical(request, _videoRequest)) {
      return;
    }
    ref.read(reelDraftProvider.notifier).setVideo(video);
    await context.push(AppRoutes.fineTune);
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.request, required this.conversionFraction});

  final Future<SourceVideo> request;

  /// How far an AV1 video's conversion to H.264 is (spec FR-1, M31); null
  /// when the video isn't being converted.
  final double? conversionFraction;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SourceVideo>(
      future: request,
      builder: (context, snapshot) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: _cardContent(context, snapshot, switch (conversionFraction) {
          final fraction? => _ConversionProgress(fraction: fraction),
          null => const LinearProgressIndicator(),
        }),
      ),
    );
  }
}

Widget _cardContent(
  BuildContext context,
  AsyncSnapshot<SourceVideo> snapshot,
  Widget pending,
) {
  if (snapshot.error case final error?) {
    return Text(
      errorMessageFor(error),
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    );
  }
  if (snapshot.data case final video?) {
    return _VideoSummary(video: video);
  }
  return pending;
}

class _ConversionProgress extends StatelessWidget {
  const _ConversionProgress({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final percent = (fraction * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(value: fraction),
        const SizedBox(height: 10),
        HintText(
          'Converting this AV1 video so the app can edit it… $percent %',
        ),
      ],
    );
  }
}

class _VideoSummary extends StatelessWidget {
  const _VideoSummary({required this.video});

  final SourceVideo video;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Thumbnail(videoId: video.videoId),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              HintText(formatTimestamp(video.duration)),
            ],
          ),
        ),
      ],
    );
  }
}

/// The video's first frame; its icon until the picture is ready, or if it
/// can't be made (a missing picture only costs the card its image).
class _Thumbnail extends ConsumerWidget {
  const _Thumbnail({required this.videoId});

  final String videoId;

  static const _size = 56.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnail = ref.watch(videoThumbnailProvider(videoId)).asData;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: _size,
        height: _size,
        child: thumbnail == null
            ? const _ThumbnailIcon()
            : Image.file(
                File(thumbnail.value.path),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => const _ThumbnailIcon(),
              ),
      ),
    );
  }
}

class _ThumbnailIcon extends StatelessWidget {
  const _ThumbnailIcon();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.palette.background,
      child: Icon(Icons.play_circle_outline, color: context.palette.accent),
    );
  }
}
