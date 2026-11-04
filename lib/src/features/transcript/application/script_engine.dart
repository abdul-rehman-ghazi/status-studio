import 'dart:io';

import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';
import 'package:status_studio/src/features/transcript/data/audio_preparer.dart';
import 'package:status_studio/src/features/transcript/data/groq_transcriber.dart';
import 'package:status_studio/src/features/transcript/data/model_manager.dart';
import 'package:status_studio/src/features/transcript/data/whisper_transcriber.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';
import 'package:status_studio/src/features/transcript/domain/speech_model.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

/// Overall progress once the speech model is ready (plan M3 Task 7).
const modelDownloadShare = 0.15;

/// The pieces of a video's audio still to write, as one run.
class PieceRun {
  const PieceRun({
    required this.pieces,
    required this.language,
    required this.completedPieces,
    required this.firstIndex,
  });

  final List<File> pieces;
  final ScriptLanguage language;
  final int completedPieces;
  final int firstIndex;
}

/// What turns audio into lines: Whisper on the phone, or Groq (FR-12a).
/// The pipeline picks one per run.
abstract interface class ScriptEngine {
  /// The saved script's source name (FR-14).
  String get source;

  /// Anything the engine needs before audio: Whisper's model download.
  Stream<ScriptProgress> prepare(String languageCode);

  /// The audio cut into the pieces [write] takes.
  Future<List<File>> piecesOf(File audio);

  Stream<ChunkEvent> write(PieceRun run);
}

class WhisperEngine implements ScriptEngine {
  WhisperEngine({
    required this.models,
    required this.audio,
    required this.whisper,
    required this.model,
  });

  final ModelManager models;
  final AudioPreparer audio;
  final WhisperTranscriber whisper;
  final SpeechModel model;

  @override
  String get source => whisperSource(model);

  @override
  Stream<ScriptProgress> prepare(String languageCode) async* {
    if (await models.isDownloaded(model)) {
      return;
    }
    await for (final amount in models.download(model)) {
      yield ScriptProgress(
        stage: ScriptStage.downloadingModel,
        fraction: amount.fraction * modelDownloadShare,
        transcript: Transcript(languageCode: languageCode, lines: const []),
        step: amount,
      );
    }
  }

  @override
  Future<List<File>> piecesOf(File source) async =>
      audio.splitIntoChunks(await audio.toWav(source));

  @override
  Stream<ChunkEvent> write(PieceRun run) => whisper.transcribeChunks(
    ChunkTranscription(
      chunks: run.pieces,
      language: run.language,
      model: model,
      completedChunks: run.completedPieces,
      firstIndex: run.firstIndex,
    ),
  );
}

class GroqEngine implements ScriptEngine {
  GroqEngine({required this.audio, required this.groq});

  final AudioPreparer audio;
  final GroqTranscriber groq;

  @override
  String get source => groqSource;

  @override
  Stream<ScriptProgress> prepare(String languageCode) => const Stream.empty();

  @override
  Future<List<File>> piecesOf(File source) => audio.splitAudioCopy(source);

  @override
  Stream<ChunkEvent> write(PieceRun run) => groq.transcribePieces(
    GroqTranscription(
      pieces: run.pieces,
      language: run.language,
      completedPieces: run.completedPieces,
      firstIndex: run.firstIndex,
    ),
  );
}
