import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/work_amount.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';
import 'package:status_studio/src/features/transcript/data/audio_preparer.dart';
import 'package:status_studio/src/features/transcript/data/groq_client.dart';
import 'package:status_studio/src/features/transcript/data/groq_key_store.dart';
import 'package:status_studio/src/features/transcript/data/groq_transcriber.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';
import 'package:status_studio/src/features/transcript/domain/audio_piece.dart';
import 'package:status_studio/src/features/transcript/domain/language_inference.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';
import 'package:status_studio/src/features/transcript/domain/segment_lines.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';

/// Overall progress at the start of each stage (plan M3 Task 7).
const _audioPreparedAt = 0.3;
const _languageStage = 0.35;

/// Everything the pipeline uses, in one value so it stays within three
/// parameters.
class ScriptPipelineServices {
  const ScriptPipelineServices({
    required this.sources,
    required this.audio,
    required this.store,
    required this.groq,
  });

  /// Where the kept videos are (spec FR-1).
  final Future<SourceCache> sources;
  final AudioPreparer audio;
  final Future<TranscriptStore> store;

  /// Groq's transcriber with the saved key; throws [NoGroqKeyException]
  /// when there is none (FR-12a).
  final Future<GroqTranscriber> Function() groq;
}

/// Writes a video's script from, in order: a saved script, or Groq on the
/// audio cut from the kept video (FR-3), saving what it writes (FR-14).
class RealScriptPipeline implements ScriptPipeline {
  RealScriptPipeline(this.services);

  final ScriptPipelineServices services;

  @override
  Stream<ScriptProgress> run(
    SourceVideo video,
    ScriptLanguage language,
  ) async* {
    final store = await services.store;
    // Before the saved-script check too, so a script saved earlier still
    // joins the Recent list once its video is opened again.
    await store.saveVideo(video);
    final key = TranscriptKey(videoId: video.videoId, language: language);
    final saved = await _savedScript(store, key);
    if (saved != null) {
      yield ScriptProgress(
        stage: ScriptStage.done,
        fraction: 1,
        transcript: saved.transcript,
        savedAt: saved.savedAt,
      );
      return;
    }
    yield* _write(video, key);
  }

  @override
  Stream<ScriptProgress> writeAgain(
    SourceVideo video,
    ScriptLanguage language,
  ) async* {
    final store = await services.store;
    await store.saveVideo(video);
    yield* _write(
      video,
      TranscriptKey(videoId: video.videoId, language: language),
    );
  }

  /// The saved script for [key], if any.
  Future<SavedTranscript?> _savedScript(
    TranscriptStore store,
    TranscriptKey key,
  ) async {
    try {
      return await store.load(key);
    } on NoSavedTranscriptException {
      return null;
    }
  }

  Stream<ScriptProgress> _write(SourceVideo video, TranscriptKey key) async* {
    // Before any audio work: without a key there is nothing to wait for.
    final groq = await services.groq();
    final keptVideo = await _keptVideo(video);
    final prepared = _PreparedPieces();
    yield* _prepareAudio(video, keptVideo, key.language.whisperCode, prepared);
    try {
      yield* _transcribe(video, key, (groq: groq, pieces: prepared.pieces));
    } finally {
      // A retry cuts them again, so they never outlive the run.
      await services.audio.discardPieces(prepared.pieces);
    }
  }

  Stream<ScriptProgress> _transcribe(
    SourceVideo video,
    TranscriptKey key,
    ({GroqTranscriber groq, List<AudioPiece> pieces}) work,
  ) async* {
    final store = await services.store;
    final groq = work.groq;
    final pieces = work.pieces;
    final requested = key.language.whisperCode;
    yield ScriptProgress(
      stage: ScriptStage.detectingLanguage,
      fraction: _languageStage,
      transcript: _empty(requested),
    );
    final partial = await _partial(store, key);
    final lines = [...partial.lines];
    var completed = partial.completedChunks;
    // The language is detected inside the first piece, so writing starts
    // now rather than after a piece's worth of silence.
    Transcript written() =>
        Transcript(languageCode: requested, lines: [...lines]);
    yield _writing(
      video,
      written(),
      chunks: (done: completed.toDouble(), of: pieces.length),
    );
    final events = groq.transcribePieces(
      GroqTranscription(
        pieces: pieces,
        language: key.language,
        completedPieces: completed,
        firstIndex: lines.length,
      ),
    );
    await for (final event in events) {
      switch (event) {
        case ChunkProgress(:final position, :final fraction):
          yield _writing(
            video,
            written(),
            chunks: (done: position + fraction, of: pieces.length),
          );
        case ChunkWritten(lines: final batch):
          lines.addAll(batch);
          completed++;
          await store.savePartial(
            key,
            groqSource,
            PartialTranscript(completedChunks: completed, lines: lines),
          );
          yield _writing(
            video,
            written(),
            chunks: (done: completed.toDouble(), of: pieces.length),
          );
      }
    }
    yield await _finish(store, key, lines);
  }

