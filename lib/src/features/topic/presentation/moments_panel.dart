import 'package:flutter/material.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/features/library/domain/recent_reel.dart';
import 'package:status_studio/src/features/topic/domain/cut_edits.dart';
import 'package:status_studio/src/features/topic/domain/topic_cut.dart';
import 'package:status_studio/src/features/topic/domain/used_marks.dart';
import 'package:status_studio/src/features/topic/presentation/cut_card.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// What the moments panel shows (spec FR-46).
class MomentsPanelContent {
  const MomentsPanelContent({
    required this.cuts,
    required this.preparingPlay,
    required this.usedReels,
  });

  final List<ReviewCut> cuts;

  /// The moment being downloaded to play, if any.
  final TopicCut? preparingPlay;

  /// This video's reels, for the `In <reel name>` tags (spec FR-44).
  final List<RecentReel> usedReels;
}

/// What a moment card can do.
class MomentActions {
  const MomentActions({
    required this.onToggle,
    required this.onPlay,
    required this.onReorder,
  });

  final ValueChanged<int> onToggle;
  final ValueChanged<TopicCut> onPlay;
  final void Function(int from, int to) onReorder;
}

/// Your moments over the script (spec FR-46), reached from the footer's
/// Moments wherever the script is scrolled to. A tap on the shade closes it.
class MomentsPanel extends StatelessWidget {
  const MomentsPanel({
    required this.content,
    required this.actions,
    required this.onClose,
    super.key,
  });

  final MomentsPanelContent content;
  final MomentActions actions;
  final VoidCallback onClose;

  static const _heightShare = 0.75;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ModalBarrier(
          color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.4),
          onDismiss: onClose,
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: LayoutBuilder(
            builder: (context, constraints) => ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * _heightShare,
              ),
              child: _panel(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _panel(BuildContext context) {
    return Material(
      color: context.palette.surface,
      elevation: 8,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
            title: Text(
              'Your moments (${content.cuts.length})',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            trailing: IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: onClose,
            ),
          ),
          Flexible(child: content.cuts.isEmpty ? const _NoMoments() : _list()),
        ],
      ),
    );
  }

  Widget _list() {
    return CustomScrollView(
      shrinkWrap: true,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          sliver: SliverReorderableList(
            itemCount: content.cuts.length,
            onReorderItem: actions.onReorder,
            itemBuilder: (context, index) {
              final review = content.cuts[index];
              return ReorderableDelayedDragStartListener(
                key: ValueKey(review.cut.start),
                index: index,
                child: CutCard(
                  review: review,
                  onToggle: () => actions.onToggle(index),
                  onPlay: () => actions.onPlay(review.cut),
                  preparingPlay: review.cut == content.preparingPlay,
                  usedIn: newestReelOver(
                    review.cut.start,
                    review.cut.end,
                    content.usedReels,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NoMoments extends StatelessWidget {
  const _NoMoments();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: HintText(
        'No moments yet. Tap the first line of a moment in the script, '
        'then the last.',
      ),
    );
  }
}
