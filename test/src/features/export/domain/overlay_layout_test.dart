import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/export/domain/overlay_layout.dart';
import 'package:status_studio/src/features/style/domain/caption_settings.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';

const story = OutputSize(1080, 1920);

/// Each character is half the font size wide; lines are 1.3 high.
Size fakeMeasure(String text, double fontSize, double maxWidth) {
  final characterWidth = fontSize * 0.5;
  final perLine = (maxWidth / characterWidth).floor();
  final lines = (text.length / perLine).ceil();
  final width = text.length < perLine ? text.length * characterWidth : maxWidth;
  return Size(width, lines * fontSize * 1.3);
}

OverlayLayout layoutFor(CaptionSettings caption) => layoutOverlay(
  OverlaySpec(output: story, caption: caption),
  measureText: fakeMeasure,
);

const shortCaption = CaptionSettings(text: 'A short line');

void main() {
  test('medium_caption_font_is_5_5_percent_of_width', () {
    final layout = layoutFor(shortCaption);

    expect(layout.captionFontSize, closeTo(59.4, 1e-9));
  });

  test('caption_bottom_margin_is_6_percent_of_height', () {
    final layout = layoutFor(shortCaption);

    expect(layout.captionBox.bottom, closeTo(1804.8, 1e-9));
  });

  test('caption_box_is_centred', () {
    final layout = layoutFor(shortCaption);

    expect(layout.captionBox.center.dx, closeTo(540, 1e-9));
  });

  test('branding_top_left_when_caption_bottom', () {
    final layout = layoutFor(shortCaption);

    expect(
      [layout.brandingOrigin.dx, layout.brandingOrigin.dy, layout.logoSize],
      [closeTo(43.2, 1e-9), closeTo(43.2, 1e-9), closeTo(48.6, 1e-9)],
    );
  });

  test('branding_bottom_when_caption_top', () {
    final layout = layoutFor(
      shortCaption.copyWith(position: CaptionPosition.top),
    );

    // Pill height is the logo plus 20 % of it above and below.
    expect(layout.brandingOrigin.dy, closeTo(1920 - 43.2 - 48.6 * 1.4, 1e-9));
  });

  test('caption_top_margin_is_6_percent_of_height', () {
    final layout = layoutFor(
      shortCaption.copyWith(position: CaptionPosition.top),
    );

    expect(layout.captionBox.top, closeTo(115.2, 1e-9));
  });

  test('long_caption_shrinks_then_clips', () {
    final layout = layoutFor(CaptionSettings(text: 'word ' * 600));

    expect(
      [layout.captionFontSize, layout.captionBox.height],
      [closeTo(0.6 * 59.4, 1e-9), lessThanOrEqualTo(672)],
    );
  });

  test('caption_that_fits_after_shrinking_keeps_that_size', () {
    // 10 lines are too tall at 100 % and 95 %; at 90 % 9 lines fit.
    final layout = layoutFor(CaptionSettings(text: 'word ' * 60));

    expect(layout.captionFontSize, closeTo(0.9 * 59.4, 1e-9));
  });

  test('clipped_caption_shows_only_lines_that_fit', () {
    final layout = layoutFor(CaptionSettings(text: 'word ' * 600));

    // (672 − 2 × 21.6 padding) / (35.64 × 1.3 line height) = 13.57 lines.
    expect(layout.captionMaxLines, 13);
  });
}
