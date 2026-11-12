import 'package:flutter/material.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/topic/domain/cut_edits.dart';
import 'package:status_studio/src/features/topic/domain/topic_cut.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// One cut on Review cuts (spec FR-36): its times, words and reason, with
/// − and + on each edge and Remove.
class CutCard extends StatefulWidget {
  const CutCard({
    required this.cut,
    required this.onNudge,
    required this.onRemove,
    super.key,
  });

  final TopicCut cut;

  /// Called with how far to move the start and the end.
  final void Function({Duration startBy, Duration endBy}) onNudge;
  final VoidCallback onRemove;

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
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${formatTimestamp(cut.start)}–${formatTimestamp(cut.end)}'
                  ' · ${cut.length.inSeconds} s',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline),
                onPressed: widget.onRemove,
              ),
            ],
          ),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                cut.text,
                maxLines: _expanded ? null : 3,
                overflow: _expanded ? null : TextOverflow.ellipsis,
              ),
            ),
          ),
          if (cut.reason.isNotEmpty) ...[
            const SizedBox(height: 4),
            HintText(cut.reason),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              _EdgeNudges(
                label: 'Start',
                onEarlier: () => widget.onNudge(startBy: -cutNudge),
                onLater: () => widget.onNudge(startBy: cutNudge),
              ),
              const Spacer(),
              _EdgeNudges(
                label: 'End',
                onEarlier: () => widget.onNudge(endBy: -cutNudge),
                onLater: () => widget.onNudge(endBy: cutNudge),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EdgeNudges extends StatelessWidget {
  const _EdgeNudges({
    required this.label,
    required this.onEarlier,
    required this.onLater,
  });

  final String label;
  final VoidCallback onEarlier;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label),
        IconButton(
          tooltip: '$label 0.5 s earlier',
          icon: const Icon(Icons.remove),
          onPressed: onEarlier,
        ),
        IconButton(
          tooltip: '$label 0.5 s later',
          icon: const Icon(Icons.add),
          onPressed: onLater,
        ),
      ],
    );
  }
}
