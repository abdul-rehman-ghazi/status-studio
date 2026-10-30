import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';

/// Spec §8 copy for a failure from the data layer.
String errorMessageFor(Object error) {
  return switch (error) {
    VideoUnavailableException() => "This video can't be downloaded.",
    OfflineException() => "You're offline. Connect and try again.",
    InsufficientStorageException() => 'Not enough space on your phone.',
    ModelDownloadException() => "Couldn't download the speech model.",
    NoSpeechFoundException() => 'No speech found in this video.',
    _ => 'Something went wrong. Try again.',
  };
}
