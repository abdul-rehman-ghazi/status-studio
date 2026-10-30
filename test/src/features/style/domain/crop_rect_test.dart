import 'package:flutter_test/flutter_test.dart';
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
    final crop = cropRectFor(story.copyWith(focus: CropFocus.left), fullHd);

    expect(crop.x, 0);
  });

  test('story_right_crop', () {
    final crop = cropRectFor(story.copyWith(focus: CropFocus.right), fullHd);

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
}
