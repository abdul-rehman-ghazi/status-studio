import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/clip/domain/clip_window.dart';
import 'package:status_studio/src/features/export/domain/render_spec.dart';
import 'package:status_studio/src/features/source/domain/clip_source.dart';
import 'package:status_studio/src/features/style/domain/crop_path.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';

Duration at(int minutes, int seconds) =>
    Duration(minutes: minutes, seconds: seconds);

RenderJob jobWith(FrameSettings frame) => RenderJob(
  source: ClipSource(
    file: File('/cache/clip.mp4'),
    offset: at(0, 55),
    window: ClipWindow(start: at(0, 55), end: at(1, 25)),
  ),
  clip: ClipRange(start: at(1, 0), end: at(1, 20)),
  frame: frame,
  sourceSize: const OutputSize(1920, 1080),
  overlayPath: '/cache/overlay.png',
  outputPath: '/files/reel.mp4',
);

void main() {
  test('crop_spec_has_ndc_crop_and_no_blur', () {
    final spec = renderSpecFor(jobWith(const FrameSettings()));

    expect(
      (spec['fill'], spec.containsKey('crop'), spec.containsKey('blurSigma')),
      ('crop', true, false),
    );
  });

  test('blur_spec_has_sigma_and_no_crop', () {
    final spec = renderSpecFor(
      jobWith(const FrameSettings(fill: FillMode.blur)),
    );

    expect(
      (spec['fill'], spec['blurSigma'], spec.containsKey('crop')),
      ('blur', 20.0, false),
    );
  });

  test('landscape_spec_has_fill_none', () {
    final spec = renderSpecFor(
      jobWith(const FrameSettings(preset: AspectPreset.landscape16x9)),
    );

    expect(spec['fill'], 'none');
  });

  test('clip_times_are_relative_to_source_offset', () {
    final spec = renderSpecFor(jobWith(const FrameSettings()));

    expect((spec['clipStartMs'], spec['clipEndMs']), (5000, 25000));
  });

  test('free_crop_outputs_free_size', () {
    final spec = renderSpecFor(
      jobWith(const FrameSettings(preset: AspectPreset.free)),
    );

    expect((spec['outputWidth'], spec['outputHeight']), (768, 992));
  });

  test('crop_is_sent_as_ndc', () {
    final spec = renderSpecFor(jobWith(const FrameSettings()));

    final crop = spec['crop']! as Map<String, Object?>;
    expect(crop['left'], closeTo(-0.315625, 1e-9));
  });

  group('moving crop', () {
    // The clip starts at 1:00 in video time.
    final moving = FrameSettings(
      cropPath: CropPath([
        CropKeyframe(
          time: at(1, 0),
          anchor: const CropAnchor(x: 0, y: 0.5),
          arrival: CropArrival.glide,
        ),
        CropKeyframe(
          time: at(1, 8),
          anchor: const CropAnchor(x: 1, y: 0.5),
          arrival: CropArrival.cut,
        ),
      ]),
    );

    test('keyframes_replace_the_fixed_crop', () {
      final spec = renderSpecFor(jobWith(moving));

      expect(spec.containsKey('crop'), isFalse);
      expect(spec['cropKeyframes'], hasLength(2));
    });

    test('keyframe_times_count_from_the_clip_start', () {
      final spec = renderSpecFor(jobWith(moving));

      final second =
          (spec['cropKeyframes']! as List<Object?>)[1]! as Map<String, Object?>;
      expect((second['timeMs'], second['arrival']), (8000, 'cut'));
    });

    test('each_keyframe_is_an_ndc_rectangle', () {
      final spec = renderSpecFor(jobWith(moving));

      final first =
          (spec['cropKeyframes']! as List<Object?>).first!
              as Map<String, Object?>;
      expect(first['left'], -1.0);
    });

    test('blur_has_no_keyframes', () {
      final spec = renderSpecFor(jobWith(moving.copyWith(fill: FillMode.blur)));

      expect(spec.containsKey('cropKeyframes'), isFalse);
    });
  });

  test('spec_names_h264_and_aac', () {
    final spec = renderSpecFor(jobWith(const FrameSettings()));

    expect(
      (spec['videoMimeType'], spec['audioMimeType']),
      ('video/avc', 'audio/mp4a-latm'),
    );
  });

  test('blur_sharp_frame_fits_output_width', () {
    final spec = renderSpecFor(
      jobWith(const FrameSettings(fill: FillMode.blur)),
    );

    // 1920 × 1080 fitted to a 1080-wide story is 607.5 of its 1920 height.
    expect(
      [spec['sharpScaleX'], spec['sharpScaleY']],
      [1.0, closeTo(607.5 / 1920, 1e-9)],
    );
  });

  test('blur_sharp_frame_of_tall_source_fits_output_height', () {
    final job = jobWith(const FrameSettings(fill: FillMode.blur));
    final tall = RenderJob(
      source: job.source,
      clip: job.clip,
      frame: const FrameSettings(
        preset: AspectPreset.square1x1,
        fill: FillMode.blur,
      ),
      sourceSize: const OutputSize(720, 1280),
      overlayPath: job.overlayPath,
      outputPath: job.outputPath,
    );

    final spec = renderSpecFor(tall);

    expect(
      [spec['sharpScaleX'], spec['sharpScaleY']],
      [closeTo(720 / 1280, 1e-9), 1.0],
    );
  });

  test('spec_lists_caption_cues_in_milliseconds', () {
    final job = RenderJob(
      source: jobWith(const FrameSettings()).source,
      clip: ClipRange(start: at(1, 0), end: at(1, 20)),
      frame: const FrameSettings(),
      sourceSize: const OutputSize(1920, 1080),
      overlayPath: '/cache/overlay.png',
      outputPath: '/files/reel.mp4',
      captionCues: const [
        RenderCue(
          start: Duration(seconds: 2),
          end: Duration(milliseconds: 6500),
          overlayPath: '/cache/overlay_1.png',
        ),
      ],
    );

    expect(renderSpecFor(job)['captionCues'], [
      {'startMs': 2000, 'endMs': 6500, 'path': '/cache/overlay_1.png'},
    ]);
  });
}
