import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';

const source = OutputSize(1920, 1080);

void main() {
  test('story_preset_outputs_1080_by_1920', () {
    expect(
      outputSizeFor(const FrameSettings(), source),
      const OutputSize(1080, 1920),
    );
  });

  test('portrait_preset_outputs_1080_by_1350', () {
    const frame = FrameSettings(preset: AspectPreset.portrait4x5);

    expect(outputSizeFor(frame, source), const OutputSize(1080, 1350));
  });

  test('square_preset_outputs_1080_by_1080', () {
    const frame = FrameSettings(preset: AspectPreset.square1x1);

    expect(outputSizeFor(frame, source), const OutputSize(1080, 1080));
  });

  test('landscape_preset_outputs_1920_by_1080', () {
    const frame = FrameSettings(preset: AspectPreset.landscape16x9);

    expect(outputSizeFor(frame, source), const OutputSize(1920, 1080));
  });

  test('free_crop_outputs_even_source_pixels', () {
    const frame = FrameSettings(
      preset: AspectPreset.free,
      freeCrop: FreeCropRect(left: 0.1, top: 0.1, width: 0.333, height: 0.5),
    );

    // 639.36 → 638, 540 → 540
    expect(outputSizeFor(frame, source), const OutputSize(638, 540));
  });

  test('free_crop_from_4k_source_is_scaled_to_1920_long_side', () {
    const frame = FrameSettings(
      preset: AspectPreset.free,
      freeCrop: FreeCropRect(left: 0, top: 0, width: 1, height: 1),
    );

    expect(
      outputSizeFor(frame, const OutputSize(3840, 2160)),
      const OutputSize(1920, 1080),
    );
  });

  test('move_clamps_rectangle_inside_frame', () {
    final moved = FreeCropRect.initial.moveBy(0.9, 0.9);

    expect(moved.left, closeTo(0.60, 1e-9));
    // 1 - 0.92 is not exactly 0.08 in floating point
    expect(moved.top, closeTo(0.08, 1e-9));
  });

  test('move_clamps_rectangle_at_top_left', () {
    final moved = FreeCropRect.initial.moveBy(-1, -1);

    expect((moved.left, moved.top), (0.0, 0.0));
  });

  test('resize_keeps_minimum_side', () {
    final resized = FreeCropRect.initial.resizeBy(-1, -1);

    expect(resized.width, FreeCropRect.minimumSide);
  });

  test('resize_keeps_rectangle_inside_frame', () {
    final resized = FreeCropRect.initial.resizeBy(1, 1);

    expect(resized.width, closeTo(0.70, 1e-9));
  });

  test('fill_options_hidden_for_landscape_and_free', () {
    final offered = [
      AspectPreset.landscape16x9,
      AspectPreset.free,
    ].map((preset) => FrameSettings(preset: preset).offersFill);

    expect(offered, [false, false]);
  });

  test('focus_offered_only_when_cropping_to_fill', () {
    const blurred = FrameSettings(fill: FillMode.blur);

    expect(blurred.offersFocus, isFalse);
  });
}
