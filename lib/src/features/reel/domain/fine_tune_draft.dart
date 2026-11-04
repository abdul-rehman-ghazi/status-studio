import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/style/domain/caption_settings.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';

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

  final TranscriptKey script;
  final RangeSelected selection;
  final ClipRange clip;
  final FrameSettings frame;
  final CaptionSettings caption;
  final bool linesEdited;
  final int scriptFingerprint;
  final DateTime savedAt;

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
