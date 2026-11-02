import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/core/presentation/bottom_action.dart';
import 'package:status_studio/src/core/presentation/flow_app_bar.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/presentation/section_label.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/source/data/video_source.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/source/domain/youtube_link.dart';
import 'package:status_studio/src/features/transcript/application/script_progress_controller.dart';
import 'package:status_studio/src/routing/app_router.dart';
import 'package:status_studio/src/theme/app_theme.dart';

class SourceScreen extends ConsumerStatefulWidget {
  const SourceScreen({super.key});

  @override
  ConsumerState<SourceScreen> createState() => _SourceScreenState();
}

class _SourceScreenState extends ConsumerState<SourceScreen> {
  final _linkController = TextEditingController();
  Future<SourceVideo>? _videoRequest;
  var _language = ScriptLanguage.auto;
  var _showLinkError = false;

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const FlowAppBar(title: 'New reel', stepLabel: 'Step 1 of 4'),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SectionLabel('YouTube link'),
          _LinkField(
            controller: _linkController,
            errorText: _showLinkError
                ? "That doesn't look like a YouTube link."
                : null,
            onChanged: _onLinkChanged,
            onPaste: _pasteLink,
          ),
          if (_videoRequest case final request?) _VideoCard(request: request),
          const SizedBox(height: 8),
          const HintText('Any video, any length.'),
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
          onPressed: _getScript,
          child: const Text('Get the script'),
        ),
      ),
    );
  }

  void _onLinkChanged(String link) {
    setState(() {
      _showLinkError = false;
      _videoRequest = _requestVideo(link);
    });
  }

  Future<SourceVideo>? _requestVideo(String link) {
    try {
      final videoId = parseYouTubeVideoId(link);
      // The card shows a failure once it builds; ignore() keeps the error
      // from being reported as unhandled before then.
      return ref.read(videoSourceProvider).fetchVideo(videoId)..ignore();
    } on InvalidYouTubeLinkException {
      return null;
    }
  }

  Future<void> _pasteLink() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final link = clip?.text ?? '';
    _linkController.text = link;
    _onLinkChanged(link);
  }

  Future<void> _getScript() async {
    final request = _videoRequest;
    if (request == null) {
      setState(() => _showLinkError = true);
      return;
    }
    final SourceVideo video;
    try {
      video = await request;
    } catch (_) {
      // The video card already shows why; stay on this screen.
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

class _LinkField extends StatelessWidget {
  const _LinkField({
    required this.controller,
    required this.errorText,
    required this.onChanged,
    required this.onPaste,
  });

  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<String> onChanged;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.url,
      autocorrect: false,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'https://youtu.be/…',
        errorText: errorText,
        border: const OutlineInputBorder(),
        suffixIcon: TextButton(onPressed: onPaste, child: const Text('Paste')),
      ),
    );
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
        const Icon(Icons.play_circle_outline, color: AppColors.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              HintText('${video.channel} · ${formatTimestamp(video.duration)}'),
            ],
          ),
        ),
      ],
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
            'The script is written on your phone. Only the download uses the '
            'internet.',
          ),
        ),
      ],
    );
  }
}
