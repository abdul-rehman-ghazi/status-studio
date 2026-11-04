import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/core/ffmpeg/frame_arguments.dart';

FrameSampling samplingWith({
  Duration start = const Duration(seconds: 5),
  Duration end = const Duration(seconds: 35),
  double framesPerSecond = 4,
}) => FrameSampling(
  inputPath: '/cache/clip.mp4',
  outputDirectory: '/cache/frames',
  cutsPath: '/cache/frames/cuts.txt',
  start: start,
  end: end,
  framesPerSecond: framesPerSecond,
);

void main() {
  group('sampledFramesArguments', () {
    test('cuts_the_range_in_file_time', () {
      final arguments = sampledFramesArguments(samplingWith());

      expect(arguments.sublist(0, 6), [
        '-y',
        '-ss',
        '5.000',
        '-to',
        '35.000',
        '-i',
      ]);
    });

    test('drops_audio_and_subtitles', () {
      final arguments = sampledFramesArguments(samplingWith());

      expect(arguments, containsAll(['-an', '-sn']));
    });

    test('scales_lists_cuts_then_samples_in_one_filter_chain', () {
      final arguments = sampledFramesArguments(samplingWith());

      final filters = arguments[arguments.indexOf('-vf') + 1];
      expect(
        filters,
        'scale=640:640:force_original_aspect_ratio=decrease,'
        'scdet=threshold=10,'
        'metadata=mode=print:key=lavfi.scd.time:file=/cache/frames/cuts.txt,'
        'fps=4',
      );
    });

    test('writes_numbered_jpegs_from_zero', () {
      final arguments = sampledFramesArguments(samplingWith());

      expect(arguments.sublist(arguments.length - 3), [
        '-start_number',
        '0',
        '/cache/frames/frame%04d.jpg',
      ]);
    });

    test('keeps_every_sampled_frame', () {
      final arguments = sampledFramesArguments(samplingWith());

      expect(
        arguments.sublist(
          arguments.indexOf('-fps_mode'),
          arguments.indexOf('-fps_mode') + 2,
        ),
        ['-fps_mode', 'passthrough'],
      );
    });

    test('a_fractional_rate_is_written_plainly', () {
      final arguments = sampledFramesArguments(
        samplingWith(framesPerSecond: 2.5),
      );

      expect(arguments[arguments.indexOf('-vf') + 1], endsWith('fps=2.5'));
    });

    test('a_path_with_a_colon_is_escaped_in_the_filter', () {
      const sampling = FrameSampling(
        inputPath: '/cache/clip.mp4',
        outputDirectory: '/cache/frames',
        cutsPath: r'C:\cache\cuts.txt',
        start: Duration.zero,
        end: Duration(seconds: 10),
        framesPerSecond: 4,
      );

      final filters = sampledFramesArguments(sampling);

      expect(
        filters[filters.indexOf('-vf') + 1],
        contains(r'file=C\:\\cache\\cuts.txt'),
      );
    });
  });

  group('samplingRateFor', () {
    test('a_short_clip_is_sampled_four_times_a_second', () {
      expect(samplingRateFor(const Duration(seconds: 30)), 4);
    });

    test('a_long_clip_is_sampled_less_to_cap_the_frames_at_240', () {
      expect(samplingRateFor(const Duration(seconds: 100)), 2.4);
    });

    test('a_very_long_clip_is_never_sampled_below_two_a_second', () {
      expect(samplingRateFor(const Duration(seconds: 300)), 2);
    });

    test('a_clip_of_exactly_sixty_seconds_keeps_four_a_second', () {
      expect(samplingRateFor(const Duration(seconds: 60)), 4);
    });
  });

  group('parseSceneCuts', () {
    test('reads_the_times_ffmpeg_prints', () {
      const text = '''
frame:12   pts:12345   pts_time:3.086
lavfi.scd.time=3.086
frame:40   pts:41000   pts_time:10.25
lavfi.scd.time=10.25
''';

      expect(parseSceneCuts(text), [
        const Duration(milliseconds: 3086),
        const Duration(milliseconds: 10250),
      ]);
    });

    test('ignores_lines_that_are_not_cut_times', () {
      expect(parseSceneCuts('frame:1 pts:2\nnothing here\n'), isEmpty);
    });

    test('an_empty_file_has_no_cuts', () {
      expect(parseSceneCuts(''), isEmpty);
    });
  });

  group('frameTime', () {
    test('frame_k_is_k_over_the_rate_after_the_clip_start', () {
      expect(
        frameTime(
          clipStart: const Duration(seconds: 20),
          index: 6,
          framesPerSecond: 4,
        ),
        const Duration(milliseconds: 21500),
      );
    });
  });
}
