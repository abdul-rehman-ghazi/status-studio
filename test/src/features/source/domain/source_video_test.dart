import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';

import '../../../../helpers/fixtures.dart';

void main() {
  test('json_round_trips', () {
    final json = sampleVideo.toJson();

    expect(SourceVideo.fromJson(json), sampleVideo);
  });

  test('malformed_json_throws_format_exception', () {
    expect(
      () => SourceVideo.fromJson(const {'videoId': 'dQw4w9WgXcQ'}),
      throwsFormatException,
    );
  });
}
