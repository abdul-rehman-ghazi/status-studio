import 'package:status_studio/src/features/export/domain/render_errors.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/style/domain/translation_errors.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';

/// Spec §8 copy for a failure from the data layer.
String errorMessageFor(Object error) {
  return switch (error) {
    VideoUnavailableException() => "This video can't be downloaded.",
    OfflineException() => "You're offline. Connect and try again.",
    YouTubeChangedException() =>
      "Couldn't read this video from YouTube. Try again later.",
    InsufficientStorageException() => 'Not enough space on your phone.',
    ModelDownloadException() => "Couldn't download the speech model.",
    ModelDownloadStoppedException() => 'The speech model download was stopped.',
    NoSpeechFoundException() => 'No speech found in this video.',
    RenderFailedException() => "Couldn't make the reel.",
    TranslationPackMissingException() => 'English needs a one-time download.',
    _ => 'Something went wrong. Try again.',
  };
}
