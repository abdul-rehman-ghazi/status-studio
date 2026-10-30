import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/source/data/youtube_video_source.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

void main() {
  test('maps_unavailable_errors', () {
    final errors = [
      yt.VideoUnavailableException('removed'),
      yt.VideoUnplayableException('age restricted'),
      yt.VideoRequiresPurchaseException(yt.VideoId('dQw4w9WgXcQ')),
    ];

    expect(
      errors.map(mapYouTubeError),
      everyElement(isA<VideoUnavailableException>()),
    );
  });

  test('maps_socket_errors_to_offline', () {
    final mapped = mapYouTubeError(const SocketException('Failed host lookup'));

    expect(mapped, isA<OfflineException>());
  });

  test('maps_http_errors_to_offline', () {
    final mapped = mapYouTubeError(const HttpException('Connection closed'));

    expect(mapped, isA<OfflineException>());
  });

  test('maps_no_space_errors_to_insufficient_storage', () {
    const error = FileSystemException(
      'Write failed',
      '/tmp/x',
      OSError('No space left on device', 28),
    );

    expect(mapYouTubeError(error), isA<InsufficientStorageException>());
  });

  test('passes_other_errors_through', () {
    final error = StateError('bug');

    expect(mapYouTubeError(error), same(error));
  });
}
