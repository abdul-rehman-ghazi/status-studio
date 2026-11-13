import 'dart:convert';

import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/topic/domain/topic_prompts.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

/// The chat model that translates a linked clip's lyrics (spec FR-37): the
/// one the topic search uses.
const translationModel = topicModel;

/// What the translation call is told: one caption line in, one out, with
/// the same IDs, so every line keeps its times.
String translationInstructions(ScriptLanguage target) =>
    'You translate the lines of a video\'s script into ${target.label}'
    '${scriptNoteFor(target)}, for captions shown one line at a time. The '
    'lines may be in another language or script (for example Urdu written '
    'in Hindi script); translate by meaning, keep each line short and '
    'natural, and never merge or split lines. Reply with JSON only: '
    '{"lines": [{"id": <the line\'s id>, "text": "<the line in '
    '${target.label}>"}]}, one entry for every line given.';

/// The lines as JSON: `{"lines": [{"id": 0, "text": "…"}, …]}`.
String translationMessage(List<TranscriptLine> lines) => jsonEncode({
  'lines': [
    for (final (id, line) in lines.indexed) {'id': id, 'text': line.text},
  ],
});

/// [lines] with their text replaced by the reply's, times kept. Throws
/// [LyricsNotTranslatedException] unless every line came back, non-empty.
List<TranscriptLine> translatedLines(
  Map<String, Object?> reply,
  List<TranscriptLine> lines,
) {
  final texts = _textsById(reply);
  return [
    for (final (id, line) in lines.indexed)
      line.copyWith(text: _textFor(texts, id)),
  ];
}

Map<int, String> _textsById(Map<String, Object?> reply) {
  final entries = reply['lines'];
  if (entries is! List<Object?>) {
    throw const LyricsNotTranslatedException('No "lines" list.');
  }
  return {
    for (final entry in entries)
      if (entry case {'id': final int id, 'text': final String text}) id: text,
  };
}

String _textFor(Map<int, String> texts, int id) {
  final text = texts[id]?.trim() ?? '';
  if (text.isEmpty) {
    throw LyricsNotTranslatedException('Line $id came back empty.');
  }
  // A caption line stays one line (FR-21).
  return text.replaceAll(RegExp(r'\s*\n\s*'), ' ');
}
