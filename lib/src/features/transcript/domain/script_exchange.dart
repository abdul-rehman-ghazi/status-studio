import 'package:status_studio/src/features/transcript/domain/line_selection.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

/// What the user pasted holds no script rows (spec §8).
class NoScriptRowsException implements Exception {
  const NoScriptRowsException();

  @override
  String toString() => 'NoScriptRowsException';
}

/// More lines than this are more than an AI chat will check in one reply.
const mostLinesForAi = 60;

/// Past this many lines Groq's web-search model starts to put lines of the
/// poem in the wrong rows (spec §10 #6).
const mostLinesForGroq = 30;

/// Too many lines to send to an AI agent in one go (spec §8).
class TooManyLinesForAiException implements Exception {
  const TooManyLinesForAiException();

  @override
  String toString() => 'TooManyLinesForAiException';
}

/// A script with its text corrected by an AI agent (spec FR-18).
class CorrectedScript {
  const CorrectedScript({
    required this.transcript,
    required this.changedLines,
    required this.uncertainRows,
  });

  final Transcript transcript;
  final int changedLines;

  /// Row numbers the agent marked `[?]`: it found no source for them.
  final List<int> uncertainRows;
}

const _uncertainMark = '[?]';

// Search models cite their sources inside the text: `【1†L10-L12】`.
final _citationMark = RegExp(r'【[^】]*】');

// `12 | 00:21.40 | 00:30.00 | text`; the text may itself hold bars.
final _row = RegExp(
  r'^\s*(\d+)\s*\|\s*[\d:.,]+\s*\|\s*[\d:.,]+\s*\|\s*(.*\S)\s*$',
);

/// The lines worth sending to an AI agent: the picked clip's lines, or the
/// whole script when it is short. Throws [TooManyLinesForAiException] when
/// that is more than [mostLines], since an agent refuses, skims or misplaces
/// them.
List<TranscriptLine> linesToCheck(
  Transcript transcript,
  LineSelection selection, {
  int mostLines = mostLinesForAi,
}) {
  final lines = selection is RangeSelected
      ? transcript.lines.sublist(selection.start, selection.end + 1)
      : transcript.lines;
  if (lines.length > mostLines) {
    throw const TooManyLinesForAiException();
  }
  return lines;
}

/// The prompt for an AI agent, with the video and [lines] in it (spec
/// FR-18). Pasted as is, it needs nothing else from the user.
String scriptPromptFor({
  required String videoTitle,
  required List<TranscriptLine> lines,
}) {
  final rows = lines
      .map(
        (line) =>
            '${line.index + 1} | ${_clock(line.start)} | ${_clock(line.end)} | '
            '${line.text.replaceAll('\n', ' ')}',
      )
      .join('\n');
  return '''
Below are rows of a time-stamped script that was auto-transcribed from the audio of a video of a naat or song. The text has mistakes. Fix the TEXT using the real published lyrics you find online, and reply with the rows in the same format. These rows are only a part of the video, so the row numbers do not start at 1; keep them as given.

Video title: $videoTitle

Each row is: <number> | <start> | <end> | <text>

Rules:
1. Search the web for the real lyrics (naat sites, the poet's collection, the video's description). Use what you find. Never invent or improve words from memory. If you cannot find a reliable source for a row, keep its text and add " $_uncertainMark" at the end of that row.
2. Keep every row's number, start and end exactly as given. Change only the text. Do not merge, split, reorder or delete rows. Never move a line from another part of the poem into a row: a row keeps what is sung there, and a short refrain row stays a refrain.
3. The video may contain verses (shaer) from a different poem. Where a row sounds like another poem, find that poem and correct the row from it.
4. Write in the same script as the input (Urdu stays in Urdu script, not Roman). No translation and no added punctuation.
5. Do not ask me to send fewer rows or to split them. Correct what is here, and mark any row you cannot verify with $_uncertainMark.
6. Reply with only the corrected rows in one code block. After it, list each row you changed with the source link you used, and each row marked $_uncertainMark.

Script:
$rows
''';
}

/// [current] with its text replaced by the rows in [pasted], matched by row
/// number. Times are never taken from [pasted], and rows that are missing or
/// empty keep their text, so a partly mangled reply still helps. Throws
/// [NoScriptRowsException] when [pasted] holds no rows.
CorrectedScript applyCorrectedScript(Transcript current, String pasted) {
  final textByRow = _textByRowNumber(pasted);
  if (textByRow.isEmpty) {
    throw const NoScriptRowsException();
  }
  var changed = 0;
  final uncertainRows = <int>[];
  final lines = <TranscriptLine>[];
  for (final line in current.lines) {
    final reply = textByRow[line.index + 1];
    if (reply == null) {
      lines.add(line);
      continue;
    }
    final isUncertain = reply.endsWith(_uncertainMark);
    final text = isUncertain
        ? reply.substring(0, reply.length - _uncertainMark.length).trim()
        : reply;
    if (isUncertain) {
      uncertainRows.add(line.index + 1);
    }
    changed += text != line.text ? 1 : 0;
    lines.add(line.copyWith(text: text));
  }
  return CorrectedScript(
    transcript: current.copyWith(lines: lines),
    changedLines: changed,
    uncertainRows: uncertainRows,
  );
}

Map<int, String> _textByRowNumber(String pasted) {
  final textByRow = <int, String>{};
  for (final row in pasted.split('\n')) {
    final match = _row.firstMatch(row.replaceAll(_citationMark, ''));
    if (match != null) {
      textByRow[int.parse(match.group(1)!)] = match.group(2)!;
    }
  }
  return textByRow;
}

String _clock(Duration time) {
  final minutes = time.inMinutes.toString().padLeft(2, '0');
  final seconds = (time.inSeconds % 60).toString().padLeft(2, '0');
  final hundredths = ((time.inMilliseconds % 1000) ~/ 10).toString().padLeft(
    2,
    '0',
  );
  return '$minutes:$seconds.$hundredths';
}
