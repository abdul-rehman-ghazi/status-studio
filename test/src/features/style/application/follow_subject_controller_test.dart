import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/source/application/clip_source_controller.dart';
import 'package:status_studio/src/features/source/data/clip_source_preparer.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/style/application/clip_frame_size_provider.dart';
import 'package:status_studio/src/features/style/application/follow_subject_controller.dart';
import 'package:status_studio/src/features/style/data/frame_extractor.dart';
import 'package:status_studio/src/features/style/data/subject_detector.dart';
import 'package:status_studio/src/features/style/domain/crop_path.dart';
import 'package:status_studio/src/features/style/domain/follow_errors.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';

import '../../../../helpers/fake_clip_preparer.dart';
import '../../../../helpers/fake_follow.dart';
import '../../../../helpers/fixtures.dart';
import '../../../../helpers/pump_app.dart';

void main() {
  late ProviderContainer container;
  late FakeFrameExtractor extractor;
  late FakeSubjectDetector detector;

  void arrange({FakeFrameExtractor? frames, FakeSubjectDetector? faces}) {
    extractor = frames ?? FakeFrameExtractor();
    detector = faces ?? FakeSubjectDetector(facesAt: (_) => [centredFace]);
    container = ProviderContainer.test(
      overrides: [
        draftOverride(pickedDraft.withMovingCropStarted()),
        clipSourcePreparerProvider.overrideWithValue(FakeClipSourcePreparer()),
        sourceCacheProvider.overrideWith(
          (ref) async => SourceCache(Directory.systemTemp),
        ),
        clipFrameSizeProvider.overrideWith(
          (ref, source) async => const OutputSize(1920, 1080),
        ),
        frameExtractorProvider.overrideWithValue(extractor),
        subjectDetectorProvider.overrideWithValue(() => detector),
      ],
    );
    container
      ..listen(followSubjectProvider, (_, _) {})
      // Fine-tune watches the clip source while it is open; so does this.
      ..listen(clipSourceProvider(pickedDraft.video!.videoId), (_, _) {});
  }

  CropPath pathNow() => container.read(reelDraftProvider).frame.cropPath;
  FollowState stateNow() => container.read(followSubjectProvider);

  /// Downloads the clip (a fake does it at once), as Fine-tune has by the
  /// time the button shows.
  Future<void> downloadClip() => container
      .read(clipSourceProvider(pickedDraft.video!.videoId).notifier)
      .prepareFor(pickedDraft.video!, pickedDraft.clip!);

  Future<void> start() async {
    await downloadClip();
    await container.read(followSubjectProvider.notifier).start();
  }

  test('a_run_ends_done_with_the_keyframe_count', () async {
    arrange();

    await start();

    expect(stateNow(), isA<FollowDone>());
  });

  test('a_run_writes_the_followed_path_into_the_draft', () async {
    arrange();
    final before = pathNow();

    await start();

    // A steady face at the centre: one keyframe, at the clip start, but the
    // path is the run's, not the starting one.
    expect(pathNow().keyframes.single.time, pickedDraft.clip!.start);
    expect(identical(pathNow(), before), isFalse);
  });

  test('progress_runs_from_sampling_to_the_end', () async {
    arrange();
    final fractions = <double>[];
    container.listen(followSubjectProvider, (_, next) {
      if (next is FollowRunning) {
        fractions.add(next.fraction);
      }
    });

    await start();

    expect(fractions.first, 0);
    expect(fractions, contains(0.25));
    expect(fractions.last, closeTo(1, 1e-9));
  });

  test('the_frames_are_deleted_after_a_run', () async {
    arrange();

    await start();

    expect(extractor.made!.existsSync(), isFalse);
  });

  test('no_person_says_so_and_leaves_the_path_alone', () async {
    arrange(faces: FakeSubjectDetector());
    final before = pathNow();

    await start();

    expect(stateNow(), isA<FollowNoSubject>());
    expect(pathNow(), before);
  });

  test('an_extractor_failure_ends_failed', () async {
    arrange(
      frames: FakeFrameExtractor(failure: const FollowFailedException('x')),
    );

    await start();

    expect(stateNow(), isA<FollowFailed>());
  });

  test('a_detector_failure_ends_failed_and_deletes_the_frames', () async {
    arrange(faces: FakeSubjectDetector(failure: Exception('model')));

    await start();

    expect(stateNow(), isA<FollowFailed>());
    expect(extractor.made!.existsSync(), isFalse);
  });

  group('stopping a run', () {
    /// Starts a run held at its first look; the function waits for it to end.
    Future<Future<void> Function()> startAndHoldAtFirstFrame() async {
      detector.gate = Completer<void>();
      await downloadClip();
      final run = container.read(followSubjectProvider.notifier).start();
      // Let the run reach the detector.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return () => run;
    }

    test('cancel_changes_nothing_and_shows_nothing', () async {
      arrange();
      final before = pathNow();
      final finish = await startAndHoldAtFirstFrame();

      container.read(followSubjectProvider.notifier).cancel();
      detector.gate!.complete();
      await finish();

      expect(stateNow(), isA<FollowIdle>());
      expect(pathNow(), before);
    });

    test('cancel_stops_ffmpeg_and_deletes_the_frames', () async {
      arrange();
      final finish = await startAndHoldAtFirstFrame();

      container.read(followSubjectProvider.notifier).cancel();
      detector.gate!.complete();
      await finish();

      expect(extractor.handle!.isCancelled, isTrue);
      expect(extractor.made!.existsSync(), isFalse);
    });

    test('cancel_stops_looking_at_frames', () async {
      arrange();
      final finish = await startAndHoldAtFirstFrame();

      container.read(followSubjectProvider.notifier).cancel();
      detector.gate!.complete();
      await finish();

      expect(detector.calls, 1);
    });

    test('a_new_clip_cancels_the_run', () async {
      arrange();
      final before = pathNow();
      final finish = await startAndHoldAtFirstFrame();

      container
          .read(reelDraftProvider.notifier)
          .nudgeClipEnd(ClipRange.nudgeStep);
      detector.gate!.complete();
      await finish();

      expect(stateNow(), isA<FollowIdle>());
      expect(pathNow(), before);
    });

    test('a_new_size_cancels_the_run', () async {
      arrange();
      final finish = await startAndHoldAtFirstFrame();

      container
          .read(reelDraftProvider.notifier)
          .updateFrame(
            container
                .read(reelDraftProvider)
                .frame
                .copyWith(preset: AspectPreset.portrait4x5),
          );
      detector.gate!.complete();
      await finish();

      expect(stateNow(), isA<FollowIdle>());
    });

    test('a_hand_edit_during_the_run_wins_over_its_result', () async {
      arrange();
      final finish = await startAndHoldAtFirstFrame();

      container
          .read(reelDraftProvider.notifier)
          .moveCropTo(pickedDraft.clip!.start, const CropAnchor(x: 0, y: 0.5));
      final edited = pathNow();
      detector.gate!.complete();
      await finish();

      expect(pathNow(), edited);
      expect(stateNow(), isA<FollowIdle>());
    });

    test('turning_the_move_off_cancels_the_run', () async {
      arrange();
      final finish = await startAndHoldAtFirstFrame();

      container.read(reelDraftProvider.notifier).stopMovingCrop();
      detector.gate!.complete();
      await finish();

      expect(stateNow(), isA<FollowIdle>());
      expect(pathNow().isEmpty, isTrue);
    });
  });

  group('the detector', () {
    test('is_closed_when_a_run_ends', () async {
      arrange();

      await start();

      expect(detector.closed, isTrue);
    });

    test('is_closed_when_a_run_is_cancelled', () async {
      arrange();
      detector.gate = Completer<void>();
      await downloadClip();
      final run = container.read(followSubjectProvider.notifier).start();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      container.read(followSubjectProvider.notifier).cancel();
      detector.gate!.complete();
      await run;

      expect(detector.closed, isTrue);
    });

    test('is_closed_when_it_fails', () async {
      arrange(faces: FakeSubjectDetector(failure: Exception('model')));

      await start();

      expect(detector.closed, isTrue);
    });
  });

  test('reset_clears_how_a_run_ended', () async {
    arrange(faces: FakeSubjectDetector());
    await start();

    container.read(followSubjectProvider.notifier).reset();

    expect(stateNow(), isA<FollowIdle>());
  });
}
