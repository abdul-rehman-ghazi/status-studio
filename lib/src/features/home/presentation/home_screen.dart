import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/core/presentation/script_text.dart';
import 'package:status_studio/src/core/presentation/section_label.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/branding/presentation/logo_mark.dart';
import 'package:status_studio/src/features/join/data/linked_clip_store.dart';
import 'package:status_studio/src/features/library/application/recent_reels_controller.dart';
import 'package:status_studio/src/features/library/domain/recent_entries.dart';
import 'package:status_studio/src/features/library/domain/recent_reel.dart';
import 'package:status_studio/src/features/reel/application/fine_tune_draft_saver.dart';
import 'package:status_studio/src/features/reel/application/fine_tune_drafts_controller.dart';
import 'package:status_studio/src/features/reel/application/fine_tune_resumer.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/reel/domain/fine_tune_draft.dart';
import 'package:status_studio/src/features/source/application/is_video_kept.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/transcript/application/saved_scripts_controller.dart';
import 'package:status_studio/src/features/transcript/application/script_opening_notice.dart';
import 'package:status_studio/src/features/transcript/application/script_progress_controller.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';
import 'package:status_studio/src/routing/app_router.dart';
import 'package:status_studio/src/theme/app_theme.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            const _Header(),
            const SizedBox(height: 24),
            _StartCards(
              onVideo: () => _startNewReel(context, ref, AppRoutes.source),
              onLink: () => _startNewReel(context, ref, AppRoutes.link),
            ),
            const SizedBox(height: 28),
            const _RecentSection(),
          ],
        ),
      ),
    );
  }

  void _startNewReel(BuildContext context, WidgetRef ref, String route) {
    ref.read(scriptOpeningNoticeProvider.notifier).clear();
    ref.read(reelDraftProvider.notifier).startNew();
    unawaited(context.push(route));
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const LogoMark(size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Status Studio',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => context.push(AppRoutes.settings),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Clip any video into a status, from its own script.',
          style: textTheme.bodyMedium?.copyWith(
            color: context.palette.textMuted,
          ),
        ),
      ],
    );
  }
}

/// From my videos, and on Android From a YouTube link (spec FR-35), side
/// by side. iOS has no links, so it keeps the one New reel card.
class _StartCards extends StatelessWidget {
  const _StartCards({required this.onVideo, required this.onLink});

  final VoidCallback onVideo;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return _StartCard(
        icon: Icons.add_circle,
        title: 'New reel',
        subtitle: 'Choose or share a video, then trim and caption it',
        onTap: onVideo,
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _StartCard(
              icon: Icons.video_library,
              title: 'From my videos',
              subtitle: 'Choose or share a trimmed video',
              onTap: onVideo,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StartCard(
              icon: Icons.link,
              title: 'From a YouTube link',
              subtitle: 'Find a topic in a long video',
              onTap: onLink,
            ),
          ),
        ],
      ),
    );
  }
}

class _StartCard extends StatelessWidget {
  const _StartCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final onAccent = context.palette.onAccent;
    return Material(
      color: context.palette.accent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: onAccent, size: 32),
              const SizedBox(height: 10),
              Text(
                title,
                style: textTheme.titleMedium?.copyWith(
                  color: onAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: textTheme.bodySmall?.copyWith(color: onAccent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentSection extends ConsumerWidget {
  const _RecentSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = _newestFirst(
      reels: ref.watch(recentReelsProvider).value ?? const [],
      scripts: ref.watch(savedScriptsProvider).value ?? const [],
      fineTunes: ref.watch(fineTuneDraftsProvider).value ?? const [],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Recent'),
        const SizedBox(height: 4),
        if (rows.isEmpty) const _EmptyRecent() else ...rows,
      ],
    );
  }
}

/// Finished reels, scripts and fine-tunes to continue in one list, newest
/// first.
List<Widget> _newestFirst({
  required List<RecentReel> reels,
  required List<SavedScript> scripts,
  required List<SavedFineTune> fineTunes,
}) {
  final entries = recentEntries(
    reels: reels,
    scripts: scripts,
    fineTunes: fineTunes,
  );
  return [
    for (final entry in entries)
      switch (entry) {
        ReelEntry(:final reel) => _RecentReelRow(reel: reel),
        ScriptEntry(:final script) => _SavedScriptRow(script: script),
        FineTuneEntry(:final fineTune) => _FineTuneRow(fineTune: fineTune),
      },
  ];
}

class _EmptyRecent extends StatelessWidget {
  const _EmptyRecent();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        'Your reels and scripts will appear here.',
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: context.palette.textMuted),
      ),
    );
  }
}

/// Thumbnail, first caption line, duration and date (FR-11). Tap opens
/// Done; long-press offers Delete.
class _RecentReelRow extends ConsumerWidget {
  const _RecentReelRow({required this.reel});

