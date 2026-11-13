import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/topic/domain/transcript_block.dart';

/// One place the search was found (spec FR-28): [start] and [end] index the
/// block's own text, so the highlight lands on what is shown.
@immutable
class ScriptMatch {
  const ScriptMatch({
    required this.blockIndex,
    required this.start,
    required this.end,
  });

  final int blockIndex;
  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is ScriptMatch &&
      other.blockIndex == blockIndex &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(blockIndex, start, end);
}

/// [original] folded for matching, and where each folded code unit came
/// from in it. [originalOffsets] has one more entry than [key]: the end.
@immutable
class FoldedText {
  const FoldedText._(this.key, this.originalOffsets);

  factory FoldedText.of(String original) {
    final key = StringBuffer();
    final offsets = <int>[];
    var offset = 0;
    for (final rune in original.runes) {
      final folded = _foldRune(rune);
      for (final unit in folded.codeUnits) {
        key.writeCharCode(unit);
        offsets.add(offset);
      }
      offset += rune > 0xFFFF ? 2 : 1;
    }
    offsets.add(original.length);
    return FoldedText._(key.toString(), List.unmodifiable(offsets));
  }

  final String key;
  final List<int> originalOffsets;
}

/// [text] as the search compares it (spec FR-28): case folded, each
/// Arabic-script letter group as one letter, harakat, the superscript alef
/// and the tatweel dropped.
String searchKey(String text) => FoldedText.of(text).key;

/// Every place [query] is found in [blocks], in script order; none for an
/// empty query. Matches in one block don't overlap.
List<ScriptMatch> scriptMatches(List<TranscriptBlock> blocks, String query) =>
    matchesIn([for (final block in blocks) FoldedText.of(block.text)], query);

/// As [scriptMatches], on blocks folded once: the search runs on each key
/// typed, and a long script has over a thousand blocks.
List<ScriptMatch> matchesIn(List<FoldedText> foldedBlocks, String query) {
  final needle = searchKey(query.trim());
  if (needle.isEmpty) {
    return const [];
  }
  return [
    for (final (index, folded) in foldedBlocks.indexed)
      ..._matchesInBlock(index, folded, needle),
  ];
}

/// ˅ after the last match goes back to the first (spec FR-28).
int nextMatchIndex(int current, int count) => (current + 1) % count;

/// ˄ before the first match goes to the last.
int previousMatchIndex(int current, int count) =>
    (current - 1 + count) % count;

Iterable<ScriptMatch> _matchesInBlock(
  int blockIndex,
  FoldedText folded,
  String needle,
) sync* {
  var from = folded.key.indexOf(needle);
  while (from >= 0) {
    final to = from + needle.length;
    yield ScriptMatch(
      blockIndex: blockIndex,
      start: folded.originalOffsets[from],
      end: folded.originalOffsets[to],
    );
    from = folded.key.indexOf(needle, to);
  }
}

/// The variants Urdu, Arabic and Persian text mixes, each mapped to the
/// letter it stands in for (spec FR-28).
const _letterGroups = {
  0x064A: 0x06CC, // ي Arabic yeh → ی
  0x0649: 0x06CC, // ى alef maksura → ی
  0x0643: 0x06A9, // ك Arabic kaf → ک
  0x0647: 0x06C1, // ه heh → ہ
  0x06BE: 0x06C1, // ھ heh doachashmee → ہ
  0x0629: 0x06C3, // ة teh marbuta → ۃ
  0x0623: 0x0627, // أ → ا
  0x0625: 0x0627, // إ → ا
  0x0622: 0x0627, // آ → ا
};

bool _isIgnoredMark(int rune) =>
    (rune >= 0x064B && rune <= 0x065F) || rune == 0x0670 || rune == 0x0640;

/// Empty for a dropped mark; otherwise the rune's search form, which may
/// be longer than one code unit (some capitals lower to two).
String _foldRune(int rune) {
  if (_isIgnoredMark(rune)) {
    return '';
  }
  final grouped = _letterGroups[rune];
  if (grouped != null) {
    return String.fromCharCode(grouped);
  }
  return String.fromCharCode(rune).toLowerCase();
}
