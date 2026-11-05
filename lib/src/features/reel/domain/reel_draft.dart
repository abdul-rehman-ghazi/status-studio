import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/style/domain/caption_cues.dart';
import 'package:status_studio/src/features/style/domain/caption_settings.dart';
import 'package:status_studio/src/features/style/domain/crop_path.dart';
import 'package:status_studio/src/features/style/domain/crop_rect.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/features/transcript/domain/line_edits.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

/// The reel being made, carried through the whole flow.
@immutable
class ReelDraft {
  const ReelDraft({
    this.video,
    this.language = ScriptLanguage.auto,
    this.transcript,
    this.selection = const NoSelection(),
    this.clip,
    this.frame = const FrameSettings(),
    this.caption = const CaptionSettings(),
    this.linesEdited = false,
  });

  final SourceVideo? video;
  final ScriptLanguage language;
  final Transcript? transcript;
  final LineSelection selection;
  final ClipRange? clip;
  final FrameSettings frame;
  final CaptionSettings caption;

  /// Whether lines were edited on Fine-tune (FR-21); lines still being
  /// written no longer replace the edited ones.
  final bool linesEdited;

  /// Starts the reel on [video]: the clip is the whole video, which the user
  /// trims on Fine-tune (spec FR-1, FR-5).
  ReelDraft withVideo(SourceVideo video) =>
      copyWith(video: video, clip: _wholeVideo(video));

  /// A new transcript replaces the lines and the per-line caption edits; the
  /// clip, its nudges and the crop keyframes stay (spec FR-5). Every line is
  /// selected: there is no line picking (spec FR-4).
  ReelDraft withTranscript(Transcript transcript) =>
      _withEveryLine(transcript).copyWith(linesEdited: false);

  /// A transcript that only adds lines to the current one (a script still
  /// being written) keeps what the user edited; any other replaces it.
  ReelDraft withGrowingTranscript(Transcript transcript) {
    final current = this.transcript;
    if (linesEdited) {
      return this;
    }
    if (current == null || !_extends(transcript, current)) {
      return withTranscript(transcript);
    }
    return _withEveryLine(transcript);
  }

  /// [corrected] has the same lines with better text, so the caption is
  /// refilled from them and the clip stays.
  ReelDraft withCorrectedLines(Transcript corrected) =>
      _withEveryLine(corrected);

  ReelDraft _withEveryLine(Transcript transcript) {
    final lastLine = transcript.lines.length - 1;
    if (lastLine < 0) {
      return copyWith(
        transcript: transcript,
        selection: const NoSelection(),
        clip: clip ?? _wholeVideo(video),
      );
    }
    final selection = RangeSelected(0, lastLine);
    return copyWith(
      transcript: transcript,
      selection: selection,
      clip: clip ?? _wholeVideo(video),
      caption: caption.copyWith(
        variant: CaptionVariant.original,
        text: _selectedText(transcript, selection),
      ),
    );
  }

  /// The script with its picked range, for editing lines (spec FR-21).
  PickedScript get pickedScript {
    final transcript = this.transcript;
    final selection = this.selection;
    if (transcript == null || selection is! RangeSelected) {
      throw StateError('Lines were edited before a range was picked.');
    }
    return PickedScript(transcript: transcript, selection: selection);
  }

  /// Applies an edit made on Fine-tune (spec FR-21). The caption is refilled
  /// from the lines; the clip stays, since it no longer follows the lines.
  ReelDraft withEditedScript(PickedScript edited) {
    return copyWith(
      transcript: edited.transcript,
      selection: edited.selection,
      caption: caption.copyWith(
        variant: CaptionVariant.original,
        text: _selectedText(edited.transcript, edited.selection),
      ),
      linesEdited: true,
    );
  }

  /// Starts a moving crop (spec FR-22): one keyframe at the clip start, where
  /// the fixed crop is.
  ReelDraft withMovingCropStarted() {
    final start = _requireClip().start;
    return _withCropPath(CropPath.startingAt(start, baseAnchorFor(frame)));
  }

  /// Ends the moving crop and keeps the crop where it was at the clip start.
  ReelDraft withMovingCropStopped() {
    _requireClip();
    return copyWith(frame: _frameWithoutMovingCrop);
  }

  /// The frame with its keyframes gone and the crop left where it was at the
  /// clip start (the base anchor for Crop to fill, the rectangle for Free
  /// crop). Picking other lines or a new script does this, since the
  /// keyframes belong to the old clip (spec FR-22).
  FrameSettings get _frameWithoutMovingCrop {
    if (frame.cropPath.isEmpty) {
      return frame;
    }
    final start = clip?.start;
    if (start == null) {
      return frame.copyWith(cropPath: const CropPath());
    }
    final atStart = frame.cropPath.anchorAt(start, base: baseAnchorFor(frame));
    final fixed = frame.preset == AspectPreset.free
        ? frame.copyWith(freeCrop: _freeCropAt(frame.freeCrop, atStart))
        : frame.copyWith(anchor: atStart);
    return fixed.copyWith(cropPath: const CropPath());
  }

