import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/clip/domain/lines_in_clip.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/style/domain/caption_settings.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

/// The script lines a kept fine-tune was working on: which ones were inside
/// the clip, and a fingerprint that tells a changed script apart.
@immutable
class KeptLines {
  const KeptLines({required this.selection, required this.fingerprint});

  final RangeSelected selection;
  final int fingerprint;

  @override
  bool operator ==(Object other) =>
      other is KeptLines &&
      other.selection == selection &&
      other.fingerprint == fingerprint;

  @override
  int get hashCode => Object.hash(selection, fingerprint);
}

/// Fine-tune work kept to continue later, one per video (spec FR-24, M30).
/// It is kept from the moment Fine-tune · Video opens, with or without
/// lyrics. The script itself is not copied: [scriptKey] names it, and
/// [lines] is set only once there were lines inside the clip.
@immutable
class FineTuneDraft {
  const FineTuneDraft({
    required this.videoId,
    required this.language,
    required this.lyricsShown,
    this.fadeEnds = false,
    required this.lines,
    required this.clip,
    required this.frame,
    required this.caption,
    required this.linesEdited,
    required this.savedAt,
  });

  /// Throws [StateError] when [draft] has no video or clip yet (see
  /// [canKeep]).
  factory FineTuneDraft.of(ReelDraft draft, {required DateTime savedAt}) {
    final clip = draft.clip;
    final video = draft.video;
    if (video == null || clip == null) {
      throw StateError('Nothing to keep before a video and a clip are set.');
    }
    return FineTuneDraft(
      videoId: video.videoId,
      language: draft.language,
      lyricsShown: draft.lyricsShown,
      fadeEnds: draft.fadeEnds,
      lines: _keptLines(draft),
      clip: clip,
      frame: draft.frame,
      caption: draft.caption,
      linesEdited: draft.linesEdited,
      savedAt: savedAt,
    );
  }

  /// Whether [draft] has reached Fine-tune: a video and a clip.
  static bool canKeep(ReelDraft draft) =>
      draft.video != null && draft.clip != null;

  final String videoId;
  final ScriptLanguage language;
  final bool lyricsShown;

  /// The picture fades in and out (spec FR-33).
  final bool fadeEnds;
  final KeptLines? lines;
  final ClipRange clip;
  final FrameSettings frame;
  final CaptionSettings caption;
  final bool linesEdited;
  final DateTime savedAt;

  /// The saved script this fine-tune's lines come from (FR-14).
  TranscriptKey get scriptKey =>
      TranscriptKey(videoId: videoId, language: language);

  /// Whether [transcript] is still the script the kept lines came from: the
  /// same lines up to the last one inside the clip, with the clip inside
  /// [video]. Without kept lines only the clip is checked.
  bool fits(SourceVideo video, Transcript transcript) {
    final lines = this.lines;
    if (lines == null) {
      return clipFits(video);
    }
    if (lines.selection.end >= transcript.lines.length) {
      return false;
    }
    return _fingerprint(transcript, lines.selection.end) == lines.fingerprint &&
        clipFits(video);
  }

  /// Whether the kept clip is still inside [video].
  bool clipFits(SourceVideo video) => clip.end <= video.duration;

  /// A clip kept before the picture start was known may start too early.
  ClipRange _clipOn(SourceVideo video) =>
      clip.startingNoEarlierThan(video.pictureStart);

  /// The reel as it was left, on [transcript] when it had lines; call only
  /// when it [fits].
  ReelDraft restoredOnto(SourceVideo video, {Transcript? transcript}) {
    return ReelDraft(
      video: video,
      language: language,
      transcript: transcript,
      // The script may have grown since this was kept (it can be saved while
      // still being written): the lines inside the clip are the selected ones.
      selection: transcript == null
          ? const NoSelection()
          : linesInClip(transcript, _clipOn(video)),
      clip: _clipOn(video),
      frame: frame,
      caption: caption,
      linesEdited: linesEdited,
      lyricsShown: lyricsShown,
      fadeEnds: fadeEnds,
    );
  }

  /// What carries over when the lines can't (spec FR-24, M30): the clip and
  /// the crop when the clip still fits [video], and the caption's position,
  /// size and appearance. A clip past the video's end starts over as the whole video,
  /// with the crop stopped where it was at the old clip start.
  ReelDraft startOver(SourceVideo video) {
    final look = CaptionSettings(
      position: caption.position,
      size: caption.size,
      appearance: caption.appearance,
    );
    if (clipFits(video)) {
      return ReelDraft(
        video: video,
        language: language,
        clip: clip,
        frame: frame,
        caption: look,
        lyricsShown: lyricsShown,
        fadeEnds: fadeEnds,
      );
    }
    final stopped = ReelDraft(
      video: video,
      language: language,
      clip: clip,
      frame: frame,
    ).withMovingCropStopped();
    return ReelDraft(
      video: video,
      language: language,
      clip: ClipRange(start: Duration.zero, end: video.duration),
      frame: stopped.frame,
      caption: look,
      lyricsShown: lyricsShown,
      fadeEnds: fadeEnds,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FineTuneDraft &&
      other.videoId == videoId &&
      other.language == language &&
      other.lyricsShown == lyricsShown &&
      other.fadeEnds == fadeEnds &&
      other.lines == lines &&
      other.clip == clip &&
      other.frame == frame &&
      other.caption == caption &&
      other.linesEdited == linesEdited &&
      other.savedAt == savedAt;

  @override
  int get hashCode => Object.hash(
    videoId,
    language,
    lyricsShown,
    fadeEnds,
    lines,
    clip,
    frame,
    caption,
    linesEdited,
    savedAt,
  );
}

/// A kept fine-tune with its video, as a Recent row (spec FR-24).
@immutable
class SavedFineTune {
  const SavedFineTune({required this.video, required this.draft});

  final SourceVideo video;
  final FineTuneDraft draft;
}

KeptLines? _keptLines(ReelDraft draft) {
  final transcript = draft.transcript;
  final selection = draft.selection;
  if (transcript == null || selection is! RangeSelected) {
    return null;
  }
  return KeptLines(
    selection: selection,
    fingerprint: _fingerprint(transcript, selection.end),
  );
}

/// FNV-1a over the lines up to [lastLine]. `String.hashCode` is not stable
/// across runs, so it can't tell a changed script from a reopened one.
int _fingerprint(Transcript transcript, int lastLine) {
  var hash = 0x811c9dc5;
  for (final line in transcript.lines.take(lastLine + 1)) {
    final text =
        '${line.start.inMilliseconds}\t${line.end.inMilliseconds}'
        '\t${line.text}\n';
    for (final byte in utf8.encode(text)) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
  }
  return hash;
}
