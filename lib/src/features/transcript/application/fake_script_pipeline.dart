import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

const _sampleLineTexts = [
  'صبر کا پھل میٹھا ہوتا ہے',
  'علم بڑی دولت ہے',
  'محنت کامیابی کی کنجی ہے',
  'وقت کی قدر کرو',
  'سچ بولنا اچھی عادت ہے',
  'جیسی کرنی ویسی بھرنی',
  'اتفاق میں برکت ہے',
  'نیکی کر دریا میں ڈال',
  'دیر آید درست آید',
];

/// Line n starts at 12.0 + 9.4·n s and lasts 8.6 s.
final Transcript sampleTranscript = Transcript(
  languageCode: ScriptLanguage.urdu.whisperCode,
  lines: [
    for (final (index, text) in _sampleLineTexts.indexed)
      TranscriptLine(
        index: index,
        text: text,
        start: Duration(milliseconds: 12000 + 9400 * index),
        end: Duration(milliseconds: 12000 + 9400 * index + 8600),
      ),
  ],
);

/// Walks through the stages over about four seconds, writing the sample
/// lines one by one while transcribing.
class FakeScriptPipeline implements ScriptPipeline {
  const FakeScriptPipeline({this.step = const Duration(milliseconds: 300)});

  final Duration step;

  @override
  Stream<ScriptProgress> run(SourceVideo video, ScriptLanguage language) {
    final events = _progressEvents();
    // Stream.periodic cancels its timer when the listener cancels.
    return Stream.periodic(step, (tick) => events[tick]).take(events.length);
  }
}

List<ScriptProgress> _progressEvents() {
  final lines = sampleTranscript.lines;
  Transcript linesUpTo(int count) =>
      sampleTranscript.copyWith(lines: lines.sublist(0, count));
  return [
    ScriptProgress(
      stage: ScriptStage.downloadingAudio,
      fraction: 0,
      transcript: linesUpTo(0),
    ),
    ScriptProgress(
      stage: ScriptStage.detectingLanguage,
      fraction: 0.15,
      transcript: linesUpTo(0),
    ),
    for (var count = 1; count <= lines.length; count++)
      ScriptProgress(
        stage: ScriptStage.transcribing,
        fraction: 0.25 + 0.7 * count / lines.length,
        transcript: linesUpTo(count),
      ),
    ScriptProgress(
      stage: ScriptStage.done,
      fraction: 1,
      transcript: sampleTranscript,
    ),
  ];
}
