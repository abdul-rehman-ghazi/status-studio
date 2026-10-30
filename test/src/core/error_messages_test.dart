import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/transcript/domain/transcript_errors.dart';

void main() {
  test('maps_no_speech', () {
    expect(
      errorMessageFor(const NoSpeechFoundException()),
      'No speech found in this video.',
    );
  });

  test('maps_offline', () {
    expect(
      errorMessageFor(const OfflineException('x')),
      "You're offline. Connect and try again.",
    );
  });

  test('maps_model_download', () {
    expect(
      errorMessageFor(const ModelDownloadException('x')),
      "Couldn't download the speech model.",
    );
  });

  test('maps_unavailable', () {
    expect(
      errorMessageFor(const VideoUnavailableException('x')),
      "This video can't be downloaded.",
    );
  });

  test('maps_storage', () {
    expect(
      errorMessageFor(const InsufficientStorageException('x')),
      'Not enough space on your phone.',
    );
  });
}
