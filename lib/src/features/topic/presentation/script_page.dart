import 'package:flutter/material.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/presentation/script_text.dart';
import 'package:status_studio/src/core/presentation/section_label.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/topic/domain/block_run.dart';
import 'package:status_studio/src/features/topic/domain/cut_edits.dart';
import 'package:status_studio/src/features/topic/domain/topic_cut.dart';
import 'package:status_studio/src/features/topic/domain/transcript_block.dart';
import 'package:status_studio/src/features/topic/presentation/cut_card.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// What the script page shows (spec FR-41).
class ScriptPageContent {
  const ScriptPageContent({
    required this.cuts,
    required this.blocks,
    required this.preparingPlay,
  });

  final List<ReviewCut> cuts;
  final List<TranscriptBlock> blocks;

  /// The moment being downloaded to play, if any.
  final TopicCut? preparingPlay;
}

/// What the script page asks Review cuts to do.
class ScriptPageActions {
  const ScriptPageActions({required this.onAddRun, required this.moments});

  final ValueChanged<List<TranscriptBlock>> onAddRun;
  final MomentActions moments;
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

/// Review cuts (spec FR-41, FR-43): your moments and the whole script,
/// where a run of blocks becomes a moment.
class ScriptPage extends StatefulWidget {
  const ScriptPage({required this.content, required this.actions, super.key});

  final ScriptPageContent content;
  final ScriptPageActions actions;

  @override
  State<ScriptPage> createState() => _ScriptPageState();
}

class _ScriptPageState extends State<ScriptPage> {
  BlockRun? _run;
  var _momentsOpen = true;

  void _add() {
    final run = _run;
    if (run == null) {
      return;
    }
    widget.actions.onAddRun(run.of(widget.content.blocks));
    setState(() => _run = null);
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    final run = _run;
    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _MomentsHeader(
                  count: content.cuts.length,
                  open: _momentsOpen,
                  onToggle: () => setState(() => _momentsOpen = !_momentsOpen),
                ),
              ),
              if (_momentsOpen) _moments(content),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionLabel('Script'),
                      HintText('Tap the first line, then the last.'),
                    ],
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: content.blocks.length,
                itemBuilder: (context, index) {
                  final block = content.blocks[index];
                  return ListTile(
                    selected: run?.includes(index) ?? false,
                    selectedTileColor: context.palette.accent.withValues(
                      alpha: 0.15,
                    ),
                    title: ScriptText(block.text),
                    subtitle: HintText(formatTimestamp(block.start)),
                    onTap: () =>
                        setState(() => _run = BlockRun.tapped(_run, index)),
                  );
                },
              ),
            ],
          ),
        ),
        if (run != null)
          _AddRunBar(
            label: addRunLabel(run.of(content.blocks)),
            onAdd: _add,
            onClear: () => setState(() => _run = null),
          ),
      ],
    );
  }

  Widget _moments(ScriptPageContent content) {
    final moments = widget.actions.moments;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverReorderableList(
        itemCount: content.cuts.length,
        onReorderItem: moments.onReorder,
        itemBuilder: (context, index) {
          final review = content.cuts[index];
          return ReorderableDelayedDragStartListener(
            key: ValueKey(review.cut.start),
            index: index,
            child: CutCard(
              review: review,
              onToggle: () => moments.onToggle(index),
              onPlay: () => moments.onPlay(review.cut),
              preparingPlay: review.cut == content.preparingPlay,
            ),
          );
        },
      ),
    );
  }
}

class _MomentsHeader extends StatelessWidget {
  const _MomentsHeader({
    required this.count,
    required this.open,
    required this.onToggle,
  });

  final int count;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      title: Text(
        'Your moments ($count)',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      trailing: Icon(open ? Icons.expand_less : Icons.expand_more),
      onTap: onToggle,
    );
  }
}

/// "Add 0:18–0:37 · 19 s" with a clear, above the footer.
class _AddRunBar extends StatelessWidget {
  const _AddRunBar({
    required this.label,
    required this.onAdd,
    required this.onClear,
  });

  final String label;
  final VoidCallback onAdd;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: FilledButton(onPressed: onAdd, child: Text(label)),
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.close),
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}
