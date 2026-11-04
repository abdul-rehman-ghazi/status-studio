import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/presentation/script_text.dart';
import 'package:status_studio/src/core/script_detection.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/clip/application/clip_playhead.dart';
import 'package:status_studio/src/features/clip/domain/clip_window.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/transcript/domain/line_edits.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';
import 'package:status_studio/src/theme/app_theme.dart';

const _outsideRangeOpacity = 0.45;

/// The script's lines around the clip, editable, with the one playing
/// highlighted (spec FR-21). A tap seeks while paused and times the line
/// while playing.
class ClipLinesList extends ConsumerStatefulWidget {
  const ClipLinesList({
    super.key,
    required this.script,
    required this.window,
    required this.playhead,
    required this.onEdited,
  });

  final PickedScript script;

  /// Only lines that overlap it are listed.
  final ClipWindow window;
  final ClipPlayhead playhead;

  /// Called after every edit, so the screen can save the script.
  final VoidCallback onEdited;

  @override
  ConsumerState<ClipLinesList> createState() => _ClipLinesListState();
}

class _ClipLinesListState extends ConsumerState<ClipLinesList>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _followPlayhead());
    widget.playhead.addListener(_followPlayhead);
  }

  @override
  void dispose() {
    widget.playhead.removeListener(_followPlayhead);
    _ticker.dispose();
    super.dispose();
  }

  // The player reports about twice a second; the ticker redraws the
  // highlight between reports while playing.
  void _followPlayhead() {
    final playing = widget.playhead.isPlaying;
    if (playing && !_ticker.isActive) {
      unawaited(_ticker.start());
    } else if (!playing && _ticker.isActive) {
      _ticker.stop();
    }
    _redraw();
  }

  // A report can arrive while the tree is building; draw after it then.
  void _redraw() {
    if (!mounted) {
      return;
    }
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _redraw());
      return;
    }
    setState(() {});
  }

  void _edit(PickedScript Function(PickedScript script) edit) {
    ref.read(reelDraftProvider.notifier).editScript(edit);
    widget.onEdited();
  }

  void _tapLine(TranscriptLine line) {
    final playhead = widget.playhead;
    if (!playhead.isReady) {
      return;
    }
    if (playhead.isPlaying) {
      final timedAt = playhead.position;
      _edit((script) => withLineTimedAt(script, line.index, timedAt));
      return;
    }
    unawaited(playhead.seekTo(line.start));
  }

  Future<void> _editLine(TranscriptLine line) async {
    final text = await askLineText(
      context,
      title: 'Edit line',
      initialText: line.text,
    );
    if (text == null) {
      return;
    }
    _edit((script) => withLineText(script, line.index, text));
  }

  Future<void> _addLine() async {
    final playhead = widget.playhead.position;
    final text = await askLineText(context, title: 'Add line');
    if (text == null) {
      return;
    }
    _edit((script) => withLineAdded(script, text: text, playhead: playhead));
  }

  void _removeLine(TranscriptLine line) =>
      _edit((script) => withLineRemoved(script, line.index));

  void _moveLine(int firstShown, int oldPosition, int newPosition) {
    _edit(
      (script) => withLineTextMoved(
        script,
        firstShown + oldPosition,
        firstShown + newPosition,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.script.transcript.lines;
    final shown = lines.where(_overlapsWindow).toList();
    final highlighted = highlightedLineIndex(lines, widget.playhead.position);
    final selection = widget.script.selection;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (shown.isNotEmpty)
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (oldPosition, newPosition) =>
                _moveLine(shown.first.index, oldPosition, newPosition),
            children: [
              for (final (position, line) in shown.indexed)
                _LineRow(
                  key: ValueKey('line-${line.index}'),
                  line: line,
                  dragPosition: position,
                  highlighted: line.index == highlighted,
                  inRange: selection.isHighlighted(line.index),
                  canRemove: !_isOnlyPickedLine(selection, line.index),
                  onTap: selection.isHighlighted(line.index)
                      ? () => _tapLine(line)
                      : null,
                  onEdit: () => unawaited(_editLine(line)),
                  onRemove: () => _removeLine(line),
                ),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: widget.playhead.isReady
                ? () => unawaited(_addLine())
                : null,
            icon: const Icon(Icons.add),
            label: const Text('Add line'),
          ),
        ),
      ],
    );
  }

  bool _overlapsWindow(TranscriptLine line) =>
      line.end > widget.window.start && line.start < widget.window.end;
}

bool _isOnlyPickedLine(RangeSelected selection, int index) =>
    selection.start == selection.end && selection.start == index;

class _LineRow extends StatelessWidget {
  const _LineRow({
    super.key,
    required this.line,
    required this.dragPosition,
    required this.highlighted,
    required this.inRange,
    required this.canRemove,
    required this.onTap,
    required this.onEdit,
    required this.onRemove,
  });

  final TranscriptLine line;
  final int dragPosition;
  final bool highlighted;
  final bool inRange;
  final bool canRemove;
  final VoidCallback? onTap;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: highlighted,
      child: Opacity(
        opacity: inRange ? 1 : _outsideRangeOpacity,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: highlighted
                ? AppColors.accent.withValues(alpha: 0.25)
                : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Row(
                children: [
                  HintText(formatTimestamp(line.start)),
                  const SizedBox(width: 12),
                  Expanded(child: ScriptText(line.text)),
                  _LineButton(
                    tooltip: 'Edit line',
                    icon: Icons.edit_outlined,
                    onPressed: onEdit,
                  ),
                  _LineButton(
                    tooltip: 'Delete line',
                    icon: Icons.delete_outline,
                    onPressed: canRemove ? onRemove : null,
                  ),
                  ReorderableDragStartListener(
                    index: dragPosition,
                    child: const Tooltip(
                      message: 'Move line',
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.drag_handle, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LineButton extends StatelessWidget {
  const _LineButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      iconSize: 20,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}

/// Asks for a line's text; the new text, or nothing when cancelled.
Future<String?> askLineText(
  BuildContext context, {
  required String title,
  String initialText = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _LineTextDialog(title: title, initialText: initialText),
  );
}

class _LineTextDialog extends StatefulWidget {
  const _LineTextDialog({required this.title, required this.initialText});

  final String title;
  final String initialText;

  @override
  State<_LineTextDialog> createState() => _LineTextDialogState();
}

class _LineTextDialogState extends State<_LineTextDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: ListenableBuilder(
        listenable: _text,
        builder: (context, _) => TextField(
          controller: _text,
          autofocus: true,
          minLines: 1,
          maxLines: 4,
          textDirection: isArabicScript(_text.text)
              ? TextDirection.rtl
              : TextDirection.ltr,
          style: scriptTextStyle(_text.text),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_text.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
