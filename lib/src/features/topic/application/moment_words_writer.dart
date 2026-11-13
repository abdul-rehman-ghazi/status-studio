import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/topic/domain/moment_words.dart';
import 'package:status_studio/src/features/topic/domain/topic_cut.dart';
import 'package:status_studio/src/features/topic/domain/topic_prompts.dart';
import 'package:status_studio/src/features/topic/domain/transcript_block.dart';
import 'package:status_studio/src/features/transcript/data/groq_chat_client.dart';
import 'package:status_studio/src/features/transcript/data/groq_client.dart';

/// What Update words writes (spec FR-40).
class MomentWordsOrder {
  const MomentWordsOrder({
    required this.cuts,
    required this.blocks,
    required this.output,
  });

  final List<TopicCut> cuts;

  /// The transcript the moments were found in.
  final List<TranscriptBlock> blocks;
  final ScriptLanguage output;
}

/// Update words (spec FR-40): one Groq chat call, text only, for every
/// moment whose words wait.
class MomentWordsWriter {
  const MomentWordsWriter(this.groq);

  final GroqChatClientOpener groq;

  /// Each moment's new words. Throws the Groq errors of `groq_errors.dart`,
  /// including no key or no consent.
  Future<Map<TopicCut, String>> write(MomentWordsOrder order) async {
    final client = await groq();
    final reply = await client.chatJson(
      GroqChatRequest(
        model: topicModel,
        instructions: momentWordsInstructions(order.output),
        message: momentWordsMessage(order.cuts, order.blocks),
      ),
    );
    return momentWordsFromReply(reply, order.cuts);
  }
}

final momentWordsWriterProvider = Provider<MomentWordsWriter>(
  (ref) => MomentWordsWriter(ref.watch(groqChatClientProvider)),
);
