import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/core/presentation/bottom_action.dart';
import 'package:status_studio/src/core/presentation/flow_app_bar.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/presentation/section_label.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/source/application/is_video_kept.dart';
import 'package:status_studio/src/features/source/application/video_thumbnail.dart';
import 'package:status_studio/src/features/source/data/local_video_importer.dart';
import 'package:status_studio/src/features/source/data/video_picker.dart';
import 'package:status_studio/src/features/source/domain/incoming_video.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/application/script_progress_controller.dart';
import 'package:status_studio/src/routing/app_router.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// Step 1: bring in a video, by the gallery picker or by a share (spec FR-1).
///
/// A [sharedVideo] is imported at once and its script starts without a tap.
class SourceScreen extends ConsumerStatefulWidget {
  const SourceScreen({this.sharedVideo, super.key});

  final IncomingVideo? sharedVideo;

  @override
  ConsumerState<SourceScreen> createState() => _SourceScreenState();
}

class _SourceScreenState extends ConsumerState<SourceScreen> {
  Future<SourceVideo>? _videoRequest;
  var _language = ScriptLanguage.auto;

  @override
  void initState() {
    super.initState();
    final shared = widget.sharedVideo;
    if (shared == null) {
      unawaited(_recoverLostPick());
      return;
    }
    _videoRequest = _importVideo(shared.path, shared.displayName);
    unawaited(_getScript());
  }

  @override
  Widget build(BuildContext context) {
    final hasVideo = _videoRequest != null;
    return Scaffold(
      appBar: const FlowAppBar(title: 'New reel', stepLabel: 'Step 1 of 5'),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SectionLabel('Video'),
          OutlinedButton.icon(
            onPressed: _chooseVideo,
            icon: const Icon(Icons.video_library_outlined),
            label: Text(hasVideo ? 'Choose another video' : 'Choose a video'),
          ),
          if (_videoRequest case final request?) _VideoCard(request: request),
          const SizedBox(height: 8),
          const HintText(
            'Trim it in another app first, or share it to Status Studio.',
          ),
          const SizedBox(height: 24),
          const SectionLabel('Language of the video'),
          DropdownButtonFormField<ScriptLanguage>(
            initialValue: _language,
            isExpanded: true,
            items: [
              for (final language in ScriptLanguage.values)
                DropdownMenuItem(value: language, child: Text(language.label)),
            ],
            onChanged: (language) =>
                setState(() => _language = language ?? ScriptLanguage.auto),
          ),
          const SizedBox(height: 8),
          const HintText(
            'Leave it on automatic unless the script comes out in the wrong '
            'language.',
          ),
          const SizedBox(height: 24),
          const _OnDeviceNote(),
        ],
      ),
      bottomNavigationBar: BottomAction(
        child: FilledButton(
          onPressed: hasVideo ? _getScript : null,
          child: const Text('Get the script'),
        ),
      ),
    );
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
    setState(() => _videoRequest = request..ignore());
  }

  Future<SourceVideo> _importVideo(String path, String displayName) async {
    final importer = await ref.read(localVideoImporterProvider.future);
    final video = await importer.importVideo(
      path: path,
      displayName: displayName,
    );
    // Recent rows that asked for this video again can open now.
    if (mounted) {
      ref.invalidate(isVideoKeptProvider);
    }
    return video;
  }

  Future<void> _getScript() async {
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
    if (!mounted) {
      return;
    }
    ref.read(reelDraftProvider.notifier)
      ..setVideo(video)
      ..setLanguage(_language);
    ref.read(scriptProgressProvider.notifier).start(video, _language);
    await context.push(AppRoutes.processing);
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.request});

  final Future<SourceVideo> request;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SourceVideo>(
      future: request,
      builder: (context, snapshot) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: _cardContent(context, snapshot),
      ),
    );
  }
}

Widget _cardContent(BuildContext context, AsyncSnapshot<SourceVideo> snapshot) {
  if (snapshot.error case final error?) {
    return Text(
      errorMessageFor(error),
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    );
  }
  if (snapshot.data case final video?) {
    return _VideoSummary(video: video);
  }
  return const LinearProgressIndicator();
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
    return const ColoredBox(
      color: AppColors.background,
      child: Icon(Icons.play_circle_outline, color: AppColors.accent),
    );
  }
}

class _OnDeviceNote extends StatelessWidget {
  const _OnDeviceNote();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.lock_outline, size: 18, color: AppColors.textMuted),
        SizedBox(width: 10),
        Expanded(
          child: HintText(
            "The video's audio is sent to Groq to write the script. The "
            'video itself stays on your phone.',
          ),
        ),
      ],
    );
  }
}
