import 'package:flutter/material.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/topic/domain/transcript_block.dart';

/// The transcript with a search field; returns the block tapped (spec
/// FR-36, Add a moment), or null when closed.
Future<TranscriptBlock?> showAddMomentSheet(
  BuildContext context,
  List<TranscriptBlock> blocks,
) => showModalBottomSheet<TranscriptBlock>(
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
  var _search = '';

  @override
  Widget build(BuildContext context) {
    final shown = _search.isEmpty
        ? widget.blocks
        : widget.blocks
              .where((block) => block.text.toLowerCase().contains(_search))
              .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search the transcript',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (text) =>
                  setState(() => _search = text.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: shown.length,
              itemBuilder: (context, index) {
                final block = shown[index];
                return ListTile(
                  title: Text(block.text),
                  subtitle: HintText(formatTimestamp(block.start)),
                  onTap: () => Navigator.of(context).pop(block),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
