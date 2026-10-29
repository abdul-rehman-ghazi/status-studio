import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/core/time_format.dart';

void main() {
  test('formats_clip_time_with_tenths', () {
    expect(formatClipTime(const Duration(seconds: 83)), '1:23.0');
  });

  test('formats_clip_time_with_hours', () {
    const time = Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 500);

    expect(formatClipTime(time), '1:02:03.5');
  });

  test('formats_timestamp_without_tenths', () {
    const time = Duration(seconds: 65, milliseconds: 900);

    expect(formatTimestamp(time), '1:05');
  });

  test('formats_timestamp_with_hours', () {
    const time = Duration(hours: 1, minutes: 2, seconds: 3);

    expect(formatTimestamp(time), '1:02:03');
  });

  test('formats_seconds_with_one_decimal', () {
    expect(formatSeconds(const Duration(milliseconds: 18500)), '18.5 s');
  });
}
