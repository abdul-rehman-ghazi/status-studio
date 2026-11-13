import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/presentation/screen_title.dart';
import 'package:status_studio/src/core/presentation/script_text.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/library/application/history_provider.dart';
import 'package:status_studio/src/features/library/application/recent_reels_controller.dart';
import 'package:status_studio/src/features/library/domain/recent_reel.dart';
import 'package:status_studio/src/features/library/domain/video_history.dart';
import 'package:status_studio/src/features/library/presentation/unfinished_work_actions.dart';
import 'package:status_studio/src/features/source/application/video_thumbnail.dart';
import 'package:status_studio/src/routing/app_router.dart';
import 'package:status_studio/src/theme/app_theme.dart';

enum _HistoryFilter {
  all('All'),
  links('Links'),
  myVideos('My videos');

  const _HistoryFilter(this.label);

  final String label;

  bool shows(VideoHistory group) => switch (this) {
    all => true,
    links => group.key is LinkedVideoKey,
    myVideos => group.key is LocalVideoKey,
  };
}

/// History (spec FR-44): one folding group per video, newest activity
/// first, with its unfinished work and its reels.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  var _filter = _HistoryFilter.all;
  final _unfolded = <HistoryVideo>{};

  /// iOS has no links, so it has nothing to filter.
  bool get _hasLinks => defaultTargetPlatform == TargetPlatform.android;

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyProvider);
    return Scaffold(
      appBar: AppBar(title: const ScreenTitle('History')),
      body: switch (history) {
        AsyncData(:final value) => _groups(value),
        AsyncError() => const _EmptyHistory(),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _groups(List<VideoHistory> all) {
    final shown = all.where(_filter.shows).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        if (_hasLinks) _filterChips(),
        if (shown.isEmpty) const _EmptyHistory(),
        for (final group in shown)
          _HistoryGroup(
            group: group,
            unfolded: _unfolded.contains(group.key),
            onFold: () => setState(() => _toggle(group.key)),
          ),
      ],
    );
  }

  void _toggle(HistoryVideo key) {
    if (!_unfolded.remove(key)) {
      _unfolded.add(key);
    }
  }

  Widget _filterChips() => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Wrap(
      spacing: 8,
      children: [
        for (final filter in _HistoryFilter.values)
          ChoiceChip(
            label: Text(filter.label),
            selected: _filter == filter,
            onSelected: (_) => setState(() => _filter = filter),
          ),
      ],
    ),
  );
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Text(
        'Videos you make reels from will appear here.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: context.palette.textMuted),
      ),
    );
  }
}

/// A video's parent row and, unfolded, its unfinished work and reels.
class _HistoryGroup extends StatelessWidget {
  const _HistoryGroup({
    required this.group,
    required this.unfolded,
    required this.onFold,
  });

  final VideoHistory group;
  final bool unfolded;
  final VoidCallback onFold;

  @override
  Widget build(BuildContext context) {
    final unfinished = group.unfinished;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _ParentRow(
            group: group,
            unfolded: unfolded,
            onFold: onFold,
          ),
          if (unfolded && unfinished != null) _UnfinishedRow(unfinished),
          if (unfolded)
            for (final reel in group.reels) _ReelRow(reel),
        ],
      ),
    );
  }
}

class _ParentRow extends StatelessWidget {
  const _ParentRow({
    required this.group,
    required this.unfolded,
    required this.onFold,
  });

  final VideoHistory group;
  final bool unfolded;
  final VoidCallback onFold;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onFold,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
        child: Row(
          children: [
            _GroupThumbnail(group),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ScriptText(group.title, maxLines: 2),
                  HintText(groupSummary(group)),
                ],
              ),
            ),
            Icon(unfolded ? Icons.expand_less : Icons.expand_more),
          ],
        ),
      ),
    );
  }
}

/// `<length> · script saved · <n> reels`, only the parts that exist.
String groupSummary(VideoHistory group) {
  final length = group.facts.length;
  final reelCount = group.reels.length;
  return [
    if (length != null) formatTimestamp(length),
    if (group.scriptSaved) 'script saved',
    if (reelCount > 0) reelCount == 1 ? '1 reel' : '$reelCount reels',
  ].join(' · ');
}

