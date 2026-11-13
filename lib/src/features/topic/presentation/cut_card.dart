import 'package:flutter/material.dart';
import 'package:status_studio/src/core/presentation/script_text.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/topic/domain/topic_cut.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// One moment on Review cuts (spec FR-36): a tick for the clip, its times,
/// Play (FR-37), its words and reason. Its edges are trimmed in the Play
/// sheet (FR-39).
class CutCard extends StatefulWidget {
  const CutCard({
    required this.cut,
    required this.ticked,
    required this.onToggle,
    required this.onPlay,
    required this.preparingPlay,
    super.key,
  });

  final TopicCut cut;
  final bool ticked;

  final VoidCallback onToggle;
  final VoidCallback onPlay;

  /// The moment is being downloaded to play: a spinner in Play's place.
  final bool preparingPlay;

  @override
  State<CutCard> createState() => _CutCardState();
}

class _CutCardState extends State<CutCard> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cut = widget.cut;
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
                value: widget.ticked,
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
          if (cut.reason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
              child: ScriptText(
                cut.reason,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: context.palette.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}