  /// The [transcript] so far, [chunks.done] of [chunks.of] chunks in; a
  /// fraction while a chunk is being written.
  ScriptProgress _writing(
    SourceVideo video,
    Transcript transcript, {
    required ({double done, int of}) chunks,
  }) {
    return ScriptProgress(
      stage: ScriptStage.transcribing,
      fraction: _languageStage + (1 - _languageStage) * chunks.done / chunks.of,
      transcript: transcript,
      step: _transcribed(video, chunksDone: chunks.done, of: chunks.of),
    );
  }

  Future<File> _keptVideo(SourceVideo video) async {
    final cache = await services.sources;
    final kept = cache.keptLocalVideos(video.videoId);
    if (kept.isEmpty) {
      throw KeptVideoMissingException(video.videoId);
    }
    return kept.first;
  }

  /// Reports how much of the video FFmpeg has read, then leaves the pieces
  /// in [prepared]: a generator can't both yield progress and return a
  /// value.
  Stream<ScriptProgress> _prepareAudio(
    SourceVideo video,
    File keptVideo,
    String languageCode,
    _PreparedPieces prepared,
  ) async* {
    yield ScriptProgress(
      stage: ScriptStage.preparingAudio,
      fraction: 0,
      transcript: _empty(languageCode),
    );
    final processed = StreamController<Duration>();
    // A failure is rethrown below, or after a cancel, when nobody awaits it:
    // ignore() keeps it from reaching the zone as unhandled.
    final cutting =
        services.audio
            .cutScriptPieces(keptVideo, onProcessed: processed.add)
            .whenComplete(processed.close)
          ..ignore();
    var finished = false;
    try {
      await for (final readUpTo in processed.stream) {
        final amount = _audioRead(video, readUpTo);
        yield ScriptProgress(
          stage: ScriptStage.preparingAudio,
          fraction: _audioPreparedAt * amount.fraction,
          transcript: _empty(languageCode),
          step: amount,
        );
      }
      prepared.pieces = await cutting;
      finished = true;
    } finally {
      // Leaving early (the user cancelled) must stop FFmpeg too, or a
      // retry would empty the folder it is still writing to. A run that
      // ended is left alone: cancelling stops every FFmpeg session.
      if (!finished) {
        await services.audio.stopRunning();
      }
    }
  }

  Future<PartialTranscript> _partial(
    TranscriptStore store,
    TranscriptKey key,
  ) async {
    try {
      return await store.loadPartial(key, groqSource);
    } on NoSavedTranscriptException {
      return const PartialTranscript(completedChunks: 0, lines: []);
    }
  }

  Future<ScriptProgress> _finish(
    TranscriptStore store,
    TranscriptKey key,
    List<TranscriptLine> lines,
  ) async {
    if (lines.isEmpty) {
      await store.clearPartial(key, groqSource);
      throw const NoSpeechFoundException();
    }
    final transcript = Transcript(
      languageCode: key.language == ScriptLanguage.auto
          ? inferLanguageCode(lines.map((line) => line.text).join(' '))
          : key.language.whisperCode,
      lines: lines,
    );
    await store.save(
      key,
      SavedTranscript(
        transcript: transcript,
        source: groqSource,
        savedAt: store.clock(),
      ),
    );
    await store.clearPartial(key, groqSource);
    return ScriptProgress(
      stage: ScriptStage.done,
      fraction: 1,
      transcript: transcript,
    );
  }
}

/// The pieces once [RealScriptPipeline._prepareAudio] has cut them.
class _PreparedPieces {
  late List<AudioPiece> pieces;
}

/// How much of [video] FFmpeg has read, never more than its length.
WorkAmount _audioRead(SourceVideo video, Duration readUpTo) {
  final total = video.duration.inMilliseconds;
  return WorkAmount(
    done: math.min(total, readUpTo.inMilliseconds),
    total: total,
    unit: WorkUnit.audioMilliseconds,
  );
}

/// Audio transcribed after [chunksDone] of [of] chunks, out of the video's
/// length; the last chunk is usually shorter than the others.
WorkAmount _transcribed(
  SourceVideo video, {
  required double chunksDone,
  required int of,
}) {
  final total = video.duration.inMilliseconds;
  final done = chunksDone >= of
      ? total
      : math.min(
          total,
          (chunksDone * transcriptionChunk.inMilliseconds).round(),
        );
  return WorkAmount(done: done, total: total, unit: WorkUnit.audioMilliseconds);
}

Transcript _empty(String languageCode) =>
    Transcript(languageCode: languageCode, lines: const []);

final realScriptPipelineProvider = Provider<ScriptPipeline>(
  (ref) => RealScriptPipeline(
    ScriptPipelineServices(
      sources: ref.watch(sourceCacheProvider.future),
      audio: ref.watch(audioPreparerProvider),
      store: ref.watch(transcriptStoreProvider.future),
      groq: () => _groqTranscriber(ref.read(groqKeyStoreProvider)),
    ),
  ),
);

Future<GroqTranscriber> _groqTranscriber(GroqKeyStore keys) async =>
    GroqTranscriber(GroqClient(apiKey: await keys.savedKey()));
