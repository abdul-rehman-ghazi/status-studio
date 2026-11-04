import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/style/domain/caption_settings.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

final reelDraftProvider = NotifierProvider<ReelDraftController, ReelDraft>(
  ReelDraftController.new,
);

class ReelDraftController extends Notifier<ReelDraft> {
  @override
  ReelDraft build() => const ReelDraft();

  void startNew() => state = const ReelDraft();

  void setVideo(SourceVideo video) => state = state.copyWith(video: video);

  void setLanguage(ScriptLanguage language) =>
      state = state.copyWith(language: language);

  void setTranscript(Transcript transcript) =>
      state = state.withTranscript(transcript);

  void correctTranscript(Transcript corrected) =>
      state = state.withCorrectedLines(corrected);

  void growTranscript(Transcript transcript) =>
      state = state.withGrowingTranscript(transcript);

  void tapLine(int index) =>
      state = state.withSelection(state.selection.tap(index));

  void nudgeClipStart(Duration delta) {
    final clip = _requireClip();
    state = state.copyWith(
      clip: clip.nudgeStart(delta, videoDuration: _requireVideo().duration),
    );
  }

  void nudgeClipEnd(Duration delta) {
    final clip = _requireClip();
    state = state.copyWith(
      clip: clip.nudgeEnd(delta, videoDuration: _requireVideo().duration),
    );
  }

  void updateFrame(FrameSettings frame) => state = state.copyWith(frame: frame);

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