/// YouTube's picture for a link, the kept video's first frame for a local
/// one; an icon when there is neither.
class _GroupThumbnail extends ConsumerWidget {
  const _GroupThumbnail(this.group);

  final VideoHistory group;

  static const _width = 80.0;
  static const _height = 45.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: _width,
        height: _height,
        child: _picture(ref) ?? _icon(context),
      ),
    );
  }

  Widget? _picture(WidgetRef ref) {
    final url = group.facts.thumbnailUrl;
    if (url != null) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => _icon(context),
      );
    }
    final key = group.key;
    if (key is! LocalVideoKey) {
      return null;
    }
    final frame = ref.watch(videoThumbnailProvider(key.videoId)).value;
    return frame == null
        ? null
        : Image.file(
            frame,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => _icon(context),
          );
  }

  Widget _icon(BuildContext context) => ColoredBox(
    color: context.palette.background,
    child: Icon(
      group.key is LinkedVideoKey
          ? Icons.smart_display_outlined
          : Icons.movie_outlined,
      color: context.palette.textMuted,
    ),
  );
}

/// "Review cuts · 4 moments" or "Fine-tune", when it was left, Continue.
class _UnfinishedRow extends ConsumerStatefulWidget {
  const _UnfinishedRow(this.work);

  final UnfinishedWork work;

  @override
  ConsumerState<_UnfinishedRow> createState() => _UnfinishedRowState();
}

class _UnfinishedRowState extends ConsumerState<_UnfinishedRow> {
  var _opening = false;

  @override
  Widget build(BuildContext context) {
    final work = widget.work;
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
      leading: Icon(
        work is UnfinishedLink ? Icons.content_cut : Icons.tune,
        color: context.palette.accent,
      ),
      title: Text(_label(work)),
      subtitle: Text('Left ${formatDayMonth(work.savedAt.toLocal())}'),
      trailing: Text(
        'Continue',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: context.palette.accent,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: () => unawaited(_continue()),
    );
  }

  String _label(UnfinishedWork work) => switch (work) {
    UnfinishedLink(:final session) => _momentsLabel(session.cuts?.length ?? 0),
    UnfinishedFineTune() => 'Fine-tune',
  };

  String _momentsLabel(int count) =>
      'Review cuts · $count ${count == 1 ? 'moment' : 'moments'}';

  /// One tap at a time: reading a kept fine-tune takes a moment.
  Future<void> _continue() async {
    if (_opening) {
      return;
    }
    setState(() => _opening = true);
    try {
      await switch (widget.work) {
        UnfinishedLink(:final session) => context.push(
          AppRoutes.reviewCuts,
          extra: session,
        ),
        UnfinishedFineTune(:final fineTune) => continueFineTune(
          context,
          ref,
          fineTune,
        ),
      };
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }
}

/// A reel of the video: its picture, name, length, date and the source
/// times it used. Tap opens Done; long-press offers Delete (FR-11).
class _ReelRow extends ConsumerWidget {
  const _ReelRow(this.reel);

  final RecentReel reel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => context.push(AppRoutes.doneFor(reel.id)),
      onLongPress: () => unawaited(_offerDelete(context, ref)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ReelThumbnail(reel),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ScriptText(reel.title, maxLines: 1),
                  HintText(
                    '${formatSeconds(reel.duration)} · '
                    '${formatDayMonth(reel.createdAt)}',
                  ),
                  if (reel.usedRanges.isNotEmpty) _RangeChips(reel),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _offerDelete(BuildContext context, WidgetRef ref) async {
    if (await confirmAction(context, 'Delete')) {
      await ref.read(recentReelsProvider.notifier).delete(reel.id);
    }
  }
}

/// One chip per source range the reel used, `2:14–2:40`, in source order.
class _RangeChips extends StatelessWidget {
  const _RangeChips(this.reel);

  final RecentReel reel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final range in reel.usedRanges)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: context.palette.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${formatTimestamp(range.start)}–${formatTimestamp(range.end)}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _ReelThumbnail extends StatelessWidget {
  const _ReelThumbnail(this.reel);

  final RecentReel reel;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 36,
        height: 48,
        child: Image.file(
          File(reel.thumbnailPath),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => ColoredBox(
            color: context.palette.background,
            child: Icon(Icons.movie_outlined, color: context.palette.textMuted),
          ),
        ),
      ),
    );
  }
}
