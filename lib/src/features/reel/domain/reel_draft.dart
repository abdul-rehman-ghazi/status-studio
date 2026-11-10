import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/clip/domain/lines_in_clip.dart';
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
    this.lyricsSkipped = false,
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

  /// Whether the user chose to make the reel without a script (spec FR-29):
  /// lines a script run still sends are not added.
  final bool lyricsSkipped;

  /// Starts the reel on [video]: the clip is the whole video, which the user
  /// trims on Fine-tune (spec FR-1, FR-5). The same video again (Back to
  /// Source, then Get the script) keeps the clip, frame and caption.
  ReelDraft withVideo(SourceVideo video) {
    if (video.videoId == this.video?.videoId) {
      return copyWith(video: video);
    }
    return ReelDraft(
      video: video,
      language: language,
      clip: _wholeVideo(video),
    );
  }

  /// The reel without a script (spec FR-29): the lines and the caption text
  /// go; the clip, the frame and the caption's look stay.
  ReelDraft withoutLyrics() => ReelDraft(
    video: video,
    language: language,
    clip: clip ?? _wholeVideo(video),
    frame: frame,
    caption: caption.copyWith(variant: CaptionVariant.original, text: ''),
    lyricsSkipped: true,
  );

  /// The reel with a script again, which Processing writes (spec FR-29).
  ReelDraft withLyrics() => copyWith(lyricsSkipped: false);

  /// A new transcript replaces the lines and the caption text filled from
  /// them; the clip, its nudges and the crop keyframes stay (spec FR-5). The
  /// lines inside the clip are the selected ones: nothing is picked (spec
  /// FR-4).
  ReelDraft withTranscript(Transcript transcript) => _selectingLinesInClip(
    transcript,
    clip,
  )._withCaptionFromLines().copyWith(linesEdited: false);

  /// A transcript that only adds lines to the current one (a script still
  /// being written) keeps what the user edited; any other replaces it.
  ReelDraft withGrowingTranscript(Transcript transcript) {
    final current = this.transcript;
    if (linesEdited || lyricsSkipped) {
      return this;
    }
    if (current == null || !_extends(transcript, current)) {
      return withTranscript(transcript);
    }
    return _selectingLinesInClip(transcript, clip);
  }

  /// [corrected] has the same lines with better text. The clip stays, and
  /// so does a caption the user changed.
  ReelDraft withCorrectedLines(Transcript corrected) =>
      _selectingLinesInClip(corrected, clip);

  /// Moves the clip to [newClip]; the selected lines follow it, and so does
  /// the caption while it is still the lines' own text (spec FR-5).
  ReelDraft withClip(ClipRange newClip) {
    final transcript = this.transcript;
    return transcript == null
        ? copyWith(clip: newClip)
        : _selectingLinesInClip(transcript, newClip);
  }

  /// Selects the lines inside [clip], or inside the whole video when there
  /// is no clip yet. The caption is refilled only while it is still the
  /// lines' own text, so a caption the user typed or translated stays.
  ReelDraft _selectingLinesInClip(Transcript transcript, ClipRange? clip) {
    final inClip = clip ?? _wholeVideo(video);
    final followsLines = _captionFollowsLines;
    if (inClip == null || transcript.lines.isEmpty) {
      return copyWith(
        transcript: transcript,
        selection: const NoSelection(),
        clip: inClip,
      );
    }
    final selection = linesInClip(transcript, inClip);
    return copyWith(
      transcript: transcript,
      selection: selection,
      clip: inClip,
      caption: followsLines
          ? caption.copyWith(
              variant: CaptionVariant.original,
              text: _selectedText(transcript, selection),
            )
          : caption,
    );
  }

  bool get _captionFollowsLines =>
      caption.variant == CaptionVariant.original &&
      caption.text == _selectedLinesText;

  ReelDraft _withCaptionFromLines() => copyWith(
    caption: caption.copyWith(
      variant: CaptionVariant.original,
      text: _selectedLinesText,
    ),
  );

  String get _selectedLinesText =>
      _selectedLines.map((line) => line.text).join('\n');

  /// The script with the lines inside the clip, for editing (spec FR-21).
  PickedScript get pickedScript {
    final transcript = this.transcript;
    final selection = this.selection;
    if (transcript == null || selection is! RangeSelected) {
      throw StateError('Lines were edited before a script was written.');
    }
    return PickedScript(transcript: transcript, selection: selection);
  }

  /// Applies an edit made on Fine-tune (spec FR-21). The caption is refilled
  /// from the lines inside the clip; the clip stays, since it no longer
  /// follows the lines.
  ReelDraft withEditedScript(PickedScript edited) => _selectingLinesInClip(
    edited.transcript,
    clip,
  )._withCaptionFromLines().copyWith(linesEdited: true);

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
    bool? lyricsSkipped,
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
      lyricsSkipped: lyricsSkipped ?? this.lyricsSkipped,
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
      other.linesEdited == linesEdited &&
      other.lyricsSkipped == lyricsSkipped;

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
    lyricsSkipped,
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