  final RecentReel reel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 48,
          height: 64,
          child: Image.file(
            File(reel.thumbnailPath),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => ColoredBox(
              color: context.palette.surface,
              child: Icon(
                Icons.movie_outlined,
                color: context.palette.textMuted,
              ),
            ),
          ),
        ),
      ),
      title: ScriptText(reel.title, maxLines: 1),
      subtitle: Text(
        '${formatSeconds(reel.duration)} · ${formatDayMonth(reel.createdAt)}',
      ),
      onTap: () => context.push(AppRoutes.doneFor(reel.id)),
      onLongPress: () => unawaited(_offerDelete(context, ref)),
    );
  }

  Future<void> _offerDelete(BuildContext context, WidgetRef ref) async {
    if (await _confirmAction(context, 'Delete')) {
      await ref.read(recentReelsProvider.notifier).delete(reel.id);
    }
  }
}

/// "From a link · " before a clip joined from a link (spec FR-37), whose
/// name is its topic.
String _linkNote(WidgetRef ref, String videoId) =>
    ref.watch(linkedClipProvider(videoId)).value == null
    ? ''
    : 'From a link · ';

/// A processed video's whole script, before any clip is cut from it. Tap
/// reopens Script without downloading (FR-14); long-press offers Delete.
class _SavedScriptRow extends ConsumerWidget {
  const _SavedScriptRow({required this.script});

  final SavedScript script;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = scriptLanguageLabel(
      script.language,
      script.saved.transcript.languageCode,
    );
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const _ScriptThumbnail(),
      title: ScriptText(script.video.title, maxLines: 1),
      subtitle: Text(
        _isKept(ref)
            ? '${_linkNote(ref, script.video.videoId)}'
                  'Script · $language · ${formatTimestamp(script.video.duration)} · '
                  '${formatDayMonth(script.saved.savedAt.toLocal())}'
            : _chooseAgainHint,
      ),
      onTap: () => unawaited(_openScript(context, ref)),
      onLongPress: () => unawaited(_offerDelete(context, ref)),
    );
  }

  bool _isKept(WidgetRef ref) =>
      ref.watch(isVideoKeptProvider(script.video.videoId)).value ?? true;

  /// Opens Fine-tune · Video with the saved script read back into the reel
  /// (nothing is uploaded for a saved script, FR-14). With the kept video
  /// gone the user is asked for it again first (spec FR-1).
  Future<void> _openScript(BuildContext context, WidgetRef ref) async {
    if (!await _isStillKept(ref, script.video.videoId)) {
      if (context.mounted) {
        _askForTheVideoAgain(context, ref, script.video.videoId);
      }
      return;
    }
    if (!context.mounted) {
      return;
    }
    ref.read(scriptOpeningNoticeProvider.notifier).clear();
    ref.read(reelDraftProvider.notifier)
      ..startNew()
      ..setVideo(script.video)
      ..setLanguage(script.language);
    ref
        .read(scriptProgressProvider.notifier)
        .start(script.video, script.language);
    unawaited(context.push(AppRoutes.fineTune));
  }

  Future<void> _offerDelete(BuildContext context, WidgetRef ref) async {
    if (await _confirmAction(context, 'Delete')) {
      await ref.read(savedScriptsProvider.notifier).delete(script);
    }
  }
}

const _chooseAgainHint = 'Choose or share the video again';

/// A row shows "choose again" from a cached answer; the video may have been
/// imported since, so a tap that finds "gone" looks at the phone again.
Future<bool> _isStillKept(WidgetRef ref, String videoId) async {
  if (ref.read(isVideoKeptProvider(videoId)).value ?? true) {
    return true;
  }
  return ref.refresh(isVideoKeptProvider(videoId).future);
}

/// The kept video is gone: say so and open Source. The script and the kept
/// fine-tune stay, and the same video chosen again finds them (spec FR-1).
void _askForTheVideoAgain(BuildContext context, WidgetRef ref, String videoId) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(errorMessageFor(KeptVideoMissingException(videoId))),
    ),
  );
  ref.read(reelDraftProvider.notifier).startNew();
  context.push(AppRoutes.source);
}

class _ScriptThumbnail extends StatelessWidget {
  const _ScriptThumbnail();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 48,
        height: 64,
        child: ColoredBox(
          color: context.palette.surface,
          child: Icon(Icons.subject, color: context.palette.textMuted),
        ),
      ),
    );
  }
}

/// A fine-tune kept at Fine-tune, to continue later (FR-24). Long-press
/// offers Delete, which removes the fine-tune and the video's script.
class _FineTuneRow extends ConsumerStatefulWidget {
  const _FineTuneRow({required this.fineTune});

  final SavedFineTune fineTune;

  @override
  ConsumerState<_FineTuneRow> createState() => _FineTuneRowState();
}

class _FineTuneRowState extends ConsumerState<_FineTuneRow> {
  var _opening = false;

  SavedFineTune get fineTune => widget.fineTune;

