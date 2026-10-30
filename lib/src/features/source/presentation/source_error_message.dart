import 'package:status_studio/src/features/source/domain/source_errors.dart';

/// Spec §8 copy for a failure while getting a video.
String sourceErrorMessage(Object error) {
  return switch (error) {
    OfflineException() => "You're offline. Connect and try again.",
    InsufficientStorageException() => 'Not enough space on your phone.',
    _ => "This video can't be downloaded.",
  };
}
