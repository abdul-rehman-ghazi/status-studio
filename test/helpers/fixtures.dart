import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/application/fake_script_pipeline.dart';
import 'package:status_studio/src/features/transcript/domain/line_selection.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

const sampleVideo = SourceVideo(
  videoId: 'dQw4w9WgXcQ',
  title: 'Sample video',
  duration: Duration(minutes: 6, seconds: 48),
);

final Transcript fixture = sampleTranscript;

/// A draft on the Script screen: video and transcript, nothing picked.
final ReelDraft scriptDraft = const ReelDraft(video: sampleVideo)
    .withTranscript(fixture);

/// A draft past the Script screen: lines 1–3 picked, clip 0:21.4 – 0:48.8.
final ReelDraft pickedDraft = scriptDraft.withSelection(
  const RangeSelected(1, 3),
);
