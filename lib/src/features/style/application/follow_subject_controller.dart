import 'dart:async';
import 'dart:io';

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
import 'package:status_studio/src/features/style/domain/crop_path.dart';
import 'package:status_studio/src/features/style/domain/follow_errors.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/features/style/domain/person_choice.dart';
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

/// Two or more people are on screen at once and the user is asked whom to
/// follow (spec FR-25).
class FollowChoosing extends FollowState {
  const FollowChoosing({
    required this.picture,
    required this.pictureSize,
    required this.choices,
  });

  /// The sampled frame the choices are faces in.
  final File picture;

  /// The video's size; the picture keeps its aspect ratio.
  final OutputSize pictureSize;

  /// All in [picture], left to right.
  final List<PersonChoice> choices;
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

/// What a question about whom to follow needs once the user has answered.
class _PendingChoice {
  const _PendingChoice({
    required this.frames,
    required this.track,
    required this.geometry,
    required this.pathAtStart,
  });

  final SampledFrames frames;
  final SubjectTrack track;
  final FollowGeometry geometry;
  final CropPath pathAtStart;
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

  /// The frames kept on disk while the user chooses; deleted by whatever ends
  /// the question.
  _PendingChoice? _pending;

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
    _releasePending();
    final pathAtStart = draft.frame.cropPath;
    final generation = ++_generation;
    final cancelFfmpeg = _cancelFfmpeg = FfmpegCancelHandle();
    state = const FollowRunning(0);
    SampledFrames? frames;
    var keptForTheChoice = false;
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
      final track = SubjectTrack(samples: samples, sceneCuts: frames.sceneCuts);
      final geometry = FollowGeometry.forFrame(
        frame: draft.frame,
        sourceSize: sourceSize,
        clip: clip,
      );
      final choices = choosablePeople(track, geometry);
      if (choices.length < 2) {
        _apply(followSubject(track, geometry), pathAtStart);
        return;
      }
      if (_handEdited(pathAtStart)) {
        state = const FollowIdle();
        return;
      }
      _pending = _PendingChoice(
        frames: frames,
        track: track,
        geometry: geometry,
        pathAtStart: pathAtStart,
      );
      keptForTheChoice = true;
      state = FollowChoosing(
        picture: frames.frames[choices.first.sampleIndex],
        pictureSize: sourceSize,
        choices: choices,
      );
    } on NoSubjectFoundException {
      if (!_isStale(generation)) {
        state = const FollowNoSubject();
      }
    } on Object {
      if (!_isStale(generation)) {
        state = const FollowFailed();
      }
    } finally {
      if (!keptForTheChoice) {
        await frames?.delete();
      }
    }
  }

  /// The user chose [choice] in the question: follow that person (spec FR-25).
  void choose(PersonChoice choice) {
    _answer((pending) => followPerson(pending.track, pending.geometry, choice));
  }

  /// The user left it to the app: follow the automatic pick (spec FR-23).
  void chooseForMe() {
    _answer((pending) => followSubject(pending.track, pending.geometry));
  }

  void _answer(CropPath Function(_PendingChoice pending) pathFor) {
    final pending = _pending;
    if (pending == null || state is! FollowChoosing) {
      return;
    }
    _pending = null;
    unawaited(pending.frames.delete());
    try {
      _apply(pathFor(pending), pending.pathAtStart);
    } on NoSubjectFoundException {
      state = const FollowNoSubject();
    } on Object {
      state = const FollowFailed();
    }
  }

  void _apply(CropPath path, CropPath pathAtStart) {
    if (_handEdited(pathAtStart)) {
      state = const FollowIdle();
      return;
    }
    ref.read(reelDraftProvider.notifier).followCrop(path);
    state = FollowDone(path.keyframes.length);
  }

  /// The user moved the crop by hand meanwhile; that wins.
  bool _handEdited(CropPath pathAtStart) =>
      ref.read(reelDraftProvider).frame.cropPath != pathAtStart;

  /// Stops the run or the question: nothing is changed and the frames are
  /// deleted.
  void cancel() {
    final wasActive = state is FollowRunning || state is FollowChoosing;
    _stop();
    if (wasActive) {
      state = const FollowIdle();
    }
  }

  /// Back to nothing shown, once the user has seen how a run ended.
  void reset() {
    if (state is! FollowRunning && state is! FollowChoosing) {
      state = const FollowIdle();
    }
  }

  void _stop() {
    _generation++;
    _releasePending();
    final cancelFfmpeg = _cancelFfmpeg;
    _cancelFfmpeg = null;
    if (cancelFfmpeg != null) {
      unawaited(cancelFfmpeg.cancel());
    }
  }

  void _releasePending() {
    final pending = _pending;
    _pending = null;
    if (pending != null) {
      unawaited(pending.frames.delete());
    }
  }

  bool _isStale(int generation) => generation != _generation;

  Future<List<SubjectSample>> _lookAtFrames(
    SampledFrames frames,
    Duration clipStart,
    int generation,
  ) async {
    final detector = ref.read(subjectDetectorProvider)();
    try {
      return await _look(detector, frames, clipStart, generation);
    } finally {
      await detector.close();
    }
  }

  Future<List<SubjectSample>> _look(
    SubjectDetector detector,
    SampledFrames frames,
    Duration clipStart,
    int generation,
  ) async {
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
  // Turning the move off ends the run; the section is gone with it.
  draft.frame.cropPath.isEmpty,
);
