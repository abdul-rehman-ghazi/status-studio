import 'package:status_studio/src/features/export/domain/render_errors.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/style/domain/follow_errors.dart';
import 'package:status_studio/src/features/style/domain/translation_errors.dart';
import 'package:status_studio/src/features/transcript/domain/groq_errors.dart';
import 'package:status_studio/src/features/transcript/domain/script_exchange.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';

/// Spec §8 copy for a failure from the data layer.
String errorMessageFor(Object error) {
  return switch (error) {
    OfflineException() ||
    GroqOfflineException() => "You're offline. Connect and try again.",
    InsufficientStorageException() => 'Not enough space on your phone.',
    VideoUnreadableException() => "Can't read this video.",
    KeptVideoMissingException() => 'Video not found, choose it again.',
    NoSpeechFoundException() => 'No speech found in this video.',
    NoGroqKeyException() => 'Writing a script needs a free Groq key.',
    GroqKeyRejectedException() => "Groq didn't accept your API key.",
    GroqRateLimitedException(:final retryAfter) => _groqLimitMessage(
      retryAfter,
    ),
    GroqFailedException() => "Groq couldn't write this script.",
    NoScriptRowsException() =>
      "Couldn't find script lines in what you pasted. Copy the AI's whole "
          'reply and try again.',
    TooManyLinesForAiException() =>
      'Too many lines for an AI to check. Shorten the clip on the next step '
          'first.',
    RenderFailedException() => "Couldn't make the reel.",
    TranslationPackMissingException() => 'English needs a one-time download.',
    NoSubjectFoundException() =>
      'No person found in this clip. The crop stays where it is.',
    FollowFailedException() => "Couldn't follow the person. Try again.",
    _ => 'Something went wrong. Try again.',
  };
}

String _groqLimitMessage(Duration retryAfter) {
  final minutes = (retryAfter.inSeconds / 60).ceil();
  return "Groq's free limit is used up for now. Try again in $minutes min.";
}
