import 'package:flutter/material.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/presentation/script_text.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/topic/domain/cut_edits.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// One moment on Review cuts (spec FR-36, FR-43): a tick for the clip, its
/// times, Play (FR-37) and its words. Its edges are trimmed in the Play
/// sheet (FR-39); until Update words, a trimmed or added moment says its
/// words are old (FR-40).
class CutCard extends StatefulWidget {
  const CutCard({
    required this.review,
    required this.onToggle,
    required this.onPlay,
    required this.preparingPlay,
    this.usedIn,
    super.key,
  });

  final ReviewCut review;

  final VoidCallback onToggle;
  final VoidCallback onPlay;

  /// The moment is being downloaded to play: a spinner in Play's place.
  final bool preparingPlay;

  /// The newest reel that used part of this moment (spec FR-44), if any.
  final String? usedIn;

  @override
  State<CutCard> createState() => _CutCardState();
}

class _CutCardState extends State<CutCard> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cut = widget.review.cut;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: widget.review.ticked,
                onChanged: (_) => widget.onToggle(),
              ),
              Expanded(
                child: Text(
                  '${formatTimestamp(cut.start)}–${formatTimestamp(cut.end)}'
                  ' · ${cut.length.inSeconds} s',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (widget.preparingPlay)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                IconButton(
                  tooltip: 'Play',
                  icon: const Icon(Icons.play_circle_outline),
                  onPressed: widget.onPlay,
                ),
            ],
          ),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
              child: ScriptText(cut.text, maxLines: _expanded ? null : 3),
            ),
          ),
          if (widget.usedIn case final reelName?)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
              child: UsedTag(reelName),
            ),
          if (widget.review.needsWords)
            const Padding(
              padding: EdgeInsets.fromLTRB(10, 4, 10, 0),
              child: HintText('Words not updated yet'),
            ),
        ],
      ),
    );
  }
}

/// `In <reel name>` on a moment or script block a reel already used (spec
/// FR-44). A mark only: the block can still be chosen.
class UsedTag extends StatelessWidget {
  const UsedTag(this.reelName, {super.key});

  final String reelName;

  @override
  Widget build(BuildContext context) {
    return Text(
      'In $reelName',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: context.palette.accent,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
