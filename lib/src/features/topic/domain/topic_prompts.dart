import 'package:status_studio/src/features/topic/domain/moment_candidate.dart';
import 'package:status_studio/src/features/topic/domain/transcript_block.dart';

/// The chat model every topic search uses (spec FR-36). One constant, so
/// the spike in §10 can swap it.
const topicModel = 'openai/gpt-oss-120b';

/// What a part's call is told: the topic, the row format and the reply
/// shape. The transcript may be in another script than the topic (Urdu
/// auto captions come as Hindi in Devanagari, §10 item 10), so meaning
/// counts, not words.
String partInstructions(String topic) =>
    'You find the moments in a video transcript that are about a topic. '
    'Each transcript row is "block number|start second|text". The '
    'transcript may be in a different language or script than the topic '
    '(for example Urdu spoken but written in Hindi script); match by '
    'meaning, not by words. A moment is a run of consecutive blocks that '
    'makes sense on its own, starting and ending at a full thought. Reply '
    'with JSON only: {"moments": [{"first": <first block number>, "last": '
    '<last block number>, "score": <0 to 1, how exactly it is about the '
    'topic>, "reason": "<one short line in English>"}]}. Reply with '
    '{"moments": []} when nothing is about the topic.\n\nTopic: $topic';

String partMessage(List<TranscriptBlock> part) =>
    part.map((block) => block.promptRow).join('\n');

/// What the picking call is told: choose the moments that together tell
/// the topic best in about [length].
String pickInstructions(String topic, Duration length) =>
    'You choose moments from a video for a clip of about '
    '${length.inSeconds} seconds about a topic. Each row is "position|'
    'seconds long|text". Order the positions from the one the clip needs '
    'most to the one it needs least; leave out moments that repeat another '
    'or are only loosely about the topic. Reply with JSON only: {"order": '
    '[<positions>]}.\n\nTopic: $topic';

String pickMessage(
  List<MomentCandidate> candidates,
  List<TranscriptBlock> blocks,
) => [
  for (final (position, candidate) in candidates.indexed)
    '$position|${candidate.lengthIn(blocks).inSeconds}|'
        '${_textOf(candidate, blocks)}',
].join('\n');

String _textOf(MomentCandidate candidate, List<TranscriptBlock> blocks) =>
    blocks
        .sublist(candidate.firstBlock, candidate.lastBlock + 1)
        .map((block) => block.text)
        .join(' ');
