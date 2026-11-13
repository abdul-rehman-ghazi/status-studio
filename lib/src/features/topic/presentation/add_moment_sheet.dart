import 'package:flutter/material.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/presentation/script_text.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/topic/domain/block_run.dart';
import 'package:status_studio/src/features/topic/domain/transcript_block.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// A guess at a row's height, to bring a block near view before it is built;
/// the exact place follows once it is.
const _estimatedRowHeight = 80.0;

/// The transcript with a search field; returns the run of blocks chosen,
/// first to last (spec FR-36, Add a moment; grouped since M50), or null
/// when closed.
Future<List<TranscriptBlock>?> showAddMomentSheet(
  BuildContext context,
  List<TranscriptBlock> blocks,
) => showModalBottomSheet<List<TranscriptBlock>>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => _AddMomentSheet(blocks: blocks),
);

class _AddMomentSheet extends StatefulWidget {
  const _AddMomentSheet({required this.blocks});

  final List<TranscriptBlock> blocks;

  @override
  State<_AddMomentSheet> createState() => _AddMomentSheetState();
}

class _AddMomentSheetState extends State<_AddMomentSheet> {
  final _searchField = TextEditingController();
  final _scroll = ScrollController();
  final _tappedRow = GlobalKey();
  var _search = '';

  BlockRun? _run;
  int? _tapped;

  @override
  void dispose() {
    _searchField.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _tap(int index) {
    final wasSearching = _search.isNotEmpty;
    setState(() {
      _run = BlockRun.tapped(_run, index);
      _tapped = index;
      _search = '';
    });
    _searchField.clear();
    if (wasSearching) _keepInView(index);
  }

  /// After the search is cleared, the tapped block is brought back into
  /// view, so the run's end is picked in context.
  void _keepInView(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) {
        return;
      }
      _scroll.jumpTo(
        (index * _estimatedRowHeight).clamp(
          0,
          _scroll.position.maxScrollExtent,
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final row = _tappedRow.currentContext;
        if (row != null && row.mounted) {
          Scrollable.ensureVisible(row, alignment: 0.3);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final blocks = widget.blocks;
    final shown = [
      for (final (index, block) in blocks.indexed)
        if (_search.isEmpty || block.text.toLowerCase().contains(_search))
          index,
    ];
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchField,
              decoration: const InputDecoration(
                hintText: 'Search the transcript',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (text) =>
                  setState(() => _search = text.trim().toLowerCase()),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: HintText('Tap the first line, then the last.'),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              itemCount: shown.length,
              itemBuilder: (context, position) {
                final index = shown[position];
                final block = blocks[index];
                return ListTile(
                  key: index == _tapped ? _tappedRow : null,
                  selected: _run?.includes(index) ?? false,
                  selectedTileColor: context.palette.accent.withValues(
                    alpha: 0.15,
                  ),
                  title: ScriptText(block.text),
                  subtitle: HintText(formatTimestamp(block.start)),
                  onTap: () => _tap(index),
                );
              },
            ),
          ),
          _AddButton(run: _run?.of(blocks) ?? const []),
        ],
      ),
    );
  }
}

/// "Add 1:02:13–1:02:31 · 18 s", off until a line is tapped.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.run});

  final List<TranscriptBlock> run;

  @override
  Widget build(BuildContext context) {
    final label = run.isEmpty ? 'Add' : addRunLabel(run);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: run.isEmpty
                ? null
                : () => Navigator.of(context).pop(run),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}
