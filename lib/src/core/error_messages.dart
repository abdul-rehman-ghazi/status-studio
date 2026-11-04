import 'package:status_studio/src/features/export/domain/render_errors.dart';
import 'package:status_studio/src/features/lyrics/domain/lyrics_match.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/style/domain/translation_errors.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';
import 'package:status_studio/src/features/transcript/domain/script_exchange.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';

/// Spec §8 copy for a failure from the data layer.
String errorMessageFor(Object error) {
  return switch (error) {
    VideoUnavailableException() => "This video can't be downloaded.",
    OfflineException() ||
    GroqOfflineException() => "You're offline. Connect and try again.",
    YouTubeChangedException() =>
      "Couldn't read this video from YouTube. Try again later.",
    InsufficientStorageException() => 'Not enough space on your phone.',
    NoSpeechFoundException() => 'No speech found in this video.',
    NoGroqKeyException() => 'Writing a script needs a free Groq key.',
    GroqKeyRejectedException() => "Groq didn't accept your API key.",
    GroqRateLimitedException(:final retryAfter) => _groqLimitMessage(
      retryAfter,
    ),
    GroqFailedException() => "Groq couldn't write this script.",
    LyricsNotFoundException() =>
      "Couldn't find the lyrics for this video. The script stays as it is.",
    NoScriptRowsException() =>
      "Couldn't find script lines in what you pasted. Copy the AI's whole "
          'reply and try again.',
    TooManyLinesForAiException() =>
      'Too many lines for an AI to check. Tap the start and end lines of '
          'your clip first.',
    RenderFailedException() => "Couldn't make the reel.",
    TranslationPackMissingException() => 'English needs a one-time download.',
    _ => 'Something went wrong. Try again.',
  };
}

String _groqLimitMessage(Duration retryAfter) {
  final minutes = (retryAfter.inSeconds / 60).ceil();
  return "Groq's free limit is used up for now. Try again in $minutes min.";
}
