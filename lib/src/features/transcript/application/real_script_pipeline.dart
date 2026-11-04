import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/work_amount.dart';
import 'package:status_studio/src/features/source/data/video_source.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';
import 'package:status_studio/src/features/transcript/data/audio_preparer.dart';
import 'package:status_studio/src/features/transcript/data/groq_client.dart';
import 'package:status_studio/src/features/transcript/data/groq_key_store.dart';
import 'package:status_studio/src/features/transcript/data/groq_transcriber.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';
import 'package:status_studio/src/features/transcript/domain/language_inference.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';
import 'package:status_studio/src/features/transcript/domain/segment_lines.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';

/// Overall progress at the start of each stage (plan M3 Task 7).
const _audioDownloadEnd = 0.3;
const _languageStage = 0.35;

/// Everything the pipeline uses, in one value so it stays within three
/// parameters.
class ScriptPipelineServices {
  const ScriptPipelineServices({
    required this.videos,
    required this.audio,
    required this.store,
    required this.groq,
  });

  final VideoSource videos;
  final AudioPreparer audio;
  final Future<TranscriptStore> store;

  /// Groq's transcriber with the saved key; throws [NoGroqKeyException]
  /// when there is none (FR-12a).
  final Future<GroqTranscriber> Function() groq;
}

/// Writes a video's script from, in order: a saved script, YouTube
/// captions, or Groq (FR-3), saving what it writes (FR-14).
class RealScriptPipeline implements ScriptPipeline {
  RealScriptPipeline(this.services);

  final ScriptPipelineServices services;

  @override
  Stream<ScriptProgress> run(
    SourceVideo video,
    ScriptLanguage language,
  ) async* {
    final store = await services.store;
    // Before the saved-script check too, so a script saved before videos
    // were kept joins the Recent list once its link is opened again.
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
    final captions = await _captions(video, language);
    if (captions != null) {
      yield* _finishWithCaptions(store, key, captions);
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

  /// The video's captions, if it has a usable track. Any caption failure
  /// falls through to Groq; the script audio and partial progress may
  /// already be on the phone.
  Future<Transcript?> _captions(
    SourceVideo video,
    ScriptLanguage language,
  ) async {
    try {
      return await services.videos.fetchCaptions(video, language);
    } on Exception {
      return null;
    }
  }

  Stream<ScriptProgress> _finishWithCaptions(
    TranscriptStore store,
    TranscriptKey key,
    Transcript captions,
  ) async* {
    yield ScriptProgress(
      stage: ScriptStage.detectingLanguage,
      fraction: _languageStage,
      transcript: _empty(captions.languageCode),
    );
    await store.save(
      key,
      SavedTranscript(
        transcript: captions,
        source: captionsSource,
        savedAt: store.clock(),
      ),
    );
    yield ScriptProgress(
      stage: ScriptStage.done,
      fraction: 1,
      transcript: captions,
    );
  }

  Stream<ScriptProgress> _write(SourceVideo video, TranscriptKey key) async* {
    final store = await services.store;
    // Before any download: without a key there is nothing to wait for.
    final groq = await services.groq();
    final requested = key.language.whisperCode;
    final audio = _ScriptAudio();
    yield* _downloadAudio(video, requested, audio);
    final pieces = await services.audio.splitAudioCopy(audio.file);
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

  /// Reports the download's bytes as they arrive, then leaves the file in
  /// [audio]: a generator can't both yield progress and return a value.
  Stream<ScriptProgress> _downloadAudio(
    SourceVideo video,
    String languageCode,
    _ScriptAudio audio,
  ) async* {
    yield ScriptProgress(
      stage: ScriptStage.downloadingAudio,
      fraction: 0,
      transcript: _empty(languageCode),
    );
    final amounts = StreamController<WorkAmount>();
    final download = services.videos
        .downloadScriptAudio(video, onProgress: amounts.add)
        .whenComplete(amounts.close);
    await for (final amount in amounts.stream) {
      yield ScriptProgress(
        stage: ScriptStage.downloadingAudio,
        fraction: _audioDownloadEnd * amount.fraction,
        transcript: _empty(languageCode),
        step: amount,
      );
    }
    audio.file = await download;
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

/// The script audio once [RealScriptPipeline._downloadAudio] has it.
class _ScriptAudio {
  late File file;
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
      videos: ref.watch(videoSourceProvider),
      audio: ref.watch(audioPreparerProvider),
      store: ref.watch(transcriptStoreProvider.future),
      groq: () => _groqTranscriber(ref.read(groqKeyStoreProvider)),
    ),
  ),
);

Future<GroqTranscriber> _groqTranscriber(GroqKeyStore keys) async =>
    GroqTranscriber(GroqClient(apiKey: await keys.savedKey()));
