import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/application/fake_script_pipeline.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

const sampleVideo = SourceVideo(
  videoId: 'dQw4w9WgXcQ',
  title: 'Sample video',
  channel: 'Sample channel',
  duration: Duration(minutes: 6, seconds: 48),
);

final Transcript fixture = sampleTranscript;
