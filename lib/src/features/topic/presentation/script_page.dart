import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/presentation/script_text.dart';
import 'package:status_studio/src/core/presentation/section_label.dart';
import 'package:status_studio/src/core/script_detection.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/library/domain/recent_reel.dart';
import 'package:status_studio/src/features/topic/domain/block_run.dart';
import 'package:status_studio/src/features/topic/domain/script_search.dart';
import 'package:status_studio/src/features/topic/domain/transcript_block.dart';
import 'package:status_studio/src/features/topic/domain/used_marks.dart';
import 'package:status_studio/src/features/topic/presentation/cut_card.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// What the script page shows (spec FR-41).
class ScriptPageContent {
  const ScriptPageContent({required this.blocks, required this.usedReels});

  final List<TranscriptBlock> blocks;

  /// This video's reels, for the `In <reel name>` marks (spec FR-44).
  final List<RecentReel> usedReels;
}

/// Review cuts (spec FR-41, FR-43): Search the script (FR-28) and the whole
/// script, where a run of blocks becomes a moment. The moments themselves
/// are in a panel from the footer (FR-46).
class ScriptPage extends StatefulWidget {
  const ScriptPage({required this.content, required this.onAddRun, super.key});

  final ScriptPageContent content;
  final ValueChanged<List<TranscriptBlock>> onAddRun;

  @override
  State<ScriptPage> createState() => _ScriptPageState();
}

class _ScriptPageState extends State<ScriptPage> {
  BlockRun? _run;
  final _scroll = ScrollController();
  final _searchField = TextEditingController();
  late List<FoldedText> _foldedBlocks = _fold(widget.content.blocks);
  late Map<int, String> _usedBlocks = _usedOf(widget.content);
  List<ScriptMatch> _matches = const [];
  var _current = 0;

  /// Built blocks' keys, to reveal a match and to measure the blocks.
  final _blockKeys = <int, GlobalKey>{};

  static Map<int, String> _usedOf(ScriptPageContent content) =>
      usedBlocks(content.blocks, content.usedReels);

  static List<FoldedText> _fold(List<TranscriptBlock> blocks) => [
    for (final block in blocks) FoldedText.of(block.text),
  ];

