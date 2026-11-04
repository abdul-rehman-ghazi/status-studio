import 'package:status_studio/src/features/transcript/domain/transcript.dart';

/// A lyric line stays on screen at most this long when nothing marks where
/// it ends (a long instrumental after it).
const longestLyricLine = Duration(seconds: 10);

// `[mm:ss.xx]`, with the fraction optional and 1 to 3 digits.
final _timestamp = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');

typedef _TimedText = ({Duration time, String text});

/// Script lines from LRC text (`[01:23.45] words`), the format synced lyrics
/// come in (spec FR-17).
///
/// A line ends where the next entry starts; an empty entry (`[03:30.00]`)
/// marks the end of singing. Metadata tags such as `[ar:Name]` are ignored.
List<TranscriptLine> parseSyncedLyrics(
  String lrc, {
  required Duration trackLength,
}) {
  final entries = _entriesIn(lrc);
  final lines = <TranscriptLine>[];
  for (final (position, entry) in entries.indexed) {
    if (entry.text.isEmpty) {
      continue;
    }
    lines.add(
      TranscriptLine(
        index: lines.length,
        text: entry.text,
        start: entry.time,
        end: _endOf(entries, position, trackLength),
      ),
    );
  }
  return lines;
}

List<_TimedText> _entriesIn(String lrc) {
  final entries = <_TimedText>[];
  for (final row in lrc.split('\n')) {
    final stamps = _leadingTimestamps(row);
    if (stamps.isEmpty) {
      continue;
    }
    final text = row.substring(stamps.last.end).trim();
    for (final stamp in stamps) {
      entries.add((time: _timeOf(stamp), text: text));
    }
  }
  entries.sort((first, second) => first.time.compareTo(second.time));
  return entries;
}

List<RegExpMatch> _leadingTimestamps(String row) {
  final found = <RegExpMatch>[];
  var offset = row.length - row.trimLeft().length;
  for (final match in _timestamp.allMatches(row)) {
    if (match.start != offset) {
      break;
    }
    found.add(match);
    offset = match.end;
  }
  return found;
}

Duration _timeOf(RegExpMatch stamp) {
  final fraction = (stamp.group(3) ?? '').padRight(3, '0');
  return Duration(
    minutes: int.parse(stamp.group(1)!),
    seconds: int.parse(stamp.group(2)!),
    milliseconds: int.parse(fraction),
  );
}

Duration _endOf(List<_TimedText> entries, int position, Duration trackLength) {
  final start = entries[position].time;
  final cap = start + longestLyricLine;
  final nextStart = position + 1 < entries.length
      ? entries[position + 1].time
      : trackLength;
  final end = nextStart < cap ? nextStart : cap;
  return end > start ? end : cap;
}
