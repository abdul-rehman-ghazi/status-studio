import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/core/ffmpeg/local_video_facts.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

String probeJson({
  Map<String, Object?>? video,
  Map<String, Object?>? audio,
  Map<String, Object?>? format,
}) {
  return jsonEncode({
    'streams': [
      if (video != null) {'codec_type': 'video', ...video},
      if (audio != null) {'codec_type': 'audio', 'codec_name': 'aac', ...audio},
    ],
    'format': format ?? {'duration': '69.000000', 'size': '61000000'},
  });
}

const landscape = {'width': 1920, 'height': 1080, 'duration': '69.000000'};

void main() {
  test('landscape_video_with_audio_reads_every_fact', () {
    final facts = parseLocalVideoFacts(
      probeJson(video: landscape, audio: const {}),
    );

    expect(
      (
        facts.duration,
        facts.sizeBytes,
        facts.rotationDegrees,
        facts.storedWidth,
        facts.storedHeight,
        facts.hasAudio,
      ),
      (const Duration(seconds: 69), 61000000, 0, 1920, 1080, true),
    );
  });

  test('duration_keeps_milliseconds', () {
    final facts = parseLocalVideoFacts(
      probeJson(
        video: landscape,
        format: const {'duration': '12.345000', 'size': '10'},
      ),
    );

    expect(facts.duration, const Duration(milliseconds: 12345));
  });

  test('side_data_rotation_minus_90_is_90_degrees_clockwise', () {
    final facts = parseLocalVideoFacts(
      probeJson(
        video: {
          ...landscape,
          'side_data_list': [
            {'side_data_type': 'Display Matrix', 'rotation': -90},
          ],
        },
        audio: const {},
      ),
    );

    expect(facts.rotationDegrees, 90);
  });

  test('side_data_rotation_90_is_270_degrees_clockwise', () {
    final facts = parseLocalVideoFacts(
      probeJson(
        video: {
          ...landscape,
          'side_data_list': [
            {'side_data_type': 'Display Matrix', 'rotation': 90},
          ],
        },
        audio: const {},
      ),
    );

    expect(facts.rotationDegrees, 270);
  });

  test('side_data_rotation_180_stays_180', () {
    final facts = parseLocalVideoFacts(
      probeJson(
        video: {
          ...landscape,
          'side_data_list': [
            {'side_data_type': 'Display Matrix', 'rotation': -180},
          ],
        },
        audio: const {},
      ),
    );

    expect(facts.rotationDegrees, 180);
  });

  test('side_data_without_rotation_is_ignored', () {
    final facts = parseLocalVideoFacts(
      probeJson(
        video: {
          ...landscape,
          'side_data_list': [
            {'side_data_type': 'Stereo 3D'},
          ],
        },
        audio: const {},
      ),
    );

    expect(facts.rotationDegrees, 0);
  });

  test('older_rotate_tag_is_read_when_side_data_is_absent', () {
    final facts = parseLocalVideoFacts(
      probeJson(
        video: {
          ...landscape,
          'tags': {'rotate': '90'},
        },
        audio: const {},
      ),
    );

    expect(facts.rotationDegrees, 90);
  });

  test('rotation_off_the_quarter_turns_counts_as_none', () {
    final facts = parseLocalVideoFacts(
      probeJson(
        video: {
          ...landscape,
          'tags': {'rotate': '45'},
        },
        audio: const {},
      ),
    );

    expect(facts.rotationDegrees, 0);
  });

  test('video_without_audio_stream_reports_no_audio', () {
    final facts = parseLocalVideoFacts(probeJson(video: landscape));

    expect(facts.hasAudio, isFalse);
  });

  test('require_audio_throws_unreadable_when_there_is_no_audio', () {
    final facts = parseLocalVideoFacts(probeJson(video: landscape));

    expect(facts.requireAudio, throwsA(isA<VideoUnreadableException>()));
  });

  test('require_audio_returns_the_facts_when_audio_exists', () {
    final facts = parseLocalVideoFacts(
      probeJson(video: landscape, audio: const {}),
    );

    expect(facts.requireAudio(), same(facts));
  });

  test('file_without_video_stream_throws_unreadable', () {
    expect(
      () => parseLocalVideoFacts(probeJson(audio: const {})),
      throwsA(isA<VideoUnreadableException>()),
    );
  });

  test('video_stream_without_size_throws_unreadable', () {
    expect(
      () => parseLocalVideoFacts(probeJson(video: const {})),
      throwsA(isA<VideoUnreadableException>()),
    );
  });

  test('missing_duration_throws_unreadable', () {
    expect(
      () => parseLocalVideoFacts(
        probeJson(video: const {'width': 10, 'height': 10}, format: {}),
      ),
      throwsA(isA<VideoUnreadableException>()),
    );
  });

  test('video_stream_duration_is_used_when_format_has_none', () {
    final facts = parseLocalVideoFacts(
      probeJson(video: landscape, format: const {'size': '5'}),
    );

    expect(facts.duration, const Duration(seconds: 69));
  });

  test('broken_json_throws_unreadable', () {
    expect(
      () => parseLocalVideoFacts('{"streams": ['),
      throwsA(isA<VideoUnreadableException>()),
    );
  });

  test('empty_output_throws_unreadable', () {
    expect(
      () => parseLocalVideoFacts(''),
      throwsA(isA<VideoUnreadableException>()),
    );
  });

  test('json_that_is_not_an_object_throws_unreadable', () {
    expect(
      () => parseLocalVideoFacts('[]'),
      throwsA(isA<VideoUnreadableException>()),
    );
  });

  test('cover_art_stream_is_not_a_video_stream', () {
    final json = jsonEncode({
      'streams': [
        {
          'codec_type': 'video',
          'width': 500,
          'height': 500,
          'disposition': {'attached_pic': 1},
        },
        {'codec_type': 'audio'},
      ],
      'format': {'duration': '10', 'size': '100'},
    });

    expect(
      () => parseLocalVideoFacts(json),
      throwsA(isA<VideoUnreadableException>()),
    );
  });

  test('real_video_stream_after_cover_art_is_chosen', () {
    final json = jsonEncode({
      'streams': [
        {
          'codec_type': 'video',
          'width': 500,
          'height': 500,
          'disposition': {'attached_pic': 1},
        },
        {
          'codec_type': 'video',
          'width': 1280,
          'height': 720,
          'disposition': {'attached_pic': 0},
        },
        {'codec_type': 'audio'},
      ],
      'format': {'duration': '10', 'size': '100'},
    });

    final facts = parseLocalVideoFacts(json);

    expect((facts.storedWidth, facts.storedHeight), (1280, 720));
  });

  test('zero_width_throws_unreadable', () {
    expect(
      () => parseLocalVideoFacts(
        probeJson(video: const {'width': 0, 'height': 10}),
      ),
      throwsA(isA<VideoUnreadableException>()),
    );
  });

  test('zero_height_throws_unreadable', () {
    expect(
      () => parseLocalVideoFacts(
        probeJson(video: const {'width': 10, 'height': 0}),
      ),
      throwsA(isA<VideoUnreadableException>()),
    );
  });

  test('zero_size_throws_unreadable', () {
    expect(
      () => parseLocalVideoFacts(
        probeJson(
          video: landscape,
          format: const {'duration': '5', 'size': '0'},
        ),
      ),
      throwsA(isA<VideoUnreadableException>()),
    );
  });

  test('zero_format_duration_falls_back_to_video_stream_duration', () {
    final facts = parseLocalVideoFacts(
      probeJson(
        video: landscape,
        format: const {'duration': '0.000000', 'size': '5'},
      ),
    );

    expect(facts.duration, const Duration(seconds: 69));
  });

  test('na_format_duration_falls_back_to_video_stream_duration', () {
    final facts = parseLocalVideoFacts(
      probeJson(
        video: landscape,
        format: const {'duration': 'N/A', 'size': '5'},
      ),
    );

    expect(facts.duration, const Duration(seconds: 69));
  });

  test('na_duration_everywhere_throws_unreadable', () {
    expect(
      () => parseLocalVideoFacts(
        probeJson(
          video: const {'width': 10, 'height': 10, 'duration': 'N/A'},
          format: const {'duration': 'N/A', 'size': '5'},
        ),
      ),
      throwsA(isA<VideoUnreadableException>()),
    );
  });

  test('side_data_rotation_wins_over_rotate_tag', () {
    final facts = parseLocalVideoFacts(
      probeJson(
        video: {
          ...landscape,
          'tags': {'rotate': '90'},
          'side_data_list': [
            {'side_data_type': 'Display Matrix', 'rotation': -180},
          ],
        },
      ),
    );

    expect(facts.rotationDegrees, 180);
  });

  test('rotate_tag_of_450_normalises_to_90', () {
    final facts = parseLocalVideoFacts(
      probeJson(
        video: {
          ...landscape,
          'tags': {'rotate': '450'},
        },
      ),
    );

    expect(facts.rotationDegrees, 90);
  });

  test('rotate_tag_of_minus_270_normalises_to_90', () {
    final facts = parseLocalVideoFacts(
      probeJson(
        video: {
          ...landscape,
          'tags': {'rotate': '-270'},
        },
      ),
    );

    expect(facts.rotationDegrees, 90);
  });

  test('width_and_height_given_as_strings_are_read', () {
    final facts = parseLocalVideoFacts(
      probeJson(
        video: const {'width': '640', 'height': '360', 'duration': '1'},
      ),
    );

    expect((facts.storedWidth, facts.storedHeight), (640, 360));
  });

  test('json_object_in_returns_clean_json_unchanged', () {
    expect(jsonObjectIn('{"a": 1}'), '{"a": 1}');
  });

  test('json_object_in_cuts_log_lines_around_the_object', () {
    const output = 'warning: odd\n{"a": {"b": 2}}\n[error] moov atom\n';

    expect(jsonObjectIn(output), '{"a": {"b": 2}}');
  });

  test('json_object_in_throws_unreadable_without_braces', () {
    expect(
      () => jsonObjectIn('no json here'),
      throwsA(isA<VideoUnreadableException>()),
    );
  });

  test('displayed_size_keeps_stored_size_when_not_rotated', () {
    const facts = LocalVideoFacts(
      duration: Duration(seconds: 1),
      sizeBytes: 1,
      rotationDegrees: 180,
      storedWidth: 1920,
      storedHeight: 1080,
      hasAudio: true,
    );

    expect((facts.displayedWidth, facts.displayedHeight), (1920, 1080));
  });

  test('displayed_size_swaps_width_and_height_for_quarter_turns', () {
    const facts = LocalVideoFacts(
      duration: Duration(seconds: 1),
      sizeBytes: 1,
      rotationDegrees: 270,
      storedWidth: 1920,
      storedHeight: 1080,
      hasAudio: true,
    );

    expect((facts.displayedWidth, facts.displayedHeight), (1080, 1920));
  });

  test('probe_arguments_ask_for_streams_and_format_as_json', () {
    expect(localVideoProbeArguments('clip.mp4'), [
      '-v',
      'error',
      '-show_streams',
      '-show_format',
      '-of',
      'json',
      'clip.mp4',
    ]);
  });
}
