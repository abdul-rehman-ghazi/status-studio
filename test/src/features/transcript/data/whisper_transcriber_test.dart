import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/transcript/data/whisper_transcriber.dart';
import 'package:status_studio/src/features/transcript/domain/speech_model.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';

import '../../../../helpers/fake_whisper.dart';

final chunks = [
  File('chunk_000.wav'),
  File('chunk_001.wav'),
  File('chunk_002.wav'),
];

ChunkTranscription job({
  ScriptLanguage language = ScriptLanguage.urdu,
  int completedChunks = 0,
  int firstIndex = 0,
}) => ChunkTranscription(
  chunks: chunks,
  language: language,
  model: SpeechModel.small,
  completedChunks: completedChunks,
  firstIndex: firstIndex,
);

/// Each written chunk's lines, without the progress events.
Future<List<List<TranscriptLine>>> writtenBatches(
  Stream<ChunkEvent> events,
) async => [
  for (final event in await events.toList())
    if (event is ChunkWritten) event.lines,
];

void main() {
  test('reports_whisper_progress_inside_a_chunk', () async {
    final transcriber = WhisperTranscriber(FakeWhisperController());

    final events = await transcriber.transcribeChunks(job()).toList();

    expect(
      events.whereType<ChunkProgress>().first,
      const ChunkProgress(position: 0, fraction: 0.5),
    );
  });

  test('second_chunk_is_offset_by_90_seconds', () async {
    final transcriber = WhisperTranscriber(FakeWhisperController());

    final batches = await writtenBatches(transcriber.transcribeChunks(job()));

    expect(batches[1].single.start, const Duration(seconds: 92));
  });

  test('lines_are_numbered_across_chunks', () async {
    final transcriber = WhisperTranscriber(FakeWhisperController());

    final batches = await writtenBatches(transcriber.transcribeChunks(job()));

    expect(batches[2].single.index, 2);
  });

  test('passes_the_chosen_language_to_whisper', () async {
    final whisper = FakeWhisperController();

    await WhisperTranscriber(whisper).transcribeChunks(job()).drain<void>();

    expect(whisper.languages, ['ur', 'ur', 'ur']);
  });

  test('resumed_run_skips_completed_chunks', () async {
    final whisper = FakeWhisperController();

    await WhisperTranscriber(whisper)
        .transcribeChunks(job(completedChunks: 2, firstIndex: 5))
        .drain<void>();

    expect(whisper.transcribedPaths, ['chunk_002.wav']);
  });

  test('resumed_run_keeps_absolute_times_and_numbering', () async {
    final transcriber = WhisperTranscriber(FakeWhisperController());

    final batches = await writtenBatches(
      transcriber.transcribeChunks(job(completedChunks: 2, firstIndex: 5)),
    );

    expect(
      (batches.single.single.index, batches.single.single.start),
      (5, const Duration(seconds: 182)),
    );
  });

  test('failed_chunk_throws_transcription_failed', () async {
    final transcriber = WhisperTranscriber(
      FakeWhisperController(failing: true),
    );

    await expectLater(
      transcriber.transcribeChunks(job()).drain<void>(),
      throwsA(isA<TranscriptionFailedException>()),
    );
  });

  test('model_is_released_after_the_last_chunk', () async {
    final whisper = FakeWhisperController();

    await WhisperTranscriber(whisper).transcribeChunks(job()).drain<void>();

    expect(whisper.releaseCount, 1);
  });

  test('model_is_released_after_a_failure', () async {
    final whisper = FakeWhisperController(failing: true);

    await WhisperTranscriber(whisper)
        .transcribeChunks(job())
        .drain<void>()
        .catchError((Object _) {});

    expect(whisper.releaseCount, 1);
  });
}
