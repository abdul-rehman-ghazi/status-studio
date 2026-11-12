import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/join/data/linked_clip_store.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';
import 'package:status_studio/src/features/transcript/data/groq_client.dart';
import 'package:status_studio/src/features/transcript/data/groq_consent_store.dart';
import 'package:status_studio/src/features/transcript/data/groq_key_store.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';
import 'package:status_studio/src/features/transcript/domain/lyrics_translation.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';

/// Writing takes most of a translated run; the translation the rest.
const _writingShare = 0.9;

class TranslatingScriptPipelineServices {
  const TranslatingScriptPipelineServices({
    required this.written,
    required this.store,
    required this.links,
    required this.groq,
  });

  /// Writes what was said (the real pipeline).
  final ScriptPipeline written;
  final Future<TranscriptStore> store;
  final LinkedClipStore links;

  /// Throws as the script pipeline's Groq does without a key or consent.
  final Future<GroqClient> Function() groq;
}

/// Lyrics in the output language for a clip joined from a link (spec
/// FR-37): Groq writes what was said, its chat model translates the lines
/// keeping their times, and only the translation is shown and kept. Any
/// other video, or a link clip asked for as spoken (automatic), passes
/// through unchanged.
class TranslatingScriptPipeline implements ScriptPipeline {
  const TranslatingScriptPipeline(this.services);

  final TranslatingScriptPipelineServices services;

  @override
  Stream<ScriptProgress> run(
    SourceVideo video,
    ScriptLanguage language,
  ) async* {
    final key = await _translationKey(video, language);
    if (key == null) {
      yield* services.written.run(video, language);
      return;
    }
    final saved = await _saved(key);
    if (saved != null) {
      yield _reopened(saved, language);
      return;
    }
    yield* _translated(key, services.written.run(video, ScriptLanguage.auto));
  }

  @override
  Stream<ScriptProgress> writeAgain(
    SourceVideo video,
    ScriptLanguage language,
  ) async* {
    final key = await _translationKey(video, language);
    if (key == null) {
      yield* services.written.writeAgain(video, language);
      return;
    }
    yield* _translated(
      key,
      services.written.writeAgain(video, ScriptLanguage.auto),
    );
  }

  /// Where a translation of [video] into [language] is saved; null when
  /// nothing is translated: not a linked clip, or asked for as spoken.
  Future<TranscriptKey?> _translationKey(
    SourceVideo video,
    ScriptLanguage language,
  ) async {
    if (language == ScriptLanguage.auto ||
        await services.links.read(video.videoId) == null) {
      return null;
    }
    return TranscriptKey(videoId: video.videoId, language: language);
  }

  Future<SavedTranscript?> _saved(TranscriptKey key) async {
    try {
      return await (await services.store).load(key);
    } on NoSavedTranscriptException {
      return null;
    }
  }

  /// The spoken lines are hidden while written: only the translation is
  /// ever shown.
  Stream<ScriptProgress> _translated(
    TranscriptKey key,
    Stream<ScriptProgress> spoken,
  ) async* {
    await for (final progress in spoken) {
      if (progress.stage == ScriptStage.done) {
        yield* _translate(key, progress.transcript);
        return;
      }
      yield _hidden(progress, key.language);
    }
  }

  Stream<ScriptProgress> _translate(
    TranscriptKey key,
    Transcript spoken,
  ) async* {
    final target = key.language;
    yield ScriptProgress(
      stage: ScriptStage.translating,
      fraction: _writingShare,
      transcript: Transcript(
        languageCode: spoken.languageCode,
        lines: const [],
      ),
      translatesTo: target,
    );
    final transcript = Transcript(
      languageCode: target.whisperCode,
      lines: spoken.languageCode == target.whisperCode
          ? spoken.lines
          : await _translatedLines(spoken.lines, target),
    );
    await _keepOnly(key, transcript);
    yield ScriptProgress(
      stage: ScriptStage.done,
      fraction: 1,
      transcript: transcript,
      translatesTo: target,
    );
  }

  Future<List<TranscriptLine>> _translatedLines(
    List<TranscriptLine> lines,
    ScriptLanguage target,
  ) async {
    final groq = await services.groq();
    final reply = await groq.chatJson(
      GroqChatRequest(
        model: translationModel,
        instructions: translationInstructions(target),
        message: translationMessage(lines),
      ),
    );
    return translatedLines(reply, lines);
  }

  /// Saves the translation under the output language and drops the spoken
  /// script, so the video reopens in one language (spec FR-37).
  Future<void> _keepOnly(TranscriptKey key, Transcript transcript) async {
    final store = await services.store;
    await store.save(
      key,
      SavedTranscript(
        transcript: transcript,
        source: translatedSource,
        savedAt: store.clock(),
      ),
    );
    await store.delete(
      TranscriptKey(videoId: key.videoId, language: ScriptLanguage.auto),
    );
  }
}

ScriptProgress _hidden(ScriptProgress progress, ScriptLanguage target) =>
    ScriptProgress(
      stage: progress.stage,
      fraction: progress.fraction * _writingShare,
      transcript: Transcript(
        languageCode: progress.transcript.languageCode,
        lines: const [],
      ),
      step: progress.step,
      translatesTo: target,
    );

ScriptProgress _reopened(SavedTranscript saved, ScriptLanguage target) =>
    ScriptProgress(
      stage: ScriptStage.done,
      fraction: 1,
      transcript: saved.transcript,
      savedAt: saved.savedAt,
      translatesTo: target,
    );

/// The key first, so a user without one is sent to Settings before being
/// asked for consent (as the script pipeline does).
Future<GroqClient> _groqClient(
  GroqKeyStore keys,
  GroqConsentStore consent,
) async {
  final apiKey = await keys.savedKey();
  await consent.requireGiven();
  return GroqClient(apiKey: apiKey, beforeUpload: consent.requireGiven);
}

ScriptPipeline translatingScriptPipeline(Ref ref, ScriptPipeline written) =>
    TranslatingScriptPipeline(
      TranslatingScriptPipelineServices(
        written: written,
        store: ref.watch(transcriptStoreProvider.future),
        links: ref.watch(linkedClipStoreProvider),
        groq: () => _groqClient(
          ref.read(groqKeyStoreProvider),
          ref.read(groqConsentStoreProvider),
        ),
      ),
    );