  bool get _isKept =>
      ref.watch(isVideoKeptProvider(fineTune.video.videoId)).value ?? true;

  @override
  Widget build(BuildContext context) {
    final clipLength = fineTune.draft.clip.length;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const _FineTuneThumbnail(),
      title: ScriptText(fineTune.video.title, maxLines: 1),
      subtitle: Text(
        _isKept
            ? '${_linkNote(ref, fineTune.video.videoId)}'
                  'Fine-tune · ${formatSeconds(clipLength)} · '
                  '${formatDayMonth(fineTune.draft.savedAt.toLocal())}'
            : _chooseAgainHint,
      ),
      trailing: Text(
        'Continue',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: context.palette.accent,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: () => unawaited(_continue(context, ref)),
      onLongPress: () => unawaited(_offerDeleteProgress(context, ref)),
    );
  }

  /// Reading the saved script takes a moment; a second tap in that time
  /// would open every screen twice.
  Future<void> _continue(BuildContext context, WidgetRef ref) async {
    if (_opening) {
      return;
    }
    setState(() => _opening = true);
    if (!await _isStillKept(ref, fineTune.video.videoId)) {
      if (mounted) {
        setState(() => _opening = false);
      }
      if (context.mounted) {
        _askForTheVideoAgain(context, ref, fineTune.video.videoId);
      }
      return;
    }
    final FineTuneResume outcome;
    try {
      outcome = await ref.read(fineTuneResumerProvider).resume(fineTune);
    } finally {
      if (mounted) {
        setState(() => _opening = false);
      }
    }
    if (!context.mounted) {
      return;
    }
    _open(context, ref, outcome);
    if (outcome is! FineTuneReady) {
      // The resumer deleted the kept fine-tune.
      ref.invalidate(fineTuneDraftsProvider);
    }
  }

  void _open(BuildContext context, WidgetRef ref, FineTuneResume outcome) {
    final video = fineTune.video;
    final notices = ref.read(scriptOpeningNoticeProvider.notifier);
    final draft = ref.read(reelDraftProvider.notifier);
    notices.clear();
    switch (outcome) {
      case FineTuneReady(draft: final restored):
        draft.restore(restored);
        unawaited(ref.read(fineTuneDraftSaverProvider).rememberKept(restored));
        _startScript(ref);
        context.push(AppRoutes.fineTune);
      case FineTuneScriptGone(:final startOver):
        draft.restore(startOver);
        // Lyrics offers to get the script again; nothing starts unasked.
        notices.show(video.videoId, ScriptOpeningNotice.fineTuneScriptGone);
        context.push(AppRoutes.fineTune);
      case FineTuneScriptChanged(:final startOver):
        draft.restore(startOver);
        notices.show(video.videoId, ScriptOpeningNotice.fineTuneScriptChanged);
        _startScript(ref);
        context.push(AppRoutes.fineTune);
    }
  }

  /// Reads the saved script back, or resumes one still being written. A
  /// fine-tune kept before it had lines starts nothing: Lyrics offers the
  /// script (M30).
  void _startScript(WidgetRef ref) {
    if (fineTune.draft.lines == null) {
      return;
    }
    ref
        .read(scriptProgressProvider.notifier)
        .start(fineTune.video, fineTune.draft.language);
  }

  Future<void> _offerDeleteProgress(BuildContext context, WidgetRef ref) async {
    if (!await _confirmAction(context, 'Delete')) {
      return;
    }
    await ref.read(fineTuneDraftsProvider.notifier).delete(fineTune);
    await _deleteItsScript(ref);
  }

  /// Without this the script row would show again where the fine-tune was.
  /// A fine-tune that never had lines leaves the video's scripts alone.
  Future<void> _deleteItsScript(WidgetRef ref) async {
    if (fineTune.draft.lines == null) {
      return;
    }
    final scripts = await ref.read(savedScriptsProvider.future);
    final script = scripts.where(
      (saved) =>
          saved.video.videoId == fineTune.video.videoId &&
          saved.language == fineTune.draft.language,
    );
    for (final saved in script) {
      await ref.read(savedScriptsProvider.notifier).delete(saved);
    }
  }
}

class _FineTuneThumbnail extends StatelessWidget {
  const _FineTuneThumbnail();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 48,
        height: 64,
        child: ColoredBox(
          color: context.palette.surface,
          child: Icon(Icons.tune, color: context.palette.textMuted),
        ),
      ),
    );
  }
}

/// Asks with a one-item sheet, as long-press menus do on Android.
Future<bool> _confirmAction(BuildContext context, String label) async {
  final delete = await showModalBottomSheet<bool>(
    context: context,
    builder: (context) => SafeArea(
      child: ListTile(
        leading: const Icon(Icons.delete_outline),
        title: Text(label),
        onTap: () => Navigator.of(context).pop(true),
      ),
    ),
  );
  return delete ?? false;
}
