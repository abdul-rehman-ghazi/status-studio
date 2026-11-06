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
import 'package:status_studio/src/features/style/domain/scene_choice.dart';
import 'package:status_studio/src/features/style/domain/subject_box.dart';
import 'package:status_studio/src/features/style/domain/subject_path.dart';

/// Where a run of Follow the person is (spec FR-23, FR-27).
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

/// One scene's question: what should the crop keep in frame (spec FR-27).
class FollowChoosing extends FollowState {
  const FollowChoosing({
    required this.sceneIndex,
    required this.sceneCount,
    required this.sceneStart,
    required this.sceneEnd,
    required this.picture,
    required this.pictureSize,
    required this.faces,
    required this.bodies,
    required this.skippedSceneCount,
  });

  /// From 0; the title says one more.
  final int sceneIndex;

  /// How many scenes are asked in all.
  final int sceneCount;
  final Duration sceneStart;
  final Duration sceneEnd;

  /// The scene's fullest sampled frame.
  final File picture;

  /// The video's size; the picture keeps its aspect ratio.
  final OutputSize pictureSize;

  /// In [picture], left to right; an answer names one by its place here.
  final List<SubjectBox> faces;
  final List<SubjectBox> bodies;

  /// Scenes after the first [mostScenesFollowed], which are not asked.
  final int skippedSceneCount;
}

class FollowDone extends FollowState {
  const FollowDone(this.keyframeCount);

  final int keyframeCount;
}

class FollowFailed extends FollowState {
  const FollowFailed();
}

/// What the user answered to a scene's question (spec FR-27). Dismissing the
/// sheet is [Cancelled].
@immutable
sealed class SceneAnswer {
  const SceneAnswer();
}

/// The face at this place in [FollowChoosing.faces].
class PickedFace extends SceneAnswer {
  const PickedFace(this.index);

  final int index;
}

/// The body at this place in [FollowChoosing.bodies].
class PickedBody extends SceneAnswer {
  const PickedBody(this.index);

  final int index;
}

/// A spot in the picture, as fractions of its width and height.
class PickedSpot extends SceneAnswer {
  const PickedSpot({required this.x, required this.y});

  final double x;
  final double y;
}

/// Back to the scene before, to change its answer; the answers given stay.
class WentBack extends SceneAnswer {
  const WentBack();
}

class Cancelled extends SceneAnswer {
  const Cancelled();
}

/// The walk through the scenes: what the questions need, and the answers so
/// far.
class _Walk {
  _Walk({
    required this.frames,
    required this.scenes,
    required this.pictures,
    required this.geometry,
    required this.pictureSize,
    required this.pathAtStart,
  }) : answers = List.filled(pictures.length, null);

  final SampledFrames frames;
  final List<SubjectScene> scenes;

  /// One per scene asked.
  final List<ScenePicture> pictures;
  final FollowGeometry geometry;
  final OutputSize pictureSize;
  final CropPath pathAtStart;

  /// One per scene asked; null until it is answered.
  final List<SceneChoice?> answers;
  var sceneIndex = 0;

  /// The first scene that has no answer yet, or null when all have one.
  int? get firstUnanswered {
    final index = answers.indexWhere((answer) => answer == null);
    return index < 0 ? null : index;
  }

  List<SceneChoice> get allAnswers => [for (final a in answers) a!];
}

/// Sampling the frames takes this share of the progress; the rest is looking
/// at them.
const _samplingShare = 0.25;

final followSubjectProvider =
    NotifierProvider.autoDispose<FollowSubjectController, FollowState>(
      FollowSubjectController.new,
    );

/// Looks at the clip's frames, asks what to keep in frame at every scene and
/// writes the crop's keyframes (spec FR-23, FR-27). Everything stays on the
/// phone.
class FollowSubjectController extends Notifier<FollowState> {
  /// Bumped by every start and cancel, so a run that was stopped notices
  /// between frames and ends without touching anything.
  var _generation = 0;
  FfmpegCancelHandle? _cancelFfmpeg;

  /// The frames kept on disk while the user chooses; deleted by whatever ends
  /// the walk.
  _Walk? _walk;

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
      throw StateError(
        'Follow the person started before the video was opened.',
      );
    }
    _releaseWalk();
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
      final scenes = scenesOf(track, geometry);
      if (scenes.isEmpty) {
        throw const FollowFailedException('no scene had a frame');
      }
      if (_handEdited(pathAtStart)) {
        state = const FollowIdle();
        return;
      }
      final asked = scenes.take(mostScenesFollowed).toList();
      _walk = _Walk(
        frames: frames,
        scenes: scenes,
        pictures: [for (final scene in asked) pictureOfScene(scene)],
        geometry: geometry,
        pictureSize: sourceSize,
        pathAtStart: pathAtStart,
      );
      keptForTheChoice = true;
      _ask(0);
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

  /// The user answered the scene's question (spec FR-27).
  void answer(SceneAnswer answer) {
    final walk = _walk;
    if (walk == null || state is! FollowChoosing) {
      return;
    }
    switch (answer) {
      case Cancelled():
        cancel();
      case WentBack():
        if (walk.sceneIndex > 0) {
          _ask(walk.sceneIndex - 1);
        }
      case PickedFace() || PickedBody() || PickedSpot():
        _keep(walk, _choiceFor(walk, answer));
    }
  }

  SceneChoice _choiceFor(_Walk walk, SceneAnswer answer) {
    final picture = walk.pictures[walk.sceneIndex];
    return switch (answer) {
      PickedFace(:final index) => FollowFace(picture.faces[index].track),
      PickedBody(:final index) => FollowBody(picture.bodies[index].track),
      PickedSpot(:final x, :final y) => HoldSpot(
        anchorForSpot(x, y, walk.geometry),
      ),
      WentBack() || Cancelled() => throw ArgumentError.value(
        answer,
        'answer',
        'is not a choice',
      ),
    };
  }

  /// Records the answer and asks the first scene still unanswered, so going
  /// back to change one answer comes forward again to where the user was.
  void _keep(_Walk walk, SceneChoice choice) {
    walk.answers[walk.sceneIndex] = choice;
    final next = walk.firstUnanswered;
    if (next != null) {
      _ask(next);
      return;
    }
    _walk = null;
    unawaited(walk.frames.delete());
    try {
      _apply(
        pathForChoices(walk.scenes, walk.geometry, walk.allAnswers),
        walk.pathAtStart,
      );
    } on Object {
      state = const FollowFailed();
    }
  }

  void _ask(int sceneIndex) {
    final walk = _walk!;
    walk.sceneIndex = sceneIndex;
    final picture = walk.pictures[sceneIndex];
    final scenes = walk.scenes;
    state = FollowChoosing(
      sceneIndex: sceneIndex,
      sceneCount: walk.pictures.length,
      sceneStart: scenes[sceneIndex].start,
      sceneEnd: sceneIndex + 1 < scenes.length
          ? scenes[sceneIndex + 1].start
          : walk.geometry.clip.end,
      picture: walk.frames.frames[picture.sampleIndex],
      pictureSize: walk.pictureSize,
      faces: [for (final person in picture.faces) person.box],
      bodies: [for (final person in picture.bodies) person.box],
      skippedSceneCount: scenes.length - walk.pictures.length,
    );
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
    _releaseWalk();
    final cancelFfmpeg = _cancelFfmpeg;
    _cancelFfmpeg = null;
    if (cancelFfmpeg != null) {
      unawaited(cancelFfmpeg.cancel());
    }
  }

  void _releaseWalk() {
    final walk = _walk;
    _walk = null;
    if (walk != null) {
      unawaited(walk.frames.delete());
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
