import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';
import 'package:status_studio/src/core/ffmpeg/frame_arguments.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/source/application/clip_source_controller.dart';
import 'package:status_studio/src/features/style/application/clip_frame_size_provider.dart';
import 'package:status_studio/src/features/style/data/frame_extractor.dart';
import 'package:status_studio/src/features/style/data/subject_detector.dart';
import 'package:status_studio/src/features/style/domain/follow_errors.dart';
import 'package:status_studio/src/features/style/domain/subject_box.dart';
import 'package:status_studio/src/features/style/domain/subject_path.dart';

/// Where a run of Follow the person is (spec FR-23).
@immutable
sealed class FollowState {
  const FollowState();
}

class FollowIdle extends FollowState {
  const FollowIdle();
}

class FollowRunning extends FollowState {
  const FollowRunning(this.fraction);

  /// From 0 to 1 over sampling the frames and looking at them.
  final double fraction;
}

class FollowDone extends FollowState {
  const FollowDone(this.keyframeCount);

  final int keyframeCount;
}

class FollowNoSubject extends FollowState {
  const FollowNoSubject();
}

class FollowFailed extends FollowState {
  const FollowFailed();
}

/// Sampling the frames takes this share of the progress; the rest is looking
/// at them.
const _samplingShare = 0.25;

final followSubjectProvider =
    NotifierProvider.autoDispose<FollowSubjectController, FollowState>(
      FollowSubjectController.new,
    );

/// Finds the person in the clip and writes the crop's keyframes (spec
/// FR-23). Everything stays on the phone.
class FollowSubjectController extends Notifier<FollowState> {
  /// Bumped by every start and cancel, so a run that was stopped notices
  /// between frames and ends without touching anything.
  var _generation = 0;
  FfmpegCancelHandle? _cancelFfmpeg;

  @override
  FollowState build() {
    ref.onDispose(_stop);
    // A new clip, size or fill makes the run's frames the wrong picture.
    ref.listen(reelDraftProvider.select(_whatTheRunDependsOn), (before, after) {
      if (before != after) {
        cancel();
      }
    });
    return const FollowIdle();
  }

  Future<void> start() async {
    final draft = ref.read(reelDraftProvider);
    final clip = draft.clip;
    final video = draft.video;
    if (clip == null || video == null) {
      throw StateError('Follow the person started without a clip.');
    }
    final source = ref.read(clipSourceProvider(video.videoId)).value;
    if (source == null) {
      throw StateError('Follow the person started before the clip downloaded.');
    }
    final generation = ++_generation;
    final cancelFfmpeg = _cancelFfmpeg = FfmpegCancelHandle();
    state = const FollowRunning(0);
    SampledFrames? frames;
    try {
      final sourceSize = await ref.read(clipFrameSizeProvider(source).future);
      frames = await ref
          .read(frameExtractorProvider)
          .extract(source, clip, cancelFfmpeg);
      if (_isStale(generation)) {
        return;
      }
      state = const FollowRunning(_samplingShare);
      final samples = await _lookAtFrames(frames, clip.start, generation);
      if (_isStale(generation)) {
        return;
      }
      final path = followSubject(
        SubjectTrack(samples: samples, sceneCuts: frames.sceneCuts),
        FollowGeometry.forFrame(
          frame: draft.frame,
          sourceSize: sourceSize,
          clip: clip,
        ),
      );
      ref.read(reelDraftProvider.notifier).followCrop(path);
      state = FollowDone(path.keyframes.length);
    } on NoSubjectFoundException {
      if (!_isStale(generation)) {
        state = const FollowNoSubject();
      }
    } on Object {
      if (!_isStale(generation)) {
        state = const FollowFailed();
      }
    } finally {
      await frames?.delete();
    }
  }

  /// Stops the run: nothing is changed and the frames are deleted.
  void cancel() {
    final wasRunning = state is FollowRunning;
    _stop();
    if (wasRunning) {
      state = const FollowIdle();
    }
  }

  /// Back to nothing shown, once the user has seen how a run ended.
  void reset() {
    if (state is! FollowRunning) {
      state = const FollowIdle();
    }
  }

  void _stop() {
    _generation++;
    final cancelFfmpeg = _cancelFfmpeg;
    _cancelFfmpeg = null;
    if (cancelFfmpeg != null) {
      unawaited(cancelFfmpeg.cancel());
    }
  }

  bool _isStale(int generation) => generation != _generation;

  Future<List<SubjectSample>> _lookAtFrames(
    SampledFrames frames,
    Duration clipStart,
    int generation,
  ) async {
    final detector = ref.read(subjectDetectorProvider);
    final samples = <SubjectSample>[];
    for (final (index, frame) in frames.frames.indexed) {
      if (_isStale(generation)) {
        return samples;
      }
      final faces = await detector.facesIn(frame);
      if (_isStale(generation)) {
        return samples;
      }
      samples.add(
        SubjectSample(
          time: frameTime(
            clipStart: clipStart,
            index: index,
            framesPerSecond: frames.framesPerSecond,
          ),
          faces: faces,
        ),
      );
      state = FollowRunning(
        _samplingShare +
            (1 - _samplingShare) * (index + 1) / frames.frames.length,
      );
    }
    return samples;
  }
}

Object _whatTheRunDependsOn(ReelDraft draft) => (
  draft.clip,
  draft.frame.preset,
  draft.frame.fill,
  draft.frame.freeCrop.width,
  draft.frame.freeCrop.height,
);