  /// Sets the crop's anchor at [videoTime], moved into the clip.
  ReelDraft withCropAnchorAt(Duration videoTime, CropAnchor anchor) {
    final clip = _requireClip();
    // Snapping happens in the path, so the limits are snapped inwards first:
    // a keyframe rounded out of the clip would never be reached.
    final earliest = _roundedUpToTenth(clip.start);
    final latest = _roundedDownToTenth(clip.end);
    final inClip = videoTime < earliest
        ? earliest
        : (videoTime > latest ? latest : videoTime);
    return _withCropPath(frame.cropPath.withAnchorAt(inClip, anchor));
  }

  /// Replaces the crop's keyframes with [path], which followed a person
  /// (spec FR-23). Throws for an empty path: that would end the moving crop,
  /// which has its own method.
  ReelDraft withFollowedCrop(CropPath path) {
    if (path.isEmpty) {
      throw ArgumentError.value(path, 'path', 'has no keyframes');
    }
    return _withCropPath(path);
  }

  ReelDraft withCropArrival(int index, CropArrival arrival) =>
      _withCropPath(frame.cropPath.withArrival(index, arrival));

  ReelDraft withoutCropKeyframe(int index) =>
      _withCropPath(frame.cropPath.withoutKeyframe(index));

  ReelDraft _withCropPath(CropPath path) =>
      copyWith(frame: frame.copyWith(cropPath: path));

  ClipRange _requireClip() {
    final clip = this.clip;
    if (clip == null) {
      throw StateError('The crop was moved before a clip was set.');
    }
    return clip;
  }

  /// Applies [selection]; a full range also sets the clip and fills the
  /// caption with the selected lines.
  ReelDraft withSelection(LineSelection selection) {
    final transcript = this.transcript;
    if (transcript == null) {
      throw StateError('Lines were selected before a transcript was set.');
    }
    if (selection is! RangeSelected) {
      return ReelDraft(
        video: video,
        language: language,
        transcript: transcript,
        selection: selection,
        frame: _frameWithoutMovingCrop,
        caption: caption,
      );
    }
    return copyWith(
      selection: selection,
      clip: ClipRange.fromLines(transcript, selection),
      frame: _frameWithoutMovingCrop,
      caption: caption.copyWith(
        variant: CaptionVariant.original,
        text: _selectedText(transcript, selection),
      ),
    );
  }

  /// The caption's lines with their times, or none before a clip is set
  /// (spec FR-7a).
  List<CaptionCue> get captionCues {
    final clip = this.clip;
    if (clip == null) {
      return const [];
    }
    return buildCaptionCues(
      captionText: caption.text,
      spokenLines: _selectedLines,
      clip: clip,
    );
  }

  List<TranscriptLine> get _selectedLines {
    final transcript = this.transcript;
    final selection = this.selection;
    if (transcript == null || selection is! RangeSelected) {
      return const [];
    }
    return transcript.lines.sublist(selection.start, selection.end + 1);
  }

  ReelDraft copyWith({
    SourceVideo? video,
    ScriptLanguage? language,
    Transcript? transcript,
    LineSelection? selection,
    ClipRange? clip,
    FrameSettings? frame,
    CaptionSettings? caption,
    bool? linesEdited,
  }) {
    return ReelDraft(
      video: video ?? this.video,
      language: language ?? this.language,
      transcript: transcript ?? this.transcript,
      selection: selection ?? this.selection,
      clip: clip ?? this.clip,
      frame: frame ?? this.frame,
      caption: caption ?? this.caption,
      linesEdited: linesEdited ?? this.linesEdited,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReelDraft &&
      other.video == video &&
      other.language == language &&
      other.transcript == transcript &&
      other.selection == selection &&
      other.clip == clip &&
      other.frame == frame &&
      other.caption == caption &&
      other.linesEdited == linesEdited;

  @override
  int get hashCode => Object.hash(
    video,
    language,
    transcript,
    selection,
    clip,
    frame,
    caption,
    linesEdited,
  );
}

ClipRange? _wholeVideo(SourceVideo? video) =>
    video == null ? null : ClipRange(start: Duration.zero, end: video.duration);

const _tenth = Duration(milliseconds: 100);

Duration _roundedUpToTenth(Duration time) {
  final tenths = (time.inMicroseconds / _tenth.inMicroseconds).ceil();
  return _tenth * tenths;
}

Duration _roundedDownToTenth(Duration time) {
  final tenths = (time.inMicroseconds / _tenth.inMicroseconds).floor();
  return _tenth * tenths;
}

FreeCropRect _freeCropAt(FreeCropRect crop, CropAnchor anchor) {
  return crop.copyWith(
    left: anchor.x * (1 - crop.width),
    top: anchor.y * (1 - crop.height),
  );
}

bool _extends(Transcript grown, Transcript current) =>
    grown.lines.length >= current.lines.length &&
    listEquals(grown.lines.sublist(0, current.lines.length), current.lines);

String _selectedText(Transcript transcript, RangeSelected selection) {
  return transcript.lines
      .sublist(selection.start, selection.end + 1)
      .map((line) => line.text)
      .join('\n');
}
