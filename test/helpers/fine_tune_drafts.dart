import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/reel/domain/fine_tune_draft.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/style/domain/caption_settings.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

FineTuneDraft fineTuneDraftFixture({
  String videoId = 'abc123',
  ScriptLanguage language = ScriptLanguage.urdu,
  DateTime? savedAt,
}) {
  return FineTuneDraft(
    script: TranscriptKey(videoId: videoId, language: language),
    selection: const RangeSelected(1, 3),
    clip: const ClipRange(
      start: Duration(seconds: 2),
      end: Duration(seconds: 8),
    ),
    frame: const FrameSettings(),
    caption: const CaptionSettings(text: 'do\nteen\nchar'),
    linesEdited: false,
    scriptFingerprint: 331970932,
    savedAt: savedAt ?? DateTime.utc(2026, 11, 4, 10),
  );
}

/// A reel at Fine-tune: lines 1–3 of five picked, the clip set.
ReelDraft pickedReelDraft({String videoId = 'abc123'}) {
  return ReelDraft(
    video: SourceVideo(
      videoId: videoId,
      title: 'A song',
      channel: 'A channel',
      duration: const Duration(seconds: 60),
    ),
    language: ScriptLanguage.urdu,
    transcript: Transcript(
      languageCode: 'ur',
      lines: [
        for (var index = 0; index < 5; index++)
          TranscriptLine(
            index: index,
            text: ['ek', 'do', 'teen', 'char', 'paanch'][index],
            start: Duration(seconds: index * 2),
            end: Duration(seconds: index * 2 + 2),
          ),
      ],
    ),
  ).withSelection(const RangeSelected(1, 3));
}
