import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/work_amount.dart';
import 'package:status_studio/src/features/settings/application/settings_controller.dart';
import 'package:status_studio/src/features/source/data/video_source.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';
import 'package:status_studio/src/features/transcript/data/audio_preparer.dart';
import 'package:status_studio/src/features/transcript/data/model_manager.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';
import 'package:status_studio/src/features/transcript/data/whisper_transcriber.dart';
import 'package:status_studio/src/features/transcript/domain/language_inference.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';
import 'package:status_studio/src/features/transcript/domain/speech_model.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';

/// Overall progress at the start of each stage (plan M3 Task 7).
const _modelShare = 0.15;
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
  });

  final ModelManager models;
  final VideoSource videos;
  final AudioPreparer audio;
  final WhisperTranscriber whisper;
  final Future<TranscriptStore> store;
}

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
    yield* _whisper(video, key);
  }

  @override
  Stream<ScriptProgress> writeAgain(
    SourceVideo video,
    ScriptLanguage language,
  ) => _whisper(
    video,
    TranscriptKey(videoId: video.videoId, language: language),
  );

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

  Stream<ScriptProgress> _whisper(SourceVideo video, TranscriptKey key) async* {
    final store = await services.store;
    final requested = key.language.whisperCode;
    yield* _ensureModel(requested);
    final audio = _ScriptAudio();
    yield* _downloadAudio(video, requested, audio);
    final chunks = await _chunksOf(audio.file);
    yield ScriptProgress(
      stage: ScriptStage.detectingLanguage,
      fraction: _languageStage,
      transcript: _empty(requested),
    );
    final partial = await _partial(store, key);
    final lines = [...partial.lines];
    var completed = partial.completedChunks;
    final batches = services.whisper.transcribeChunks(
      ChunkTranscription(
        chunks: chunks,
        language: key.language,
        model: model,
        completedChunks: completed,
        firstIndex: lines.length,
      ),
    );
    await for (final batch in batches) {
      lines.addAll(batch);
      completed++;
      await store.savePartial(
        key,
        model,
        PartialTranscript(completedChunks: completed, lines: lines),
      );
      yield ScriptProgress(
        stage: ScriptStage.transcribing,
        fraction:
            _languageStage + (1 - _languageStage) * completed / chunks.length,
        transcript: Transcript(languageCode: requested, lines: [...lines]),
        step: _transcribed(video, completed: completed, of: chunks.length),
      );
    }
    yield await _finishWithWhisper(store, key, lines);
  }

  Stream<ScriptProgress> _ensureModel(String languageCode) async* {
    if (await services.models.isDownloaded(model)) {
      return;
    }
    await for (final amount in services.models.download(model)) {
      yield ScriptProgress(
        stage: ScriptStage.downloadingModel,
        fraction: amount.fraction * _modelShare,
        transcript: _empty(languageCode),
        step: amount,
      );
    }
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
      fraction: _modelShare,
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
            _modelShare + (_audioDownloadEnd - _modelShare) * amount.fraction,
        transcript: _empty(languageCode),
        step: amount,
      );
    }
    audio.file = await download;
  }

  Future<List<File>> _chunksOf(File audio) async {
    final wav = await services.audio.toWav(audio);
    return services.audio.splitIntoChunks(wav);
  }

  Future<PartialTranscript> _partial(
    TranscriptStore store,
    TranscriptKey key,
  ) async {
    try {
      return await store.loadPartial(key, model);
    } on NoSavedTranscriptException {
      return const PartialTranscript(completedChunks: 0, lines: []);
    }
  }

  Future<ScriptProgress> _finishWithWhisper(
    TranscriptStore store,
    TranscriptKey key,
    List<TranscriptLine> lines,
  ) async {
    if (lines.isEmpty) {
      await store.clearPartial(key, model);
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
        source: whisperSource(model),
        savedAt: store.clock(),
      ),
    );
    await store.clearPartial(key, model);
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

/// Audio transcribed after [completed] of [of] chunks, out of the video's
/// length; the last chunk is usually shorter than the others.
WorkAmount _transcribed(
  SourceVideo video, {
  required int completed,
  required int of,
}) {
  final total = video.duration.inMilliseconds;
  final done = completed == of
      ? total
      : math.min(total, completed * _chunkLength.inMilliseconds);
  return WorkAmount(done: done, total: total, unit: WorkUnit.audioMilliseconds);
}

Transcript _empty(String languageCode) =>
    Transcript(languageCode: languageCode, lines: const []);

/// The model chosen in Settings (spec FR-12), small until it has loaded.
/// Home watches the setting, so it has loaded before a script starts.
final whisperModelProvider = Provider<SpeechModel>(
  (ref) => ref.watch(whisperModelSettingProvider).value ?? SpeechModel.small,
);

final realScriptPipelineProvider = Provider<ScriptPipeline>(
  (ref) => RealScriptPipeline(
    ScriptPipelineServices(
      models: ref.watch(modelManagerProvider),
      videos: ref.watch(videoSourceProvider),
      audio: ref.watch(audioPreparerProvider),
      whisper: ref.watch(whisperTranscriberProvider),
      store: ref.watch(transcriptStoreProvider.future),
    ),
    model: ref.watch(whisperModelProvider),
  ),
);
