import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/presentation/section_label.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/source/application/linked_video_reader.dart';
import 'package:status_studio/src/features/source/domain/linked_video.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/topic/domain/moment_source.dart';
import 'package:status_studio/src/features/topic/domain/topic_request.dart';
import 'package:status_studio/src/features/topic/presentation/replace_unfinished_dialog.dart';
import 'package:status_studio/src/features/topic/presentation/script_fields.dart';
import 'package:status_studio/src/routing/app_router.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// From a link (spec FR-35, FR-50, Android only): paste or share a link,
/// read what the video is, then the output language and Get the script
/// (FR-43).
class LinkSection extends ConsumerStatefulWidget {
  const LinkSection({this.sharedLink, super.key});

  /// A link shared into the app; it is filled in and read at once.
  final String? sharedLink;

  @override
  ConsumerState<LinkSection> createState() => _LinkSectionState();
}

class _LinkSectionState extends ConsumerState<LinkSection> {
  final _linkField = TextEditingController();
  Future<LinkedVideo>? _videoRequest;

  /// The read video, once [_videoRequest] succeeds.
  LinkedVideo? _video;

  @override
  void initState() {
    super.initState();
    final shared = widget.sharedLink;
    if (shared == null) {
      return;
    }
    _linkField.text = shared;
    _readLink();
  }

  @override
  void dispose() {
    _linkField.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Video link'),
        TextField(
          controller: _linkField,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _readLink(),
          decoration: InputDecoration(
            hintText: 'Paste a video link',
            suffixIcon: IconButton(
              tooltip: 'Paste',
              icon: const Icon(Icons.content_paste),
              onPressed: () => unawaited(_paste()),
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _readLink,
          icon: const Icon(Icons.link),
          label: const Text('Read link'),
        ),
        if (_videoRequest case final request?) _LinkedVideoCard(request),
        if (_video case final video?) ...[
          const SizedBox(height: 8),
          ScriptFields(
            key: ValueKey(video.videoKey),
            source: LinkedMoments(video),
            onGet: (request) => unawaited(_getScript(request)),
          ),
        ],
      ],
    );
  }

  /// One unfinished piece of work per linked video (spec FR-43): starting
  /// again asks first, then deletes the old one.
  Future<void> _getScript(TopicRequest request) async {
    if (!await clearUnfinishedLinkWork(context, ref, request.source.key)) {
      return;
    }
    if (mounted) await context.push(AppRoutes.reviewCuts, extra: request);
  }

  Future<void> _paste() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clip?.text?.trim();
    if (text == null || text.isEmpty || !mounted) {
      return;
    }
    _linkField.text = text;
    _readLink();
  }

  /// The card's FutureBuilder reports a failure; ignore() keeps it from
  /// being reported as unhandled before the card builds.
  void _readLink() {
    final link = _linkField.text.trim();
    if (link.isEmpty) {
      return;
    }
    final request = ref.read(linkedVideoReaderProvider).read(link)..ignore();
    setState(() {
      _videoRequest = request;
      _video = null;
    });
    unawaited(_keepWhenRead(request));
  }

  Future<void> _keepWhenRead(Future<LinkedVideo> request) async {
    try {
      final video = await request;
      if (mounted && identical(request, _videoRequest)) {
        setState(() => _video = video);
      }
    } on Object {
      // The card shows why.
    }
  }
}

class _LinkedVideoCard extends StatelessWidget {
  const _LinkedVideoCard(this.request);

  final Future<LinkedVideo> request;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LinkedVideo>(
      future: request,
      builder: (context, snapshot) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: _cardContent(context, snapshot),
      ),
    );
  }
}

Widget _cardContent(BuildContext context, AsyncSnapshot<LinkedVideo> snapshot) {
  if (snapshot.error case final error?) {
    return _ReadFailure(error);
  }
  if (snapshot.data case final video?) {
    return _LinkedVideoSummary(video: video);
  }
  return const LinearProgressIndicator();
}

/// The §8 message, and for a failure the app can't name, yt-dlp's own
/// words, selectable, so a report from the phone says what broke (M73).
class _ReadFailure extends StatelessWidget {
  const _ReadFailure(this.error);

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          errorMessageFor(error),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        if (error case SiteChangedException(:final reason)) ...[
          const SizedBox(height: 6),
          SelectableText(reason, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }
}

class _LinkedVideoSummary extends StatelessWidget {
  const _LinkedVideoSummary({required this.video});

  final LinkedVideo video;

  @override
  Widget build(BuildContext context) {
    final details = [
      if (!video.isYouTube) video.site,
      if (video.channel.isNotEmpty) video.channel,
      formatTimestamp(video.duration),
    ].join(' · ');
    return Row(
      children: [
        _LinkThumbnail(url: video.thumbnailUrl),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              HintText(details),
            ],
          ),
        ),
      ],
    );
  }
}

/// The site's own thumbnail, 16:9; its icon when there is none or it
/// fails.
class _LinkThumbnail extends StatelessWidget {
  const _LinkThumbnail({required this.url});

  final String? url;

  static const _width = 96.0;
  static const _height = 54.0;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: _width,
        height: _height,
        child: url == null
            ? const _LinkThumbnailIcon()
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) =>
                    const _LinkThumbnailIcon(),
              ),
      ),
    );
  }
}

class _LinkThumbnailIcon extends StatelessWidget {
  const _LinkThumbnailIcon();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.palette.background,
      child: Icon(Icons.smart_display_outlined, color: context.palette.accent),
    );
  }
}
