/// Scoring for tool/voice_check.dart: how far Groq's text is from the
/// lyrics the user wrote down (spec §10 item 8). Pure Dart.
library;

const _missingLineThreshold = 0.4;

/// The text as the score compares it: lower case, no harakat, tatweel,
/// ZWNJ or punctuation, look-alike letters merged, one line of single
/// spaces.
String normalizeLyrics(String text) {
  final merged = text
      .toLowerCase()
      .replaceAll(RegExp('[ً-ٰٟـ‌]'), '')
      .replaceAll(RegExp('[يى]'), 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll(RegExp('[ہة]'), 'ه')
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll(RegExp(r'[\p{P}\p{S}]', unicode: true), ' ');
  return merged.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Edit distance between [reference] and [heard] over characters, divided
/// by the reference's length. Both are used as given: normalise first.
double characterErrorRate({required String reference, required String heard}) {
  final expected = reference.runes.toList();
  final actual = heard.runes.toList();
  if (expected.isEmpty) {
    throw ArgumentError('the reference text is empty');
  }
  return _editDistance(expected, actual) / expected.length;
}

int _editDistance(List<int> from, List<int> to) {
  var previous = List<int>.generate(to.length + 1, (column) => column);
  for (var row = 1; row <= from.length; row++) {
    final current = List<int>.filled(to.length + 1, row);
    for (var column = 1; column <= to.length; column++) {
      final substitution = from[row - 1] == to[column - 1] ? 0 : 1;
      current[column] = [
        previous[column] + 1,
        current[column - 1] + 1,
        previous[column - 1] + substitution,
      ].reduce((a, b) => a < b ? a : b);
    }
    previous = current;
  }
  return previous.last;
}

/// The expected lines, in order, that [heard] has no close match for after
/// the place where the previous line matched (a repeat Whisper dropped).
/// Both are normalised already.
List<String> missingLines({
  required List<String> expectedLines,
  required String heard,
}) {
  final missing = <String>[];
  final heardRunes = heard.runes.toList();
  var cursor = 0;
  for (final line in expectedLines) {
    final match = _bestMatch(line.runes.toList(), heardRunes.sublist(cursor));
    if (match.distance / line.runes.length > _missingLineThreshold) {
      missing.add(line);
      continue;
    }
    cursor += match.end;
  }
  return missing;
}

typedef _Match = ({int distance, int end});

/// The substring of [text] closest to [pattern] (Sellers' variant of the
/// edit distance, where the match may start anywhere), and where it ends.
_Match _bestMatch(List<int> pattern, List<int> text) {
  var column = List<int>.generate(pattern.length + 1, (row) => row);
  var best = (distance: column.last, end: 0);
  for (var position = 1; position <= text.length; position++) {
    final next = List<int>.filled(pattern.length + 1, 0);
    for (var row = 1; row <= pattern.length; row++) {
      final substitution = pattern[row - 1] == text[position - 1] ? 0 : 1;
      next[row] = [
        column[row] + 1,
        next[row - 1] + 1,
        column[row - 1] + substitution,
      ].reduce((a, b) => a < b ? a : b);
    }
    column = next;
    if (column.last < best.distance) {
      best = (distance: column.last, end: position);
    }
  }
  return best;
}
