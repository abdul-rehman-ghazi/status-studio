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
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';

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

/// Splits any audio into [pieceCount] named pieces without FFmpeg.
class FakeAudioPreparer extends AudioPreparer {
  FakeAudioPreparer({this.pieceCount = 3}) : super(const FfmpegRunner());

  final int pieceCount;

  @override
  Future<List<File>> splitAudioCopy(
    File audio, {
    int chunkSeconds = 90,
  }) async => [for (var i = 0; i < pieceCount; i++) File('piece_00$i.m4a')];
}

/// Answers every piece with one line of [text], or none when it is empty.
class FakeGroqClient extends GroqClient {
  FakeGroqClient({this.text = 'یہ اچھی بات ہے'}) : super(apiKey: 'gsk_fake');

  final String text;
  final pieces = <String>[];

  @override
  Future<List<GroqSegment>> transcribe(
    File piece, {
    required String? languageCode,
  }) async {
    pieces.add(piece.path);
    if (text.isEmpty) {
      return const [];
    }
    return [
      GroqSegment(
        from: const Duration(seconds: 1),
        to: const Duration(seconds: 2),
        text: text,
        noSpeechProbability: 0.1,
      ),
    ];
  }
}

void main() {
  late Directory root;
  late TranscriptStore store;
  late ScriptVideoSource videos;
  late FakeGroqClient groqClient;
  var hasKey = true;

  final key = TranscriptKey(
    videoId: sampleVideo.videoId,
    language: ScriptLanguage.auto,
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('script_pipeline_test');
    store = TranscriptStore(root, clock: () => savedAt);
    videos = ScriptVideoSource();
    groqClient = FakeGroqClient();
    hasKey = true;
  });

  tearDown(() => root.delete(recursive: true));

  RealScriptPipeline pipeline({int pieceCount = 3}) => RealScriptPipeline(
    ScriptPipelineServices(
      videos: videos,
      audio: FakeAudioPreparer(pieceCount: pieceCount),
      store: Future.value(store),
      groq: () async {
        if (!hasKey) {
          throw const NoGroqKeyException();
        }
        return GroqTranscriber(groqClient);
      },
    ),
  );

  Future<List<ScriptProgress>> run({int pieceCount = 3}) =>
      pipeline(pieceCount: pieceCount)
          .run(sampleVideo, ScriptLanguage.auto)
          .toList();

  List<WorkAmount?> stepsOf(List<ScriptProgress> events, ScriptStage stage) => [
    for (final event in events)
      if (event.stage == stage) event.step,
  ];

  test('audio_download_reports_its_bytes', () async {
    final events = await run();

    expect(
      stepsOf(events, ScriptStage.downloadingAudio).last,
      FakeVideoSource.scriptAudioAmount,
    );
  });

  test('transcribing_starts_at_zero_before_the_first_piece', () async {
    final events = await run();

    expect(stepsOf(events, ScriptStage.transcribing).first!.done, 0);
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

    expect((events.last.transcript, groqClient.pieces.length), (captions, 0));
  });

  test('captions_need_no_audio_download', () async {
    videos = ScriptVideoSource(hasCaptions: true);

    await run();

    expect(videos.audioDownloads, 0);
  });

  test('captions_need_no_groq_key', () async {
    hasKey = false;
    videos = ScriptVideoSource(hasCaptions: true);

    final events = await run();

    expect(events.last.transcript, captions);
  });

  test('writes_with_groq_without_captions', () async {
    final events = await run();

    expect(events.last.transcript.lines, hasLength(3));
  });

  test('caption_failure_falls_back_to_groq', () async {
    videos = ScriptVideoSource(
      captionFailure: const OfflineException('captions timed out'),
    );

    final events = await run();

    expect(events.last.transcript.lines, hasLength(3));
  });

  test('without_a_key_it_stops_before_downloading_audio', () async {
    hasKey = false;

    await expectLater(run(), throwsA(isA<NoGroqKeyException>()));
    expect(videos.audioDownloads, 0);
  });

  test('emits_lines_progressively_per_piece', () async {
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
    groqClient = FakeGroqClient(text: '');

    await expectLater(run(), throwsA(isA<NoSpeechFoundException>()));
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
      (events.single.savedAt, videos.audioDownloads, groqClient.pieces.length),
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

    expect((await store.load(key)).source, groqSource);
  });

  test('resumes_from_partial_progress', () async {
    await store.savePartial(
      key,
      groqSource,
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

    final events = await run(pieceCount: 4);

    expect(
      (groqClient.pieces.join(','), events.last.transcript.lines.last.index),
      ('piece_002.m4a,piece_003.m4a', 3),
    );
  });

  test('finished_run_saves_script_and_clears_partial', () async {
    await run();

    expect((await store.load(key)).source, groqSource);
    await expectLater(
      store.loadPartial(key, groqSource),
      throwsA(isA<NoSavedTranscriptException>()),
    );
  });

  test('captions_run_keeps_the_video_for_the_recent_list', () async {
    videos = ScriptVideoSource(hasCaptions: true);

    await run();

    final listed = [for (final script in await store.list()) script.video];
    expect(listed, [sampleVideo]);
  });

  test('groq_run_keeps_the_video_for_the_recent_list', () async {
    await run();

    final listed = [for (final script in await store.list()) script.video];
    expect(listed, [sampleVideo]);
  });

  test('write_again_keeps_the_video_for_the_recent_list', () async {
    await pipeline().writeAgain(sampleVideo, ScriptLanguage.auto).drain<void>();

    final listed = [for (final script in await store.list()) script.video];
    expect(listed, [sampleVideo]);
  });
}
