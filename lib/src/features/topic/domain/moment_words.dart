import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/topic/domain/topic_cut.dart';
import 'package:status_studio/src/features/topic/domain/topic_prompts.dart';
import 'package:status_studio/src/features/topic/domain/transcript_block.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';

/// What Update words tells Groq (spec FR-40): only the words between each
/// moment's exact times, in the output language.
String momentWordsInstructions(ScriptLanguage output) =>
    'You write the words of moments cut from a video transcript. For each '
    'moment you get "moment <id>|<start second>|<end second>" and then the '
    'transcript rows around it as "<start second>|<text>". The rows may '
    'start before or end after the moment, and may be in another language '
    'or script (for example Urdu written in Hindi script). Write only the '
    'words spoken between the moment\'s start and end, in ${output.label}'
    '${scriptNoteFor(output)}, translated if spoken in another language. '
    'Reply with JSON only: {"moments": [{"id": <id>, "text": "<the '
    'words>"}]}, one entry for every moment given.';

/// Each moment's header and the blocks that overlap it, numbered from 0 in
/// [cuts]' order.
String momentWordsMessage(List<TopicCut> cuts, List<TranscriptBlock> blocks) =>
    [
      for (final (id, cut) in cuts.indexed) ...[
        'moment $id|${_seconds(cut.start)}|${_seconds(cut.end)}',
        for (final block in blocksOverlapping(cut, blocks))
          '${block.start.inSeconds}|${block.text}',
      ],
    ].join('\n');

/// The transcript blocks with any part inside [cut].
List<TranscriptBlock> blocksOverlapping(
  TopicCut cut,
  List<TranscriptBlock> blocks,
) => [
  for (final block in blocks)
    if (block.end > cut.start && block.start < cut.end) block,
];

/// The reply's words for each of [cuts]. Throws
/// [GroqUnreadableReplyException] unless every moment came back with words.
Map<TopicCut, String> momentWordsFromReply(
  Map<String, Object?> reply,
  List<TopicCut> cuts,
) {
  final moments = reply['moments'];
  if (moments is! List<Object?>) {
    throw const GroqUnreadableReplyException('No "moments" list.');
  }
  final texts = {
    for (final moment in moments)
      if (moment case {'id': final int id, 'text': final String text})
        id: text.trim(),
  };
  return {for (final (id, cut) in cuts.indexed) cut: _wordsFor(texts, id)};
}

String _wordsFor(Map<int, String> texts, int id) {
  final text = texts[id] ?? '';
  if (text.isEmpty) {
    throw GroqUnreadableReplyException('Moment $id came back without words.');
  }
  return text;
}

/// Tenths, so a 0.5 s nudge shows in what is sent.
String _seconds(Duration time) =>
    (time.inMilliseconds / Duration.millisecondsPerSecond).toStringAsFixed(1);
