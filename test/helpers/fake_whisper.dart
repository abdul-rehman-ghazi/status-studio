// TranscribeResult is the return type of WhisperController.transcribe but
// isn't exported, and the fake has to name it.
// ignore: implementation_imports
import 'package:whisper_ggml/src/models/whisper_result.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

/// Answers each chunk with one 2–4 s segment saying [text] (empty text
/// means silence), or null when [failing]. Never loads native code.
class FakeWhisperController extends WhisperController {
  FakeWhisperController({this.failing = false, this.text = 'words'});

  final bool failing;
  final String text;
  final languages = <String>[];
  final transcribedPaths = <String>[];
  var releaseCount = 0;

  @override
  Future<TranscribeResult?> transcribe({
    required WhisperModel model,
    required String audioPath,
    String lang = 'en',
    bool diarize = false,
    String? initialPrompt,
    bool noContext = false,
    int? maxContext,
    bool suppressNonSpeechTokens = false,
    bool withSegments = false,
    bool splitOnWord = false,
    bool keepModelLoaded = false,
    String? vadModelPath,
    int? vadSpeechPadMs,
    void Function(int percent)? onProgress,
  }) async {
    languages.add(lang);
    transcribedPaths.add(audioPath);
    if (failing) {
      return null;
    }
    return TranscribeResult(
      time: Duration.zero,
      transcription: WhisperTranscribeResponse(
        type: 'transcribe',
        text: text,
        segments: [
          WhisperTranscribeSegment(
            fromTs: const Duration(seconds: 2),
            toTs: const Duration(seconds: 4),
            text: text,
          ),
        ],
      ),
    );
  }

  @override
  Future<void> releaseModel() async => releaseCount++;
}
