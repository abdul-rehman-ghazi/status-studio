import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/transcript/data/whisper_transcriber.dart';
import 'package:status_studio/src/features/transcript/domain/speech_model.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';
// TranscribeResult is the return type of WhisperController.transcribe but
// isn't exported, and the fake has to name it.
// ignore: implementation_imports
import 'package:whisper_ggml/src/models/whisper_result.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

/// Answers each chunk with one 2–4 s segment, or null when [failing].
class FakeWhisperController extends WhisperController {
  FakeWhisperController({this.failing = false});

  final bool failing;
  final languages = <String>[];
  var releaseCount = 0;

  @override
  Future<TranscribeResult?> transcribe({
    required WhisperModel model,
    required String audioPath,
    String lang = 'en',
    bool diarize = false,
    String? initialPrompt,
    bool noContext = false,
    int? maxContext,
    bool suppressNonSpeechTokens = false,
    bool withSegments = false,
    bool splitOnWord = false,
    bool keepModelLoaded = false,
    String? vadModelPath,
    int? vadSpeechPadMs,
    void Function(int percent)? onProgress,
  }) async {
    languages.add(lang);
    if (failing) {
      return null;
    }
    return TranscribeResult(
      time: Duration.zero,
      transcription: WhisperTranscribeResponse(
        type: 'transcribe',
        text: 'line of $audioPath',
        segments: [
          WhisperTranscribeSegment(
            fromTs: const Duration(seconds: 2),
            toTs: const Duration(seconds: 4),
            text: 'line of $audioPath',
          ),
        ],
      ),
    );
  }

  @override
  Future<void> releaseModel() async => releaseCount++;
}

final chunks = [File('chunk_000.wav'), File('chunk_001.wav')];

void main() {
  test('second_chunk_is_offset_by_90_seconds', () async {
    final transcriber = WhisperTranscriber(FakeWhisperController());

    final batches = await transcriber
        .transcribeChunks(
          chunks,
          language: ScriptLanguage.urdu,
          model: SpeechModel.small,
        )
        .toList();

    expect(batches[1].single.start, const Duration(seconds: 92));
  });

  test('lines_are_numbered_across_chunks', () async {
    final transcriber = WhisperTranscriber(FakeWhisperController());

    final batches = await transcriber
        .transcribeChunks(
          chunks,
          language: ScriptLanguage.urdu,
          model: SpeechModel.small,
        )
        .toList();

    expect(batches[1].single.index, 1);
  });

  test('passes_the_chosen_language_to_whisper', () async {
    final whisper = FakeWhisperController();

    await WhisperTranscriber(whisper)
        .transcribeChunks(
          chunks,
          language: ScriptLanguage.urdu,
          model: SpeechModel.small,
        )
        .drain<void>();

    expect(whisper.languages, ['ur', 'ur']);
  });

  test('failed_chunk_throws_transcription_failed', () async {
    final transcriber = WhisperTranscriber(
      FakeWhisperController(failing: true),
    );

    await expectLater(
      transcriber
          .transcribeChunks(
            chunks,
            language: ScriptLanguage.auto,
            model: SpeechModel.small,
          )
          .drain<void>(),
      throwsA(isA<TranscriptionFailedException>()),
    );
  });

  test('model_is_released_after_the_last_chunk', () async {
    final whisper = FakeWhisperController();

    await WhisperTranscriber(whisper)
        .transcribeChunks(
          chunks,
          language: ScriptLanguage.auto,
          model: SpeechModel.small,
        )
        .drain<void>();

    expect(whisper.releaseCount, 1);
  });

  test('model_is_released_after_a_failure', () async {
    final whisper = FakeWhisperController(failing: true);

    await WhisperTranscriber(whisper)
        .transcribeChunks(
          chunks,
          language: ScriptLanguage.auto,
          model: SpeechModel.small,
        )
        .drain<void>()
        .catchError((Object _) {});

    expect(whisper.releaseCount, 1);
  });
}