  @override
  void didUpdateWidget(ScriptPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.content;
    if (!identical(old.blocks, widget.content.blocks) ||
        !listEquals(old.usedReels, widget.content.usedReels)) {
      _usedBlocks = _usedOf(widget.content);
    }
    if (!identical(oldWidget.content.blocks, widget.content.blocks)) {
      _foldedBlocks = _fold(widget.content.blocks);
      _matches = matchesIn(_foldedBlocks, _searchField.text);
      _current = 0;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchField.dispose();
    super.dispose();
  }

  void _add() {
    final run = _run;
    if (run == null) {
      return;
    }
    widget.onAddRun(run.of(widget.content.blocks));
    setState(() => _run = null);
  }

  /// Finds as the user types (spec FR-28); the first match becomes current
  /// and comes into view (*Claude's call*).
  void _search(String query) {
    setState(() {
      _matches = matchesIn(_foldedBlocks, query);
      _current = 0;
    });
    _revealCurrent();
  }

  void _clearSearch() {
    _searchField.clear();
    _search('');
  }

  void _step(int Function(int current, int count) next) {
    if (_matches.isEmpty) {
      return;
    }
    setState(() => _current = next(_current, _matches.length));
    _revealCurrent();
  }

  void _revealCurrent() {
    if (_matches.isEmpty) {
      return;
    }
    unawaited(_reveal(_matches[_current].blockIndex));
  }

  /// The script is built lazily, so a block far away has no key to reveal
  /// yet: jump towards it by the built blocks' average height until it is
  /// built, then bring it into view.
  Future<void> _reveal(int blockIndex) async {
    for (var attempt = 0; attempt < 8 && mounted; attempt++) {
      final target = _blockKeys[blockIndex]?.currentContext;
      if (target != null && target.mounted) {
        await Scrollable.ensureVisible(
          target,
          alignment: 0.3,
          duration: const Duration(milliseconds: 250),
        );
        return;
      }
      if (!_jumpTowards(blockIndex)) {
        return;
      }
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  /// False when no block is built to measure from.
  bool _jumpTowards(int blockIndex) {
    final built = [
      for (final MapEntry(:key, :value) in _blockKeys.entries)
        if (value.currentContext?.findRenderObject() case final RenderBox box
            when box.hasSize)
          (index: key, height: box.size.height),
    ]..sort((a, b) => a.index.compareTo(b.index));
    if (built.isEmpty || !_scroll.hasClients) {
      return false;
    }
    final averageHeight =
        built.fold(0.0, (sum, block) => sum + block.height) / built.length;
    final nearest = blockIndex < built.first.index ? built.first : built.last;
    final position = _scroll.position;
    final distance = (blockIndex - nearest.index) * averageHeight;
    position.jumpTo(
      (position.pixels + distance).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.content;
    final run = _run;
    final current = _matches.isEmpty ? null : _matches[_current];
    return Column(
      children: [
        _ScriptSearchBar(
          field: _searchField,
          found: (count: _matches.length, current: _current),
          actions: _SearchBarActions(
            onChanged: _search,
            onClear: _clearSearch,
            onPrevious: () => _step(previousMatchIndex),
            onNext: () => _step(nextMatchIndex),
          ),
        ),
        Expanded(
          child: CustomScrollView(
            controller: _scroll,
            slivers: [
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
                  final usedIn = _usedBlocks[index];
                  return KeyedSubtree(
                    key: _blockKeys.putIfAbsent(index, GlobalKey.new),
                    child: ListTile(
                      selected: run?.includes(index) ?? false,
                      selectedTileColor: context.palette.accent.withValues(
                        alpha: 0.15,
                      ),
                      tileColor: usedIn == null
                          ? null
                          : context.palette.accent.withValues(alpha: 0.06),
                      title: _HighlightedScriptText(
                        text: block.text,
                        matches: [
                          for (final match in _matches)
                            if (match.blockIndex == index) match,
                        ],
                        current: current,
                      ),
                      subtitle: usedIn == null
                          ? HintText(formatTimestamp(block.start))
                          : Row(
                              children: [
                                HintText(formatTimestamp(block.start)),
                                const SizedBox(width: 8),
                                Flexible(child: UsedTag(usedIn)),
                              ],
                            ),
                      onTap: () =>
                          setState(() => _run = BlockRun.tapped(_run, index)),
                    ),
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
}

class _SearchBarActions {
  const _SearchBarActions({
    required this.onChanged,
    required this.onClear,
    required this.onPrevious,
    required this.onNext,
  });

  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
}

/// "Search the script" with a clear, then "3 of 12" or "No match" and
/// ˄ ˅ while there is text (spec FR-28).
class _ScriptSearchBar extends StatelessWidget {
  const _ScriptSearchBar({
    required this.field,
    required this.found,
    required this.actions,
  });

  final TextEditingController field;

  /// [current] is a 0-based index into the matches.
  final ({int count, int current}) found;
  final _SearchBarActions actions;

  @override
  Widget build(BuildContext context) {
    final searching = field.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: field,
              textInputAction: TextInputAction.search,
              onChanged: actions.onChanged,
              decoration: InputDecoration(
                hintText: 'Search the script',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: field.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close),
                        onPressed: actions.onClear,
                      ),
              ),
            ),
          ),
          if (searching) ..._matchControls(),
        ],
      ),
    );
  }

  List<Widget> _matchControls() {
    final hasMatches = found.count > 0;
    return [
      const SizedBox(width: 8),
      Text(hasMatches ? '${found.current + 1} of ${found.count}' : 'No match'),
      IconButton(
        tooltip: 'Previous match',
        icon: const Icon(Icons.keyboard_arrow_up),
        onPressed: hasMatches ? actions.onPrevious : null,
      ),
      IconButton(
        tooltip: 'Next match',
        icon: const Icon(Icons.keyboard_arrow_down),
        onPressed: hasMatches ? actions.onNext : null,
      ),
    ];
  }
}

/// A block's words with each match highlighted, the current one stronger.
/// Only the background changes, so the letters keep their joins.
class _HighlightedScriptText extends StatelessWidget {
  const _HighlightedScriptText({
    required this.text,
    required this.matches,
    required this.current,
  });

  final String text;

  /// This block's matches, in order.
  final List<ScriptMatch> matches;
  final ScriptMatch? current;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return ScriptText(text);
    }
    final rightToLeft = isArabicScript(text);
    return Text.rich(
      TextSpan(children: _spans(context.palette.accent)),
      textAlign: rightToLeft ? TextAlign.right : TextAlign.left,
      textDirection: rightToLeft ? TextDirection.rtl : TextDirection.ltr,
      style: scriptTextStyle(text),
    );
  }

  List<TextSpan> _spans(Color accent) {
    final spans = <TextSpan>[];
    var shownTo = 0;
    for (final match in matches) {
      spans
        ..add(TextSpan(text: text.substring(shownTo, match.start)))
        ..add(
          TextSpan(
            text: text.substring(match.start, match.end),
            style: TextStyle(
              backgroundColor: accent.withValues(
                alpha: match == current ? 0.6 : 0.25,
              ),
            ),
          ),
        );
      shownTo = match.end;
    }
    spans.add(TextSpan(text: text.substring(shownTo)));
    return spans;
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
