import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';
import 'package:status_studio/src/core/work_amount.dart';
import 'package:status_studio/src/features/source/data/fake_video_source.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/application/real_script_pipeline.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';
import 'package:status_studio/src/features/transcript/data/audio_preparer.dart';
import 'package:status_studio/src/features/transcript/data/groq_client.dart';
import 'package:status_studio/src/features/transcript/data/groq_transcriber.dart';
import 'package:status_studio/src/features/transcript/data/model_manager.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';
import 'package:status_studio/src/features/transcript/data/whisper_transcriber.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';
import 'package:status_studio/src/features/transcript/domain/speech_model.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';

import '../../../../helpers/fake_whisper.dart';
import '../../../../helpers/fixtures.dart';

final savedAt = DateTime.utc(2026, 10, 30, 12);

const captions = Transcript(
  languageCode: 'en',
  lines: [
    TranscriptLine(
      index: 0,
      text: 'from captions',
      start: Duration.zero,
      end: Duration(seconds: 2),
    ),
  ],
);

/// Captions when [hasCaptions]; counts script audio downloads.
class ScriptVideoSource extends FakeVideoSource {
  ScriptVideoSource({
    this.hasCaptions = false,
    this.captionFailure = const NoCaptionTrackException(),
  });

  final bool hasCaptions;

  /// Thrown by [fetchCaptions] when there are no captions.
  final Exception captionFailure;
  var audioDownloads = 0;

  @override
  Future<Transcript> fetchCaptions(
    SourceVideo video,
    ScriptLanguage language,
  ) async {
    if (hasCaptions) {
      return captions;
    }
    throw captionFailure;
  }

  @override
  Future<File> downloadScriptAudio(
    SourceVideo video, {
    required void Function(WorkAmount amount) onProgress,
  }) async {
    audioDownloads++;
    return super.downloadScriptAudio(video, onProgress: onProgress);
  }
}

/// Says the model is there unless [missing]; downloading it reports halfway
/// then done.
class FakeModelManager extends ModelManager {
  FakeModelManager({this.missing = false})
    : super(
        pathFor: (_) async => '',
        uriFor: (_) => Uri(),
        httpClient: HttpClient(),
      );

  bool missing;

  @override
  Future<bool> isDownloaded(SpeechModel model) async => !missing;

  static const modelBytes = 1000;

  @override
  Stream<WorkAmount> download(SpeechModel model) async* {
    yield const WorkAmount(
      done: modelBytes ~/ 2,
      total: modelBytes,
      unit: WorkUnit.bytes,
    );
    missing = false;
    yield const WorkAmount(
      done: modelBytes,
      total: modelBytes,
      unit: WorkUnit.bytes,
    );
  }
}

/// Splits any audio into [chunkCount] named pieces without FFmpeg.
class FakeAudioPreparer extends AudioPreparer {
  FakeAudioPreparer({this.chunkCount = 3}) : super(const FfmpegRunner());

  final int chunkCount;

  @override
  Future<File> toWav(File audio) async => File('audio.wav');

  @override
  Future<List<File>> splitIntoChunks(File wav, {int chunkSeconds = 90}) async =>
      [for (var i = 0; i < chunkCount; i++) File('chunk_00$i.wav')];

  @override
  Future<List<File>> splitAudioCopy(
    File audio, {
    int chunkSeconds = 90,
  }) async => [for (var i = 0; i < chunkCount; i++) File('chunk_00$i.m4a')];
}

/// Answers every piece with one spoken line.
class FakeGroqClient extends GroqClient {
  FakeGroqClient() : super(apiKey: 'gsk_fake');

  final pieces = <String>[];

  @override
  Future<List<GroqSegment>> transcribe(
    File piece, {
    required String? languageCode,
  }) async {
    pieces.add(piece.path);
    return const [
      GroqSegment(
        from: Duration(seconds: 1),
        to: Duration(seconds: 2),
        text: 'hello',
        noSpeechProbability: 0.1,
      ),
    ];
  }
}

