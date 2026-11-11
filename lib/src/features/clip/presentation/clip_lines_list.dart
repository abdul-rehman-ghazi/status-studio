import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/presentation/script_text.dart';
import 'package:status_studio/src/core/script_detection.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/clip/application/clip_playhead.dart';
import 'package:status_studio/src/features/clip/application/lyrics_undo_controller.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/clip/presentation/playhead_redraw.dart';
import 'package:status_studio/src/features/transcript/domain/line_edits.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// The clip's lines, editable, with the one playing highlighted (spec FR-21).
/// A sliver: it goes in the screen's `CustomScrollView`. A tap seeks while paused and times the line
/// while playing.
class ClipLinesList extends ConsumerStatefulWidget {
  const ClipLinesList({
    super.key,
    required this.script,
    required this.clip,
    required this.playhead,
    required this.onEdited,
  });

  final PickedScript script;

  /// Add line is on only while the playhead is inside it.
  final ClipRange clip;
  final ClipPlayhead playhead;

  /// Called after every edit, so the screen can save the script.
  final VoidCallback onEdited;

  @override
  ConsumerState<ClipLinesList> createState() => _ClipLinesListState();
}

class _ClipLinesListState extends ConsumerState<ClipLinesList>
    with SingleTickerProviderStateMixin {
  late final PlayheadRedraw _redraw;

  @override
  void initState() {
    super.initState();
    _redraw = PlayheadRedraw(
      vsync: this,
      playhead: widget.playhead,
      isMounted: () => mounted,
      redraw: () => setState(() {}),
    );
  }

  @override
  void dispose() {
    _redraw.dispose();
    super.dispose();
  }

  void _edit(PickedScript Function(PickedScript script) edit) {
    // A quick message's Undo would take back this edit, not its own.
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ref.read(lyricsUndoProvider.notifier).applyEdit(edit);
    widget.onEdited();
  }

  /// "Line deleted" or "Line timed" with Undo, for the changes most often
  /// made by accident, for a snack bar's default 4 s (spec FR-34).
  void _offerUndo(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(label: 'Undo', onPressed: _undoFromMessage),
      ),
    );
  }

  void _undoFromMessage() {
    if (!mounted) {
      return;
    }
    ref.read(lyricsUndoProvider.notifier).undo();
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
      _offerUndo('Line timed');
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

  void _removeLine(TranscriptLine line) {
    _edit((script) => withLineRemoved(script, line.index));
    _offerUndo('Line deleted');
  }

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
    final selection = widget.script.selection;
    final shown = lines.sublist(selection.start, selection.end + 1);
    final highlighted = highlightedLineIndex(lines, widget.playhead.position);
    // Slivers, so the list is part of the screen's own scrolling and a drag
    // near the top or bottom edge scrolls it (spec FR-21, M40).
    return SliverMainAxisGroup(
      slivers: [
        SliverReorderableList(
          itemCount: shown.length,
          onReorderItem: (oldPosition, newPosition) =>
              _moveLine(shown.first.index, oldPosition, newPosition),
          proxyDecorator: _liftedRow,
          itemBuilder: (context, position) {
            final line = shown[position];
            return _LineRow(
              key: ValueKey('line-${line.index}'),
              line: line,
              dragPosition: position,
              highlighted: line.index == highlighted,
              canRemove: shown.length > 1,
              onTap: () => _tapLine(line),
              onEdit: () => unawaited(_editLine(line)),
              onRemove: () => _removeLine(line),
            );
          },
        ),
        SliverToBoxAdapter(
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _canAddLine ? () => unawaited(_addLine()) : null,
              icon: const Icon(Icons.add),
              label: const Text('Add line'),
            ),
          ),
        ),
      ],
    );
  }

  /// The row being dragged floats above the list on its own card, as
  /// `ReorderableListView` drew it.
  Widget _liftedRow(Widget row, int position, Animation<double> lift) {
    return AnimatedBuilder(
      animation: lift,
      builder: (context, child) => Material(
        elevation: 6 * lift.value,
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(10),
        child: child,
      ),
      child: row,
    );
  }

  bool get _canAddLine {
    final playhead = widget.playhead;
    final position = playhead.position;
    return playhead.isReady &&
        position >= widget.clip.start &&
        position <= widget.clip.end;
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    super.key,
    required this.line,
    required this.dragPosition,
    required this.highlighted,
    required this.canRemove,
    required this.onTap,
    required this.onEdit,
    required this.onRemove,
  });

  final TranscriptLine line;
  final int dragPosition;
  final bool highlighted;
  final bool canRemove;
  final VoidCallback? onTap;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: highlighted,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: highlighted
              ? context.palette.accent.withValues(alpha: 0.25)
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
