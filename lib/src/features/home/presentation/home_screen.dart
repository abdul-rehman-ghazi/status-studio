import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/presentation/script_text.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/branding/presentation/logo_mark.dart';
import 'package:status_studio/src/features/library/application/recent_reels_controller.dart';
import 'package:status_studio/src/features/library/domain/recent_reel.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/settings/application/settings_controller.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/transcript/application/saved_scripts_controller.dart';
import 'package:status_studio/src/features/transcript/application/script_progress_controller.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';
import 'package:status_studio/src/routing/app_router.dart';
import 'package:status_studio/src/theme/app_theme.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Loads the Settings model choice early, so the first script after
    // launch uses it rather than the default.
    ref.watch(whisperModelSettingProvider);
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
                      'Paste a YouTube link, then pick the lines from its '
                      'script',
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

/// Finished reels and processed videos' scripts in one list, newest first.
List<Widget> _newestFirst({
  required List<RecentReel> reels,
  required List<SavedScript> scripts,
}) {
  final dated = <({DateTime at, Widget row})>[
    for (final reel in reels)
      (at: reel.createdAt, row: _RecentReelRow(reel: reel)),
    for (final script in scripts)
      (at: script.saved.savedAt, row: _SavedScriptRow(script: script)),
  ]..sort((a, b) => b.at.compareTo(a.at));
  return [for (final entry in dated) entry.row];
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
    if (await _confirmDelete(context)) {
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
        'Script · $language · ${formatTimestamp(script.video.duration)} · '
        '${formatDayMonth(script.saved.savedAt.toLocal())}',
      ),
      onTap: () => _openScript(context, ref),
      onLongPress: () => unawaited(_offerDelete(context, ref)),
    );
  }

  /// The same path as pasting the link again: Processing finds the saved
  /// script and goes straight on to Script.
  void _openScript(BuildContext context, WidgetRef ref) {
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
    if (await _confirmDelete(context)) {
      await ref.read(savedScriptsProvider.notifier).delete(script);
    }
  }
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

/// Asks with a one-item sheet, as long-press menus do on Android.
Future<bool> _confirmDelete(BuildContext context) async {
  final delete = await showModalBottomSheet<bool>(
    context: context,
    builder: (context) => SafeArea(
      child: ListTile(
        leading: const Icon(Icons.delete_outline),
        title: const Text('Delete'),
        onTap: () => Navigator.of(context).pop(true),
      ),
    ),
  );
  return delete ?? false;
}
