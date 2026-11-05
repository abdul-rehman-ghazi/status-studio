import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';

import '../../../../helpers/fixtures.dart';

void main() {
  test('json_round_trips', () {
    final json = sampleVideo.toJson();

    expect(SourceVideo.fromJson(json), sampleVideo);
  });

  test('json_has_no_channel', () {
    final json = sampleVideo.toJson();

    expect(json.containsKey('channel'), isFalse);
  });

  test('old_json_with_channel_is_read_without_it', () {
    final oldJson = {...sampleVideo.toJson(), 'channel': 'Heera Gold'};

    expect(SourceVideo.fromJson(oldJson), sampleVideo);
  });

  test('malformed_json_throws_format_exception', () {
    expect(
      () => SourceVideo.fromJson(const {'videoId': 'dQw4w9WgXcQ'}),
      throwsFormatException,
    );
  });
}
