import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/core/presentation/script_text.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/branding/presentation/logo_mark.dart';
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
            _NewReelCard(onTap: () => _startNewReel(context, ref)),
            const SizedBox(height: 28),
            const _RecentSection(),
          ],
        ),
      ),
    );
  }

  void _startNewReel(BuildContext context, WidgetRef ref) {
    ref.read(scriptOpeningNoticeProvider.notifier).clear();
    ref.read(reelDraftProvider.notifier).startNew();
    context.push(AppRoutes.source);
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
          style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _NewReelCard extends StatelessWidget {
  const _NewReelCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: AppColors.accent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              const Icon(Icons.add_circle, color: AppColors.onAccent, size: 36),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'New reel',
                      style: textTheme.titleMedium?.copyWith(
                        color: AppColors.onAccent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Choose or share a video, then trim and caption it',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.onAccent,
                      ),
                    ),
                  ],
                ),
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
    final textTheme = Theme.of(context).textTheme;
    final rows = _newestFirst(
      reels: ref.watch(recentReelsProvider).value ?? const [],
      scripts: ref.watch(savedScriptsProvider).value ?? const [],
      fineTunes: ref.watch(fineTuneDraftsProvider).value ?? const [],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent',
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        'Your reels and scripts will appear here.',
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: AppColors.textMuted),
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
            errorBuilder: (context, error, stackTrace) => const ColoredBox(
              color: AppColors.surface,
              child: Icon(Icons.movie_outlined, color: AppColors.textMuted),
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
            ? 'Script · $language · ${formatTimestamp(script.video.duration)} · '
                  '${formatDayMonth(script.saved.savedAt.toLocal())}'
            : _chooseAgainHint,
      ),
      onTap: () => _openScript(context, ref),
      onLongPress: () => unawaited(_offerDelete(context, ref)),
    );
  }

  bool _isKept(WidgetRef ref) =>
      ref.watch(isVideoKeptProvider(script.video.videoId)).value ?? true;

  bool _isKeptNow(WidgetRef ref) =>
      ref.read(isVideoKeptProvider(script.video.videoId)).value ?? true;

  /// Processing finds the saved script and goes straight on to Script. With
  /// the kept video gone the user is asked for it again first (spec FR-1).
  void _openScript(BuildContext context, WidgetRef ref) {
    if (!_isKeptNow(ref)) {
      _askForTheVideoAgain(context, ref, script.video.videoId);
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
    context.push(AppRoutes.processing);
  }

  Future<void> _offerDelete(BuildContext context, WidgetRef ref) async {
    if (await _confirmAction(context, 'Delete')) {
      await ref.read(savedScriptsProvider.notifier).delete(script);
    }
  }
}

const _chooseAgainHint = 'Choose or share the video again';

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
      child: const SizedBox(
        width: 48,
        height: 64,
        child: ColoredBox(
          color: AppColors.surface,
          child: Icon(Icons.subject, color: AppColors.textMuted),
        ),
      ),
    );
  }
}

/// A fine-tune kept at Fine-tune, to continue later (FR-24). Long-press
/// offers Delete progress, which leaves the video's script.
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

  bool get _isKeptNow =>
      ref.read(isVideoKeptProvider(fineTune.video.videoId)).value ?? true;

  @override
  Widget build(BuildContext context) {
    final clipLength = fineTune.draft.clip.length;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const _FineTuneThumbnail(),
      title: ScriptText(fineTune.video.title, maxLines: 1),
      subtitle: Text(
        _isKept
            ? 'Fine-tune · ${formatSeconds(clipLength)} · '
                  '${formatDayMonth(fineTune.draft.savedAt.toLocal())}'
            : _chooseAgainHint,
      ),
      trailing: Text(
        'Continue',
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: AppColors.accent, fontWeight: FontWeight.w600),
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
    if (!_isKeptNow) {
      _askForTheVideoAgain(context, ref, fineTune.video.videoId);
      return;
    }
    setState(() => _opening = true);
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
        context
          ..push(AppRoutes.script)
          ..push(AppRoutes.fineTune);
      case FineTuneScriptGone(:final startOver):
        draft.restore(startOver);
        notices.show(video.videoId, ScriptOpeningNotice.fineTuneScriptGone);
        _startScript(ref);
        context.push(AppRoutes.processing);
      case FineTuneScriptChanged(:final startOver):
        draft.restore(startOver);
        notices.show(video.videoId, ScriptOpeningNotice.fineTuneScriptChanged);
        _startScript(ref);
        context.push(AppRoutes.script);
    }
  }

  void _startScript(WidgetRef ref) => ref
      .read(scriptProgressProvider.notifier)
      .start(fineTune.video, fineTune.draft.script.language);

  Future<void> _offerDeleteProgress(BuildContext context, WidgetRef ref) async {
    if (await _confirmAction(context, 'Delete progress')) {
      await ref.read(fineTuneDraftsProvider.notifier).delete(fineTune);
    }
  }
}

class _FineTuneThumbnail extends StatelessWidget {
  const _FineTuneThumbnail();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: const SizedBox(
        width: 48,
        height: 64,
        child: ColoredBox(
          color: AppColors.surface,
          child: Icon(Icons.tune, color: AppColors.textMuted),
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
