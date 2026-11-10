import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/style/domain/caption_settings.dart';
import 'package:status_studio/src/features/style/domain/crop_path.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/features/transcript/domain/line_edits.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

final reelDraftProvider = NotifierProvider<ReelDraftController, ReelDraft>(
  ReelDraftController.new,
);

class ReelDraftController extends Notifier<ReelDraft> {
  @override
  ReelDraft build() => const ReelDraft();

  void startNew() => state = const ReelDraft();

  /// Continues a kept fine-tune (spec FR-24).
  void restore(ReelDraft draft) => state = draft;

  void setVideo(SourceVideo video) => state = state.withVideo(video);

  void setLanguage(ScriptLanguage language) =>
      state = state.copyWith(language: language);

  /// A script written again replaces the edited lines, so edits stop
  /// shielding the lines from it (spec FR-21).
  void forgetLineEdits() => state = state.copyWith(linesEdited: false);

  void hideLyrics() => state = state.withLyricsHidden();

  void showLyrics() => state = state.withLyricsShown();

  void startTypedLyrics(String text, Duration at) =>
      state = state.withTypedFirstLine(text, at);

  void setTranscript(Transcript transcript) =>
      state = state.withTranscript(transcript);

  void growTranscript(Transcript transcript) =>
      state = state.withGrowingTranscript(transcript);

  /// Applies [edit] to the picked script as it is now, so a tap that lands
  /// after another edit never works from stale lines.
  void editScript(PickedScript Function(PickedScript script) edit) =>
      state = state.withEditedScript(edit(state.pickedScript));

  void nudgeClipStart(Duration delta) {
    final clip = _requireClip();
    state = state.withClip(
      clip.nudgeStart(delta, videoDuration: _requireVideo().duration),
    );
  }

  void nudgeClipEnd(Duration delta) {
    final clip = _requireClip();
    state = state.withClip(
      clip.nudgeEnd(delta, videoDuration: _requireVideo().duration),
    );
  }

  void startMovingCrop() => state = state.withMovingCropStarted();

  void stopMovingCrop() => state = state.withMovingCropStopped();

  void moveCropTo(Duration videoTime, CropAnchor anchor) =>
      state = state.withCropAnchorAt(videoTime, anchor);

  void addCropPosition(Duration videoTime) =>
      state = state.withCropPositionAt(videoTime);

  void followCrop(CropPath path) => state = state.withFollowedCrop(path);

  void setCropArrival(int index, CropArrival arrival) =>
      state = state.withCropArrival(index, arrival);

  void removeCropKeyframe(int index) =>
      state = state.withoutCropKeyframe(index);

  /// Sets the clip start to [videoTime], rounded to a tenth of a second. The
  /// nudge rules apply: a start that leaves under 3 s, or passes the video's
  /// ends, changes nothing (spec FR-5).
  void setClipStartAt(Duration videoTime) =>
      nudgeClipStart(_roundedToTenth(videoTime) - _requireClip().start);

  /// Sets the clip end to [videoTime]; see [setClipStartAt].
  void setClipEndAt(Duration videoTime) =>
      nudgeClipEnd(_roundedToTenth(videoTime) - _requireClip().end);

  void updateFrame(FrameSettings frame) => state = state.copyWith(frame: frame);

  /// While the crop moves its keyframes place the window, so only the free
  /// crop's size may change then (spec FR-6, FR-22).
  void resizeFreeCrop(FreeCropRect crop) {
    final frame = state.frame;
    final kept = frame.cropPath.isEmpty
        ? crop
        : frame.freeCrop.copyWith(width: crop.width, height: crop.height);
    updateFrame(frame.copyWith(freeCrop: kept));
  }

  void updateCaption(CaptionSettings caption) =>
      state = state.copyWith(caption: caption);

  ClipRange _requireClip() {
    final clip = state.clip;
    if (clip == null) {
      throw StateError('The clip was nudged before lines were picked.');
    }
    return clip;
  }

  SourceVideo _requireVideo() {
    final video = state.video;
    if (video == null) {
      throw StateError('The clip was nudged before a video was set.');
    }
    return video;
  }
}

Duration _roundedToTenth(Duration time) =>
    Duration(milliseconds: (time.inMilliseconds / 100).round() * 100);
