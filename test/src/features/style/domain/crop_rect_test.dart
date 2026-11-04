import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/style/domain/crop_path.dart';
import 'package:status_studio/src/features/style/domain/crop_rect.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';

const fullHd = OutputSize(1920, 1080);

const story = FrameSettings();

void main() {
  test('story_center_crop', () {
    expect(
      cropRectFor(story, fullHd),
      const PixelRect(x: 657, y: 0, width: 606, height: 1080),
    );
  });

  test('story_left_crop', () {
    final crop = cropRectFor(story.withFocus(CropFocus.left), fullHd);

    expect(crop.x, 0);
  });

  test('story_right_crop', () {
    final crop = cropRectFor(story.withFocus(CropFocus.right), fullHd);

    expect(crop.x, 1314);
  });

  test('portrait_center_crop', () {
    final crop = cropRectFor(
      story.copyWith(preset: AspectPreset.portrait4x5),
      fullHd,
    );

    expect(crop, const PixelRect(x: 528, y: 0, width: 864, height: 1080));
  });

  test('square_center_crop', () {
    final crop = cropRectFor(
      story.copyWith(preset: AspectPreset.square1x1),
      fullHd,
    );

    expect(crop, const PixelRect(x: 420, y: 0, width: 1080, height: 1080));
  });

  test('free_initial_crop', () {
    final crop = cropRectFor(story.copyWith(preset: AspectPreset.free), fullHd);

    expect(crop, const PixelRect(x: 576, y: 43, width: 768, height: 992));
  });

  test('free_crop_uses_source_pixels_for_720p', () {
    final crop = cropRectFor(
      story.copyWith(preset: AspectPreset.free),
      const OutputSize(1280, 720),
    );

    expect(crop, const PixelRect(x: 384, y: 28, width: 512, height: 662));
  });

  test('story_crop_of_vertical_source', () {
    final crop = cropRectFor(story, const OutputSize(720, 1280));

    expect(crop, const PixelRect(x: 0, y: 0, width: 720, height: 1280));
  });

  test('blur_and_landscape_have_no_crop', () {
    expect(
      () => cropRectFor(story.copyWith(fill: FillMode.blur), fullHd),
      throwsArgumentError,
    );
  });

  test('ndc_of_story_center_crop', () {
    final ndc = toNdc(cropRectFor(story, fullHd), fullHd);

    expect(
      [ndc.left, ndc.right, ndc.top, ndc.bottom],
      [
        closeTo(-0.315625, 1e-9),
        closeTo(0.315625, 1e-9),
        closeTo(1, 1e-9),
        closeTo(-1, 1e-9),
      ],
    );
  });

  group('cropRectAt', () {
    CropPath leftToRight({CropArrival arrival = CropArrival.glide}) =>
        CropPath([
          const CropKeyframe(
            time: Duration.zero,
            anchor: CropAnchor(x: 0, y: 0.5),
            arrival: CropArrival.glide,
          ),
          CropKeyframe(
            time: const Duration(seconds: 10),
            anchor: const CropAnchor(x: 1, y: 0.5),
            arrival: arrival,
          ),
        ]);

    test('with_no_keyframes_it_is_the_fixed_crop', () {
      expect(
        cropRectAt(story, fullHd, const Duration(seconds: 3)),
        cropRectFor(story, fullHd),
      );
    });

    test('a_glide_halfway_is_the_centre', () {
      final frame = story.copyWith(cropPath: leftToRight());

      expect(cropRectAt(frame, fullHd, const Duration(seconds: 5)).x, 657);
    });

    test('the_window_keeps_its_size_while_it_moves', () {
      final frame = story.copyWith(cropPath: leftToRight());

      final crop = cropRectAt(frame, fullHd, const Duration(seconds: 2));

      expect((crop.width, crop.height), (606, 1080));
    });

    test('a_cut_stays_left_until_its_time', () {
      final frame = story.copyWith(
        cropPath: leftToRight(arrival: CropArrival.cut),
      );

      expect(cropRectAt(frame, fullHd, const Duration(seconds: 9)).x, 0);
    });

    test('the_end_of_a_glide_is_the_far_right', () {
      final frame = story.copyWith(cropPath: leftToRight());

      expect(
        cropRectAt(frame, fullHd, const Duration(seconds: 10)).x,
        fullHd.width - 606,
      );
    });
  });

  test('an_anchor_between_the_three_places_puts_the_window_in_the_room', () {
    final frame = story.copyWith(anchor: const CropAnchor(x: 0.25, y: 0.5));

    expect(cropRectFor(frame, fullHd).x, 328);
  });

  group('baseAnchorFor', () {
    test('centre_focus_is_the_middle', () {
      expect(baseAnchorFor(story), const CropAnchor(x: 0.5, y: 0.5));
    });

    test('right_focus_is_the_far_right', () {
      expect(baseAnchorFor(story.withFocus(CropFocus.right)).x, 1);
    });

    test('a_free_crop_anchor_is_its_place_in_the_room_left', () {
      final anchor = baseAnchorFor(
        const FrameSettings(preset: AspectPreset.free),
      );

      expect(anchor.x, closeTo(0.5, 1e-9));
      expect(anchor.y, closeTo(0.5, 1e-9));
    });
  });

  group('canMoveCrop', () {
    const portraitSource = OutputSize(1080, 1920);

    test('a_story_crop_of_a_wide_video_can_move', () {
      expect(canMoveCrop(story, fullHd), isTrue);
    });

    test('16_9_keeps_the_whole_frame', () {
      final frame = story.copyWith(preset: AspectPreset.landscape16x9);

      expect(canMoveCrop(frame, fullHd), isFalse);
    });

    test('blur_keeps_the_whole_frame', () {
      final frame = story.copyWith(fill: FillMode.blur);

      expect(canMoveCrop(frame, fullHd), isFalse);
    });

    test('a_source_already_at_the_presets_aspect_has_no_room', () {
      expect(canMoveCrop(story, portraitSource), isFalse);
    });

    test('a_4_5_crop_of_a_tall_video_can_move_up_and_down', () {
      final frame = story.copyWith(preset: AspectPreset.portrait4x5);

      expect(canMoveCrop(frame, portraitSource), isTrue);
    });

    test('a_free_crop_smaller_than_the_frame_can_move', () {
      expect(
        canMoveCrop(const FrameSettings(preset: AspectPreset.free), fullHd),
        isTrue,
      );
    });

    test('a_free_crop_of_the_whole_frame_has_no_room', () {
      final frame = const FrameSettings(preset: AspectPreset.free).copyWith(
        freeCrop: const FreeCropRect(left: 0, top: 0, width: 1, height: 1),
      );

      expect(canMoveCrop(frame, fullHd), isFalse);
    });
  });

  group('cropRectForAnchor', () {
    test('places_the_window_by_the_anchor', () {
      final crop = cropRectForAnchor(
        story,
        fullHd,
        const CropAnchor(x: 0.25, y: 0.5),
      );

      expect(crop.x, 328);
    });
  });
}
