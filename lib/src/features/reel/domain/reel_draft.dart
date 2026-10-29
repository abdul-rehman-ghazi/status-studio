import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/style/domain/caption_settings.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
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
  });

  final SourceVideo? video;
  final ScriptLanguage language;
  final Transcript? transcript;
  final LineSelection selection;
  final ClipRange? clip;
  final FrameSettings frame;
  final CaptionSettings caption;

  /// A new transcript invalidates the old selection and clip.
  ReelDraft withTranscript(Transcript transcript) {
    return ReelDraft(
      video: video,
      language: language,
      transcript: transcript,
      frame: frame,
      caption: caption,
    );
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
        frame: frame,
        caption: caption,
      );
    }
    return copyWith(
      selection: selection,
      clip: ClipRange.fromLines(transcript, selection),
      caption: caption.copyWith(
        variant: CaptionVariant.original,
        text: _selectedText(transcript, selection),
      ),
    );
  }

  ReelDraft copyWith({
    SourceVideo? video,
    ScriptLanguage? language,
    Transcript? transcript,
    LineSelection? selection,
    ClipRange? clip,
    FrameSettings? frame,
    CaptionSettings? caption,
  }) {
    return ReelDraft(
      video: video ?? this.video,
      language: language ?? this.language,
      transcript: transcript ?? this.transcript,
      selection: selection ?? this.selection,
      clip: clip ?? this.clip,
      frame: frame ?? this.frame,
      caption: caption ?? this.caption,
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
      other.caption == caption;

  @override
  int get hashCode =>
      Object.hash(video, language, transcript, selection, clip, frame, caption);
}

String _selectedText(Transcript transcript, RangeSelected selection) {
  return transcript.lines
      .sublist(selection.start, selection.end + 1)
      .map((line) => line.text)
      .join('\n');
}
