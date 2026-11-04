import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/work_amount.dart';
import 'package:status_studio/src/features/settings/application/settings_controller.dart';
import 'package:status_studio/src/features/source/data/video_source.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/application/script_engine.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';
import 'package:status_studio/src/features/transcript/data/audio_preparer.dart';
import 'package:status_studio/src/features/transcript/data/groq_client.dart';
import 'package:status_studio/src/features/transcript/data/groq_key_store.dart';
import 'package:status_studio/src/features/transcript/data/groq_transcriber.dart';
import 'package:status_studio/src/features/transcript/data/model_manager.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';
import 'package:status_studio/src/features/transcript/data/whisper_transcriber.dart';
import 'package:status_studio/src/features/transcript/domain/language_inference.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';
import 'package:status_studio/src/features/transcript/domain/speech_model.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';

/// Overall progress at the start of each stage (plan M3 Task 7).
const _audioDownloadEnd = 0.3;
const _languageStage = 0.35;

/// Matches `AudioPreparer.splitIntoChunks`.
const _chunkLength = Duration(seconds: 90);

/// Everything the pipeline uses, in one value so it stays within three
/// parameters.
class ScriptPipelineServices {
  const ScriptPipelineServices({
    required this.models,
    required this.videos,
    required this.audio,
    required this.whisper,
    required this.store,
    this.groq = _noGroq,
  });

  final ModelManager models;
  final VideoSource videos;
  final AudioPreparer audio;
  final WhisperTranscriber whisper;
  final Future<TranscriptStore> store;

  /// Groq's transcriber when the switch is on and a key is saved, else
  /// `null` (FR-12a).
  final Future<GroqTranscriber?> Function() groq;
}

Future<GroqTranscriber?> _noGroq() async => null;

/// Writes a video's script from, in order: a saved script, YouTube
/// captions, or Whisper on the phone (FR-3), saving what it writes (FR-14).
class RealScriptPipeline implements ScriptPipeline {
  RealScriptPipeline(this.services, {required this.model});

  final ScriptPipelineServices services;
  final SpeechModel model;

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
  /// falls through to Whisper, which may need nothing from the network:
  /// the model, script audio and partial progress can all be on the phone.
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
    final requested = key.language.whisperCode;
    final engine = await _engine();
    yield* engine.prepare(requested);
    final audio = _ScriptAudio();
    yield* _downloadAudio(video, requested, audio);
    final pieces = await engine.piecesOf(audio.file);
    yield ScriptProgress(
      stage: ScriptStage.detectingLanguage,
      fraction: _languageStage,
      transcript: _empty(requested),
    );
    final partial = await _partial(store, key, engine);
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
    final events = engine.write(
      PieceRun(
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
            engine.source,
            PartialTranscript(completedChunks: completed, lines: lines),
          );
          yield _writing(
            video,
            written(),
            chunks: (done: completed.toDouble(), of: pieces.length),
          );
      }
    }
    yield await _finish(store, key, engine, lines);
  }

  Future<ScriptEngine> _engine() async {
    final groq = await services.groq();
    if (groq != null) {
      return GroqEngine(audio: services.audio, groq: groq);
    }
    return WhisperEngine(
      models: services.models,
      audio: services.audio,
      whisper: services.whisper,
      model: model,
    );
  }

  /// The [transcript] so far, [chunks.done] of [chunks.of] chunks in; a
  /// fraction while Whisper is inside a chunk.
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
      fraction: modelDownloadShare,
      transcript: _empty(languageCode),
    );
    final amounts = StreamController<WorkAmount>();
    final download = services.videos
        .downloadScriptAudio(video, onProgress: amounts.add)
        .whenComplete(amounts.close);
    await for (final amount in amounts.stream) {
      yield ScriptProgress(
        stage: ScriptStage.downloadingAudio,
        fraction:
            modelDownloadShare +
            (_audioDownloadEnd - modelDownloadShare) * amount.fraction,
        transcript: _empty(languageCode),
        step: amount,
      );
    }
    audio.file = await download;
  }

  Future<PartialTranscript> _partial(
    TranscriptStore store,
    TranscriptKey key,
    ScriptEngine engine,
  ) async {
    try {
      return await store.loadPartial(key, engine.source);
    } on NoSavedTranscriptException {
      return const PartialTranscript(completedChunks: 0, lines: []);
    }
  }

  Future<ScriptProgress> _finish(
    TranscriptStore store,
    TranscriptKey key,
    ScriptEngine engine,
    List<TranscriptLine> lines,
  ) async {
    if (lines.isEmpty) {
      await store.clearPartial(key, engine.source);
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
        source: engine.source,
        savedAt: store.clock(),
      ),
    );
    await store.clearPartial(key, engine.source);
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
      : math.min(total, (chunksDone * _chunkLength.inMilliseconds).round());
  return WorkAmount(done: done, total: total, unit: WorkUnit.audioMilliseconds);
}

Transcript _empty(String languageCode) =>
    Transcript(languageCode: languageCode, lines: const []);

/// The model chosen in Settings (spec FR-12), small until it has loaded.
/// Home watches the setting, so it has loaded before a script starts.
final whisperModelProvider = Provider<SpeechModel>(
  (ref) => ref.watch(whisperModelSettingProvider).value ?? defaultSpeechModel,
);

final realScriptPipelineProvider = Provider<ScriptPipeline>(
  (ref) => RealScriptPipeline(
    ScriptPipelineServices(
      models: ref.watch(modelManagerProvider),
      videos: ref.watch(videoSourceProvider),
      audio: ref.watch(audioPreparerProvider),
      whisper: ref.watch(whisperTranscriberProvider),
      store: ref.watch(transcriptStoreProvider.future),
      groq: () => _groqIfOn(ref.read(groqKeyStoreProvider)),
    ),
    model: ref.watch(whisperModelProvider),
  ),
);

Future<GroqTranscriber?> _groqIfOn(GroqKeyStore keys) async {
  if (!await keys.isEnabled()) {
    return null;
  }
  return GroqTranscriber(GroqClient(apiKey: await keys.savedKey()));
}
