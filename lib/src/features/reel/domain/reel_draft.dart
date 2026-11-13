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
import 'package:status_studio/src/features/transcript/domain/lines_history.dart';
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
    this.lyricsShown = true,
    this.fadeEnds = false,
    this.louderSound = false,
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

  /// Whether the lyrics are on the reel (spec FR-29, M30). Off, the lines
  /// are kept but the reel has no caption, and lines a script run still
  /// sends are not added.
  final bool lyricsShown;

  /// Whether the picture fades in from black and out to black (spec FR-33).
  final bool fadeEnds;

  /// Whether quiet sound is raised at export (spec FR-42).
  final bool louderSound;

  /// Starts the reel on [video]: the clip is the whole video, which the user
  /// trims on Fine-tune (spec FR-1, FR-5). The same video again (Back to
  /// Source, then Get the script) keeps the clip, frame and caption.
  ReelDraft withVideo(SourceVideo video) {
    if (video.videoId == this.video?.videoId) {
      return copyWith(
        video: video,
        clip: clip?.startingNoEarlierThan(video.pictureStart),
      );
    }
    return ReelDraft(
      video: video,
      language: language,
      clip: _playableRangeOf(video),
    );
  }

  /// Starts the reel on [clip] of [video]: one moment kept from a link
  /// opens on the moment, not on the seconds its file has around it (spec
  /// FR-46). The same video again keeps its clip, as [withVideo] does.
  ReelDraft withVideoOn(SourceVideo video, ClipRange clip) {
    if (video.videoId == this.video?.videoId) {
      return withVideo(video);
    }
    return ReelDraft(
      video: video,
      language: language,
      clip: clip.startingNoEarlierThan(video.pictureStart),
    );
  }

  ReelDraft withFadeEnds() => copyWith(fadeEnds: true);

  ReelDraft withoutFadeEnds() => copyWith(fadeEnds: false);

  ReelDraft withLouderSound() => copyWith(louderSound: true);

  ReelDraft withoutLouderSound() => copyWith(louderSound: false);

  /// The reel without lyrics (spec FR-29): the caption is emptied, but the
  /// lines stay, so turning the lyrics back on brings them back.
  ReelDraft withLyricsHidden() =>
      copyWith(lyricsShown: false, caption: caption.copyWith(text: ''));

  /// The lyrics on the reel again, the caption refilled from the lines.
  ReelDraft withLyricsShown() =>
      copyWith(lyricsShown: true)._withCaptionFromLines();

  /// A line the user types (spec FR-21): Type them myself's first line, or
  /// Add line on a clip with no line in it (M40). One line of [text] from
  /// [at], 2 s long and cut at the clip end, put into the script in time
  /// order (or as the whole script when there is none), and counted as
  /// edited so it is saved as the `edited` script.
  ReelDraft withTypedLine(String text, Duration at) {
    final clip = _requireClip();
    final latestStart = clip.end - _typedLineLength ~/ 2;
    final start = at < clip.start
        ? clip.start
        : (at > latestStart ? latestStart : at);
    final end = start + _typedLineLength;
    final line = TranscriptLine(
      index: 0,
      text: text,
      start: start,
      end: end < clip.end ? end : clip.end,
    );
    final current = transcript;
    final typed = current == null
        ? Transcript(languageCode: language.whisperCode, lines: [line])
        : withLineInserted(current, line);
    return _selectingLinesInClip(
      typed,
      clip,
    )._withCaptionFromLines().copyWith(linesEdited: true);
  }

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
    if (linesEdited || !lyricsShown) {
      return this;
    }
    if (current == null || !_extends(transcript, current)) {
      return withTranscript(transcript);
    }
    return _selectingLinesInClip(transcript, clip);
  }

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
  /// lines' own text, so a caption the user typed stays.
  ReelDraft _selectingLinesInClip(Transcript transcript, ClipRange? clip) {
    final inClip = clip ?? _playableRangeOf(video);
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
          ? caption.copyWith(text: _selectedText(transcript, selection))
          : caption,
    );
  }

  bool get _captionFollowsLines => caption.text == _selectedLinesText;

  /// Hidden lyrics leave the caption empty (spec FR-29).
  ReelDraft _withCaptionFromLines() => copyWith(
    caption: caption.copyWith(text: lyricsShown ? _selectedLinesText : ''),
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

  /// The lines as they are now, for undo (spec FR-34). Throws [StateError]
  /// before there is a script.
  LinesSnapshot get linesSnapshot {
    final transcript = this.transcript;
    if (transcript == null) {
      throw StateError('There are no lines to keep for undo yet.');
    }
    return LinesSnapshot(transcript: transcript, linesEdited: linesEdited);
  }

  /// The lines of an undo or redo step, with the caption refilled from them
  /// (spec FR-34).
  ReelDraft withLinesRestored(LinesSnapshot snapshot) => _selectingLinesInClip(
    snapshot.transcript,
    clip,
  )._withCaptionFromLines().copyWith(linesEdited: snapshot.linesEdited);

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

  /// Adds a crop position at [videoTime] holding the crop where it is at that
  /// moment (spec FR-22, "New position here"); it is then dragged into place.
  ReelDraft withCropPositionAt(Duration videoTime) {
    final anchor = frame.cropPath.anchorAt(
      videoTime,
      base: baseAnchorFor(frame),
    );
    return withCropAnchorAt(videoTime, anchor);
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
      caption: caption.copyWith(text: _selectedText(transcript, selection)),
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
    bool? lyricsShown,
    bool? fadeEnds,
    bool? louderSound,
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
      lyricsShown: lyricsShown ?? this.lyricsShown,
      fadeEnds: fadeEnds ?? this.fadeEnds,
      louderSound: louderSound ?? this.louderSound,
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
      other.lyricsShown == lyricsShown &&
      other.fadeEnds == fadeEnds &&
      other.louderSound == louderSound;

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
    lyricsShown,
    fadeEnds,
    louderSound,
  );
}

/// The whole video from where its picture starts (spec FR-5, M41).
ClipRange? _playableRangeOf(SourceVideo? video) => video == null
    ? null
    : ClipRange(start: video.pictureStart, end: video.duration);

const _tenth = Duration(milliseconds: 100);
const _typedLineLength = Duration(seconds: 2);

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

/// Empty when no line is selected (a clip over silence, spec FR-21).
String _selectedText(Transcript transcript, LineSelection selection) {
  if (selection is! RangeSelected) {
    return '';
  }
  return transcript.lines
      .sublist(selection.start, selection.end + 1)
      .map((line) => line.text)
      .join('\n');
}
