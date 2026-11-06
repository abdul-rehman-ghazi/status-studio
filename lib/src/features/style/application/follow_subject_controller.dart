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

  /// One per scene asked; null until it is answered. A body answer is only
  /// turned into a track after the last answer, since it takes a look at the
  /// scene's frames.
  final List<SceneAnswer?> answers;
  var sceneIndex = 0;

  /// The first scene that has no answer yet, or null when all have one.
  int? get firstUnanswered {
    final index = answers.indexWhere((answer) => answer == null);
    return index < 0 ? null : index;
  }

  /// Where in the track's samples the scene's frames start.
  int firstFrameOf(int scene) => scenes[scene].firstIndex;
}

/// What looking for the bodies of the answered scenes needs, and how far it
/// has got.
class _BodyWork {
  _BodyWork({
    required this.detector,
    required this.generation,
    required this.totalFrames,
  });

  final SubjectDetector detector;
  final int generation;
  final int totalFrames;
  var framesLooked = 0;
}

/// Sampling the frames takes this share of the progress, looking for faces in
/// them up to [_facesShare], and the bodies in each scene's picture the rest.
const _samplingShare = 0.25;
const _facesShare = 0.85;

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
      final pictures = await _withBodies(
        [for (final scene in asked) pictureOfScene(scene)],
        frames,
        generation,
      );
      if (_isStale(generation)) {
        return;
      }
      _walk = _Walk(
        frames: frames,
        scenes: scenes,
        pictures: pictures,
        geometry: geometry,
        pictureSize: sourceSize,
        pathAtStart: pathAtStart,
      );
      _ask(0);
      keptForTheChoice = true;
    } on Object {
      if (!_isStale(generation)) {
        state = const FollowFailed();
      }
    } finally {
      if (!keptForTheChoice) {
        // Only this run's walk: a newer run may have its own by now.
        if (identical(_walk?.frames, frames)) {
          _walk = null;
        }
        await frames?.delete();
      }
    }
  }

  /// The user answered [question] (spec FR-27). An answer to a question that
  /// is no longer the current one is ignored.
  void answer(FollowChoosing question, SceneAnswer answer) {
    final walk = _walk;
    if (walk == null || !identical(state, question)) {
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
        _keep(walk, answer);
    }
  }

  /// Records the answer and asks the first scene still unanswered, so going
  /// back to change one answer comes forward again to where the user was.
  void _keep(_Walk walk, SceneAnswer answer) {
    walk.answers[walk.sceneIndex] = answer;
    final next = walk.firstUnanswered;
    if (next != null) {
      _ask(next);
      return;
    }
    unawaited(_finish(walk));
  }

  /// Turns the answers into the crop's keyframes. Faces and spots are known
  /// already; a body has to be looked for in its scene's frames first, which
  /// shows the progress again.
  Future<void> _finish(_Walk walk) async {
    final generation = _generation;
    try {
      final choices = await _choicesFor(walk, generation);
      if (_isStale(generation)) {
        return;
      }
      _releaseWalk();
      _apply(
        pathForChoices(walk.scenes, walk.geometry, choices),
        walk.pathAtStart,
      );
    } on Object {
      if (!_isStale(generation)) {
        _releaseWalk();
        state = const FollowFailed();
      }
    }
  }

  Future<List<SceneChoice>> _choicesFor(_Walk walk, int generation) async {
    final answers = [for (final answer in walk.answers) answer!];
    final bodyScenes = [
      for (final (index, answer) in answers.indexed)
        if (answer is PickedBody) index,
    ];
    if (bodyScenes.isEmpty) {
      return [
        for (final (index, answer) in answers.indexed)
          _choiceFor(walk, index, answer),
      ];
    }
    state = const FollowRunning(0);
    final work = _BodyWork(
      detector: ref.read(subjectDetectorProvider)(),
      generation: generation,
      // Every other frame of each scene is looked at.
      totalFrames: [
        for (final index in bodyScenes)
          (walk.scenes[index].samples.length + 1) ~/ 2,
      ].fold(0, (sum, frames) => sum + frames),
    );
    try {
      return [
        for (final (index, answer) in answers.indexed)
          answer is PickedBody
              ? await _followBody(walk, index, work)
              : _choiceFor(walk, index, answer),
      ];
    } finally {
      await work.detector.close();
    }
  }

  SceneChoice _choiceFor(_Walk walk, int sceneIndex, SceneAnswer answer) {
    return switch (answer) {
      PickedFace(:final index) => FollowFace(
        walk.pictures[sceneIndex].faces[index].track,
      ),
      PickedSpot(:final x, :final y) => HoldSpot(
        anchorForSpot(x, y, walk.geometry),
      ),
      PickedBody() || WentBack() || Cancelled() => throw ArgumentError.value(
        answer,
        'answer',
        'is not a face or a spot',
      ),
    };
  }

  /// The body chosen in the scene's picture, followed through the scene. The
  /// detector looks at every other frame (a body is big and slow), and the
  /// picture's own boxes stand for its frame.
  Future<SceneChoice> _followBody(
    _Walk walk,
    int sceneIndex,
    _BodyWork work,
  ) async {
    final scene = walk.scenes[sceneIndex];
    final picture = walk.pictures[sceneIndex];
    final pictureIndex = picture.sampleIndex - walk.firstFrameOf(sceneIndex);
    final chosen =
        picture.bodies[(walk.answers[sceneIndex]! as PickedBody).index];
    final samples = <SubjectSample>[];
    for (final (index, sample) in scene.samples.indexed) {
      final bodies = index == pictureIndex
          ? picture.bodies
          : index.isOdd
          ? const <SubjectBox>[]
          : await _lookForBodies(
              walk.frames.frames[scene.firstIndex + index],
              work,
            );
      if (_isStale(work.generation)) {
        throw const FollowFailedException('stopped');
      }
      samples.add(SubjectSample(time: sample.time, faces: bodies));
    }
    return FollowBody(trackOfBody(samples, pictureIndex, chosen));
  }

  Future<List<SubjectBox>> _lookForBodies(File frame, _BodyWork work) async {
    final bodies = await work.detector.bodiesIn(frame);
    state = FollowRunning(++work.framesLooked / work.totalFrames);
    return bodies;
  }

  /// Looks for the bodies in each picture. A phone where the body model can't
  /// load or run still has faces and spots, so a failure leaves the pictures
  /// with no bodies instead of ending the run.
  Future<List<ScenePicture>> _withBodies(
    List<ScenePicture> pictures,
    SampledFrames frames,
    int generation,
  ) async {
    final detector = ref.read(subjectDetectorProvider)();
    try {
      final withBodies = <ScenePicture>[];
      for (final (index, picture) in pictures.indexed) {
        final bodies = await detector.bodiesIn(
          frames.frames[picture.sampleIndex],
        );
        if (_isStale(generation)) {
          return pictures;
        }
        withBodies.add(picture.withBodies(bodies));
        state = FollowRunning(
          _facesShare + (1 - _facesShare) * (index + 1) / pictures.length,
        );
      }
      return withBodies;
    } on Object {
      return pictures;
    } finally {
      await detector.close();
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
      // The last scene asked holds to the clip's end when scenes were left out.
      sceneEnd: sceneIndex + 1 < walk.pictures.length
          ? scenes[sceneIndex + 1].start
          : walk.geometry.clip.end,
      picture: walk.frames.frames[picture.sampleIndex],
      pictureSize: walk.pictureSize,
      faces: [for (final person in picture.faces) person.box],
      bodies: picture.bodies,
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
            (_facesShare - _samplingShare) * (index + 1) / frames.frames.length,
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
