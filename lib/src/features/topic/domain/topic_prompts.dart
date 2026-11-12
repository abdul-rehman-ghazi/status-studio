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
    'makes sense on its own, starting and ending at a full thought, and '
    'lasting between 8 and 30 seconds (use the start seconds). Reply '
    'with JSON only: {"moments": [{"first": <first block number>, "last": '
    '<last block number>, "score": <0 to 1, how exactly it is about the '
    'topic>, "reason": "<one short line in English>"}]}. Reply with '
    '{"moments": []} when nothing is about the topic.\n\nTopic: $topic';

String partMessage(List<TranscriptBlock> part) =>
    part.map((block) => block.promptRow).join('\n');
