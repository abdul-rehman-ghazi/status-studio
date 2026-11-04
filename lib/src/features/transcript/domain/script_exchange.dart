import 'package:status_studio/src/features/transcript/domain/transcript.dart';

/// What the user pasted holds no script rows (spec §8).
class NoScriptRowsException implements Exception {
  const NoScriptRowsException();

  @override
  String toString() => 'NoScriptRowsException';
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

// `12 | 00:21.40 | 00:30.00 | text`; the text may itself hold bars.
final _row = RegExp(
  r'^\s*(\d+)\s*\|\s*[\d:.,]+\s*\|\s*[\d:.,]+\s*\|\s*(.*\S)\s*$',
);

/// The prompt for an AI agent, with the video and every script line in it
/// (spec FR-18). Pasted as is, it needs nothing else from the user.
String scriptPromptFor({
  required String videoTitle,
  required String videoUrl,
  required Transcript transcript,
}) {
  final rows = transcript.lines
      .map(
        (line) =>
            '${line.index + 1} | ${_clock(line.start)} | ${_clock(line.end)} | '
            '${line.text.replaceAll('\n', ' ')}',
      )
      .join('\n');
  return '''
Below is a time-stamped script that was auto-transcribed from a YouTube video of a naat or song. The text has mistakes. Fix the TEXT using the real published lyrics you find online, and reply with the script in the same format.

Video title: $videoTitle
Video link: $videoUrl

Each row is: <number> | <start> | <end> | <text>

Rules:
1. Search the web for the real lyrics (naat sites, the poet's collection, the video's description). Use what you find. Never invent or improve words from memory. If you cannot find a reliable source for a row, keep its text and add " $_uncertainMark" at the end of that row.
2. Keep every row's number, start and end exactly as given. Change only the text. Do not merge, split, reorder or delete rows.
3. The video may contain verses (shaer) from a different poem. Where a row sounds like another poem, find that poem and correct the row from it.
4. Write in the same script as the input (Urdu stays in Urdu script, not Roman). No translation and no added punctuation.
5. Reply with only the corrected rows in one code block. After it, list each row you changed with the source link you used, and each row marked $_uncertainMark.

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
    final match = _row.firstMatch(row);
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
