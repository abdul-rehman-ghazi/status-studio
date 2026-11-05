import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/clip/domain/lines_in_clip.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/style/domain/caption_settings.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

/// Fine-tune work kept to continue later (spec FR-24). The script itself is
/// not copied: [script] names it, and [scriptFingerprint] tells a changed
/// script apart.
@immutable
class FineTuneDraft {
  const FineTuneDraft({
    required this.script,
    required this.selection,
    required this.clip,
    required this.frame,
    required this.caption,
    required this.linesEdited,
    required this.scriptFingerprint,
    required this.savedAt,
  });

  /// Throws [StateError] when [draft] has no picked range or clip yet
  /// (see [canKeep]).
  factory FineTuneDraft.of(ReelDraft draft, {required DateTime savedAt}) {
    final transcript = draft.transcript;
    final selection = draft.selection;
    final clip = draft.clip;
    final video = draft.video;
    if (video == null ||
        transcript == null ||
        selection is! RangeSelected ||
        clip == null) {
      throw StateError('Nothing to keep before a range and clip are picked.');
    }
    return FineTuneDraft(
      script: TranscriptKey(videoId: video.videoId, language: draft.language),
      selection: selection,
      clip: clip,
      frame: draft.frame,
      caption: draft.caption,
      linesEdited: draft.linesEdited,
      scriptFingerprint: _fingerprint(transcript, selection.end),
      savedAt: savedAt,
    );
  }

  /// Whether [draft] has reached Fine-tune: a video, a script, a picked
  /// range and a clip.
  static bool canKeep(ReelDraft draft) =>
      draft.video != null &&
      draft.transcript != null &&
      draft.selection is RangeSelected &&
      draft.clip != null;

  final TranscriptKey script;
  final RangeSelected selection;
  final ClipRange clip;
  final FrameSettings frame;
  final CaptionSettings caption;
  final bool linesEdited;
  final int scriptFingerprint;
  final DateTime savedAt;

  /// Whether [transcript] is still the script this was picked from: the same
  /// lines up to the last picked one, with the clip inside [video].
  bool fits(SourceVideo video, Transcript transcript) {
    if (selection.end >= transcript.lines.length) {
      return false;
    }
    return _fingerprint(transcript, selection.end) == scriptFingerprint &&
        clip.end <= video.duration;
  }

  /// The reel as it was left, on [transcript]; call only when [fits].
  ReelDraft restoredOnto(SourceVideo video, Transcript transcript) {
    return ReelDraft(
      video: video,
      language: script.language,
      transcript: transcript,
      // The script may have grown since this was kept (it can be saved while
      // still being written): the lines inside the clip are the selected ones.
      selection: linesInClip(transcript, clip),
      clip: clip,
      frame: frame,
      caption: caption,
      linesEdited: linesEdited,
    );
  }

  /// What carries over when the lines can't (spec FR-24): size, fill, the
  /// crop where it was at the clip start, and the caption's position and
  /// size.
  ReelDraft startOver(SourceVideo video) {
    final stopped = ReelDraft(
      video: video,
      language: script.language,
      clip: clip,
      frame: frame,
    ).withMovingCropStopped();
    return ReelDraft(
      video: video,
      language: script.language,
      frame: stopped.frame,
      caption: CaptionSettings(position: caption.position, size: caption.size),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FineTuneDraft &&
      other.script == script &&
      other.selection == selection &&
      other.clip == clip &&
      other.frame == frame &&
      other.caption == caption &&
      other.linesEdited == linesEdited &&
      other.scriptFingerprint == scriptFingerprint &&
      other.savedAt == savedAt;

  @override
  int get hashCode => Object.hash(
    script,
    selection,
    clip,
    frame,
    caption,
    linesEdited,
    scriptFingerprint,
    savedAt,
  );
}

/// A kept fine-tune with its video, as a Recent row (spec FR-24).
@immutable
class SavedFineTune {
  const SavedFineTune({required this.video, required this.draft});

  final SourceVideo video;
  final FineTuneDraft draft;

  TranscriptKey get key => draft.script;
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
