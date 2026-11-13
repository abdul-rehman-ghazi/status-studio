import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/presentation/script_text.dart';
import 'package:status_studio/src/core/presentation/section_label.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/branding/presentation/logo_mark.dart';
import 'package:status_studio/src/features/join/data/linked_clip_store.dart';
import 'package:status_studio/src/features/library/domain/recent_entries.dart';
import 'package:status_studio/src/features/library/presentation/unfinished_work_actions.dart';
import 'package:status_studio/src/features/reel/application/fine_tune_drafts_controller.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/reel/domain/fine_tune_draft.dart';
import 'package:status_studio/src/features/source/application/is_video_kept.dart';
import 'package:status_studio/src/features/topic/application/link_sessions_controller.dart';
import 'package:status_studio/src/features/topic/domain/link_session.dart';
import 'package:status_studio/src/features/transcript/application/script_opening_notice.dart';
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
            const _CarryOnSection(),
            const _HistoryRow(),
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
              subtitle: 'Pick moments from a long video',
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

/// Unfinished work only (spec FR-44): link sessions and kept fine-tunes,
/// newest first, at most three; hidden when there is none.
class _CarryOnSection extends ConsumerWidget {
  const _CarryOnSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = recentEntries(
      RecentLists(
        fineTunes: ref.watch(fineTuneDraftsProvider).value ?? const [],
        linkSessions: ref.watch(linkSessionsProvider).value ?? const [],
      ),
    );
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Carry on'),
        const SizedBox(height: 4),
        for (final entry in entries)
          switch (entry) {
            FineTuneEntry(:final fineTune) => _FineTuneRow(fineTune: fineTune),
            LinkSessionEntry(:final session) => _LinkSessionRow(
              session: session,
            ),
          },
        const SizedBox(height: 12),
      ],
    );
  }
}

/// Always shown: History holds every video, its reels and scripts (spec
/// FR-44).
class _HistoryRow extends StatelessWidget {
  const _HistoryRow();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.history, color: context.palette.accent),
      title: Text('History', style: Theme.of(context).textTheme.titleMedium),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(AppRoutes.history),
    );
  }
}

/// "From a link · " before a clip joined from a link (spec FR-37), whose
/// name is the video's title.
String _linkNote(WidgetRef ref, String videoId) =>
    ref.watch(linkedClipProvider(videoId)).value == null
    ? ''
    : 'From a link · ';

/// A fine-tune kept at Fine-tune, to continue later (FR-24). Long-press
/// offers Delete, which removes the fine-tune only: the script stays for
/// History (spec FR-44; until M54 the script went too).
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
            : chooseAgainHint,
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
    try {
      await continueFineTune(context, ref, fineTune);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _offerDeleteProgress(BuildContext context, WidgetRef ref) async {
    if (!await confirmAction(context, 'Delete')) {
      return;
    }
    await ref.read(fineTuneDraftsProvider.notifier).delete(fineTune);
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

/// A link left on Review cuts (FR-38). Tap opens Review cuts with the cuts
/// as left; long-press offers Delete, which keeps the saved moments.
class _LinkSessionRow extends ConsumerWidget {
  const _LinkSessionRow({required this.session});

  final LinkSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const _LinkThumbnail(),
      title: ScriptText(session.request.video.title, maxLines: 1),
      subtitle: Text(
        'Script · Review cuts · '
        '${formatDayMonth(session.savedAt.toLocal())}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        'Continue',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: context.palette.accent,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: () => context.push(AppRoutes.reviewCuts, extra: session),
      onLongPress: () => unawaited(_offerDelete(context, ref)),
    );
  }

  Future<void> _offerDelete(BuildContext context, WidgetRef ref) async {
    if (await confirmAction(context, 'Delete')) {
      await ref.read(linkSessionsProvider.notifier).delete(session);
    }
  }
}

class _LinkThumbnail extends StatelessWidget {
  const _LinkThumbnail();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 48,
        height: 64,
        child: ColoredBox(
          color: context.palette.surface,
          child: Icon(Icons.link, color: context.palette.textMuted),
        ),
      ),
    );
  }
}