void main() {
  late Directory root;
  late TranscriptStore store;
  late ScriptVideoSource videos;
  late FakeModelManager models;
  late FakeWhisperController whisper;
  FakeGroqClient? groqClient;

  final key = TranscriptKey(
    videoId: sampleVideo.videoId,
    language: ScriptLanguage.auto,
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('script_pipeline_test');
    store = TranscriptStore(root, clock: () => savedAt);
    videos = ScriptVideoSource();
    models = FakeModelManager();
    whisper = FakeWhisperController(text: 'یہ اچھی بات ہے');
  });

  tearDown(() => root.delete(recursive: true));

  RealScriptPipeline pipeline({int chunkCount = 3}) => RealScriptPipeline(
    ScriptPipelineServices(
      models: models,
      videos: videos,
      audio: FakeAudioPreparer(chunkCount: chunkCount),
      whisper: WhisperTranscriber(whisper),
      store: Future.value(store),
      groq: () async {
        final client = groqClient;
        return client == null ? null : GroqTranscriber(client);
      },
    ),
    model: SpeechModel.small,
  );

  Future<List<ScriptProgress>> run({int chunkCount = 3}) =>
      pipeline(chunkCount: chunkCount)
          .run(sampleVideo, ScriptLanguage.auto)
          .toList();

  List<WorkAmount?> stepsOf(List<ScriptProgress> events, ScriptStage stage) => [
    for (final event in events)
      if (event.stage == stage) event.step,
  ];

  test('model_download_reports_its_bytes', () async {
    models.missing = true;

    final events = await run();

    expect(
      stepsOf(events, ScriptStage.downloadingModel).last,
      const WorkAmount(
        done: FakeModelManager.modelBytes,
        total: FakeModelManager.modelBytes,
        unit: WorkUnit.bytes,
      ),
    );
  });

  test('audio_download_reports_its_bytes', () async {
    final events = await run();

    expect(
      stepsOf(events, ScriptStage.downloadingAudio).last,
      FakeVideoSource.scriptAudioAmount,
    );
  });

  test('transcribing_starts_at_zero_before_the_first_chunk', () async {
    final events = await run();

    expect(stepsOf(events, ScriptStage.transcribing).first!.done, 0);
  });

  test('transcribing_reports_progress_inside_a_chunk', () async {
    final events = await run();

    expect(
      stepsOf(events, ScriptStage.transcribing).map((step) => step!.done),
      contains(45000),
    );
  });

  test('transcribing_ends_at_the_video_length', () async {
    final events = await run();

    expect(
      stepsOf(events, ScriptStage.transcribing).last!.done,
      sampleVideo.duration.inMilliseconds,
    );
  });

  test('uses_captions_when_track_exists', () async {
    videos = ScriptVideoSource(hasCaptions: true);

    final events = await run();

    expect(
      (events.last.transcript, whisper.transcribedPaths.length),
      (captions, 0),
    );
  });

  test('captions_need_no_audio_download', () async {
    videos = ScriptVideoSource(hasCaptions: true);

    await run();

    expect(videos.audioDownloads, 0);
  });

  test('falls_back_to_whisper_without_captions', () async {
    final events = await run();

    expect(events.last.transcript.lines, hasLength(3));
  });

  test('caption_failure_falls_back_to_whisper', () async {
    videos = ScriptVideoSource(
      captionFailure: const OfflineException('captions timed out'),
    );

    final events = await run();

    expect(events.last.transcript.lines, hasLength(3));
  });

  test('downloads_model_first_when_missing', () async {
    models.missing = true;

    final events = await run();

    expect(events.first.stage, ScriptStage.downloadingModel);
  });

  test('emits_lines_progressively_per_chunk', () async {
    final events = await run();

    final lineCounts = events
        .where((event) => event.stage == ScriptStage.transcribing)
        .map((event) => event.transcript.lines.length)
        .toSet();
    expect(lineCounts, containsAll([1, 2, 3]));
  });

  test('auto_language_sets_inferred_code', () async {
    final events = await run();

    expect(events.last.transcript.languageCode, 'ur');
  });

  test('empty_transcript_throws_no_speech', () async {
    whisper = FakeWhisperController(text: '[BLANK_AUDIO]');

    await expectLater(run(), throwsA(isA<NoSpeechFoundException>()));
  });

  test('cancel_releases_model', () async {
    final firstLines = Completer<void>();
    final subscription = pipeline(chunkCount: 4)
        .run(sampleVideo, ScriptLanguage.auto)
        .listen((event) {
          if (event.transcript.lines.isNotEmpty && !firstLines.isCompleted) {
            firstLines.complete();
          }
        });
    await firstLines.future;

    await subscription.cancel();

    expect(whisper.releaseCount, 1);
  });

  test('saved_script_skips_download_and_transcription', () async {
    await store.save(
      key,
      SavedTranscript(
        transcript: captions,
        source: 'captions',
        savedAt: savedAt,
      ),
    );

    final events = await run();

    expect(
      (
        events.single.savedAt,
        videos.audioDownloads,
        whisper.transcribedPaths.length,
      ),
      (savedAt, 0, 0),
    );
  });

  test('write_again_ignores_saved_script_and_replaces_it', () async {
    await store.save(
      key,
      SavedTranscript(
        transcript: captions,
        source: 'captions',
        savedAt: DateTime.utc(2026),
      ),
    );

    await pipeline().writeAgain(sampleVideo, ScriptLanguage.auto).drain<void>();

    expect((await store.load(key)).source, 'whisper-small');
  });

  test('resumes_from_partial_progress', () async {
    await store.savePartial(
      key,
      whisperSource(SpeechModel.small),
      const PartialTranscript(
        completedChunks: 2,
        lines: [
          TranscriptLine(
            index: 0,
            text: 'یہ',
            start: Duration(seconds: 2),
            end: Duration(seconds: 4),
          ),
          TranscriptLine(
            index: 1,
            text: 'بات',
            start: Duration(seconds: 92),
            end: Duration(seconds: 94),
          ),
        ],
      ),
    );

    final events = await run(chunkCount: 4);

    expect(
      (
        whisper.transcribedPaths.join(','),
        events.last.transcript.lines.last.index,
      ),
      ('chunk_002.wav,chunk_003.wav', 3),
    );
  });

  test('finished_run_saves_script_and_clears_partial', () async {
    await run();

    expect((await store.load(key)).source, 'whisper-small');
    await expectLater(
      store.loadPartial(key, whisperSource(SpeechModel.small)),
      throwsA(isA<NoSavedTranscriptException>()),
    );
  });

  test('captions_run_keeps_the_video_for_the_recent_list', () async {
    videos = ScriptVideoSource(hasCaptions: true);

    await run();

    final listed = [for (final script in await store.list()) script.video];
    expect(listed, [sampleVideo]);
  });

  test('whisper_run_keeps_the_video_for_the_recent_list', () async {
    await run();

    final listed = [for (final script in await store.list()) script.video];
    expect(listed, [sampleVideo]);
  });

  test('write_again_keeps_the_video_for_the_recent_list', () async {
    await pipeline().writeAgain(sampleVideo, ScriptLanguage.auto).drain<void>();

    final listed = [for (final script in await store.list()) script.video];
    expect(listed, [sampleVideo]);
  });

  group('with_groq_on', () {
    setUp(() => groqClient = FakeGroqClient());

    test('groq_run_does_not_call_whisper', () async {
      await run();

      expect(whisper.transcribedPaths, isEmpty);
    });

    test('groq_run_skips_the_model_download', () async {
      models.missing = true;

      final events = await run();

      expect(stepsOf(events, ScriptStage.downloadingModel), isEmpty);
    });

    test('groq_run_saves_the_script_under_the_groq_source', () async {
      await run();

      expect((await store.load(key)).source, groqSource);
    });

    test('groq_run_does_not_reuse_whisper_partial_progress', () async {
      await store.savePartial(
        key,
        whisperSource(SpeechModel.small),
        const PartialTranscript(completedChunks: 2, lines: []),
      );

      await run();

      expect(groqClient!.pieces, hasLength(3));
    });
  });

  group('use_on_device', () {
    const groqLine = TranscriptLine(
      index: 0,
      text: 'from groq',
      start: Duration(seconds: 1),
      end: Duration(seconds: 2),
    );

    setUp(() async {
      groqClient = FakeGroqClient();
      await store.savePartial(
        key,
        groqSource,
        const PartialTranscript(completedChunks: 1, lines: [groqLine]),
      );
    });

    Future<void> continueOnDevice() => pipeline()
        .continueOnDevice(sampleVideo, ScriptLanguage.auto)
        .drain<void>();

    test('use_on_device_keeps_groqs_lines', () async {
      await continueOnDevice();

      final texts = (await store.load(key)).transcript.lines
          .map((line) => line.text);
      expect(texts.first, 'from groq');
    });

    test('use_on_device_continues_from_the_next_piece', () async {
      await continueOnDevice();

      expect(whisper.transcribedPaths, hasLength(2));
    });

    test('use_on_device_does_not_call_groq', () async {
      await continueOnDevice();

      expect(groqClient!.pieces, isEmpty);
    });

    test('use_on_device_saves_under_the_on_device_source', () async {
      await continueOnDevice();

      expect((await store.load(key)).source, whisperSource(SpeechModel.small));
    });

    test('use_on_device_numbers_new_lines_after_groqs', () async {
      await continueOnDevice();

      final indexes = (await store.load(key)).transcript.lines
          .map((line) => line.index);
      expect(indexes, [for (var i = 0; i < indexes.length; i++) i]);
    });

    test('use_on_device_clears_groqs_partial_progress', () async {
      await continueOnDevice();

      expect(
        store.loadPartial(key, groqSource),
        throwsA(isA<NoSavedTranscriptException>()),
      );
    });

    test('use_on_device_without_groq_lines_writes_from_the_start', () async {
      await store.clearPartial(key, groqSource);

      await continueOnDevice();

      expect(whisper.transcribedPaths, hasLength(3));
    });
  });
}
