import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/clip/domain/clip_window.dart';
import 'package:status_studio/src/features/source/domain/clip_source.dart';
import 'package:status_studio/src/features/style/data/frame_extractor.dart';
import 'package:status_studio/src/features/style/domain/follow_errors.dart';

/// Writes what FFmpeg would: [frameCount] JPEGs and, unless [cutsText] is
/// null, the scene-cut file.
class FakeFrameRunner implements CancellableFfmpegRunner {
  FakeFrameRunner({this.frameCount = 3, this.cutsText = '', this.failure});

  final int frameCount;
  final String? cutsText;
  final Exception? failure;
  final runs = <List<String>>[];

  @override
  Future<void> run(List<String> arguments, FfmpegCancelHandle handle) async {
    runs.add(arguments);
    if (failure case final failure?) {
      throw failure;
    }
    final directory = File(arguments.last).parent.path;
    for (var frame = 0; frame < frameCount; frame++) {
      final name = 'frame${frame.toString().padLeft(4, '0')}.jpg';
      await File('$directory/$name').writeAsBytes(const [1]);
    }
    if (cutsText case final text?) {
      await File('$directory/cuts.txt').writeAsString(text);
    }
  }
}

final source = ClipSource(
  file: File('/cache/clip.mp4'),
  offset: const Duration(seconds: 15),
  window: const ClipWindow(
    start: Duration(seconds: 15),
    end: Duration(seconds: 55),
  ),
);

const clip = ClipRange(
  start: Duration(seconds: 20),
  end: Duration(seconds: 50),
);

void main() {
  late Directory work;

  setUp(() => work = Directory.systemTemp.createTempSync('frames_test'));
  tearDown(() {
    if (work.existsSync()) {
      work.deleteSync(recursive: true);
    }
  });

  FfmpegFrameExtractor extractorWith(FakeFrameRunner runner) =>
      FfmpegFrameExtractor(runner: runner, makeDirectory: () => work);

  test('asks_ffmpeg_for_the_clip_in_the_files_own_time', () async {
    final runner = FakeFrameRunner();

    await extractorWith(runner).extract(source, clip, FfmpegCancelHandle());

    // 20 s − 15 s offset and 50 s − 15 s offset.
    expect(runner.runs.single.sublist(1, 5), ['-ss', '5.000', '-to', '35.000']);
  });

  test('returns_the_frames_in_order', () async {
    final frames = await extractorWith(FakeFrameRunner(frameCount: 12))
        .extract(source, clip, FfmpegCancelHandle());

    expect(frames.frames.map((file) => file.uri.pathSegments.last).toList(), [
      for (var i = 0; i < 12; i++) 'frame${i.toString().padLeft(4, '0')}.jpg',
    ]);
  });

  test('reports_the_sampling_rate', () async {
    final frames = await extractorWith(FakeFrameRunner())
        .extract(source, clip, FfmpegCancelHandle());

    expect(frames.framesPerSecond, 4);
  });

  test('scene_cuts_are_moved_into_video_time', () async {
    final frames = await extractorWith(
      FakeFrameRunner(cutsText: 'lavfi.scd.time=3.5\n'),
    ).extract(source, clip, FfmpegCancelHandle());

    expect(frames.sceneCuts, [const Duration(milliseconds: 23500)]);
  });

  test('a_cuts_file_with_no_cuts_means_there_are_none', () async {
    final frames = await extractorWith(FakeFrameRunner(cutsText: ''))
        .extract(source, clip, FfmpegCancelHandle());

    expect(frames.sceneCuts, isEmpty);
  });

  test('no_cuts_file_means_the_cuts_are_not_known', () async {
    final frames = await extractorWith(FakeFrameRunner(cutsText: null))
        .extract(source, clip, FfmpegCancelHandle());

    expect(frames.sceneCuts, isNull);
  });

  test('delete_removes_the_frames', () async {
    final frames = await extractorWith(FakeFrameRunner())
        .extract(source, clip, FfmpegCancelHandle());

    await frames.delete();

    expect(work.existsSync(), isFalse);
  });

  test('a_failed_run_is_a_follow_failure_and_cleans_up', () async {
    final extractor = extractorWith(
      FakeFrameRunner(failure: const FfmpegFailedException('boom')),
    );

    await expectLater(
      extractor.extract(source, clip, FfmpegCancelHandle()),
      throwsA(isA<FollowFailedException>()),
    );
    expect(work.existsSync(), isFalse);
  });

  test('a_run_that_makes_no_frames_is_a_follow_failure', () async {
    final extractor = extractorWith(FakeFrameRunner(frameCount: 0));

    await expectLater(
      extractor.extract(source, clip, FfmpegCancelHandle()),
      throwsA(isA<FollowFailedException>()),
    );
    expect(work.existsSync(), isFalse);
  });
}
