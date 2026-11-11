import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:status_studio/src/core/presentation/script_text.dart';
import 'package:status_studio/src/core/script_detection.dart';
import 'package:status_studio/src/features/branding/presentation/logo_mark.dart';
import 'package:status_studio/src/features/export/domain/overlay_layout.dart';
import 'package:status_studio/src/features/style/domain/caption_ink.dart';
import 'package:status_studio/src/features/style/domain/caption_settings.dart';
import 'package:status_studio/src/theme/app_theme.dart';

const brandingText = 'Status Studio';

// Shares of the logo size, as in the Style preview.
const _brandingGap = 0.3;
const _brandingFont = 0.55;

/// The caption and branding on a transparent image at output size, for
/// Media3 to lay over the video (spec §5). Flutter draws the text so
/// Nastaliq joins properly.
Future<Uint8List> paintOverlayPng(OverlaySpec spec) async {
  final recorder = ui.PictureRecorder();
  _paintOverlay(Canvas(recorder), spec);
  final image = await recorder.endRecording().toImage(
    spec.output.width,
    spec.output.height,
  );
  try {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) {
      throw StateError("Couldn't encode the overlay as PNG.");
    }
    return png.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Measures caption text exactly as the overlay paints it. Colours and
/// shadows don't change the layout, so the default ink measures every look.
Size measureCaptionText(String text, double fontSize, double maxWidth) {
  final painter = captionTextPainter(
    text,
    captionTextStyle(text, fontSize, captionInkFor(const CaptionAppearance())),
  )..layout(maxWidth: maxWidth);
  final size = painter.size;
  painter.dispose();
  return size;
}

/// The caption's text style for [text]: its script's font and line height,
/// in [ink]'s colour and shadow. Not inherited, so the Style preview's `Text`
/// lays out exactly like the painter here instead of picking up the theme's
/// letter spacing.
TextStyle captionTextStyle(String text, double fontSize, CaptionInk ink) =>
    scriptTextStyle(text).copyWith(
      inherit: false,
      fontSize: fontSize,
      color: ink.text,
      shadows: ink.shadowsAt(fontSize),
    );

/// "Status Studio" in the branding pill; not inherited, as above.
TextStyle brandingTextStyle(double logoSize) => TextStyle(
  inherit: false,
  color: ReelColors.text,
  fontFamily: AppFonts.ui,
  fontWeight: FontWeight.w600,
  fontSize: logoSize * _brandingFont,
  height: 1,
);

TextDirection captionTextDirection(String text) =>
    isArabicScript(text) ? TextDirection.rtl : TextDirection.ltr;

TextPainter captionTextPainter(String text, TextStyle style) => TextPainter(
  text: TextSpan(text: text, style: style),
  textAlign: TextAlign.center,
  textDirection: captionTextDirection(text),
);

void _paintOverlay(Canvas canvas, OverlaySpec spec) {
  final layout = layoutOverlay(spec, measureText: measureCaptionText);
  if (spec.caption.text.trim().isNotEmpty) {
    _paintCaption(canvas, spec.caption, layout);
  }
  _paintBranding(canvas, layout);
}

void _paintCaption(
  Canvas canvas,
  CaptionSettings caption,
  OverlayLayout layout,
) {
  final box = layout.captionBox;
  final ink = captionInkFor(caption.appearance);
  final boxColour = ink.box;
  if (boxColour != null) {
    canvas.drawRect(box, Paint()..color = boxColour);
  }
  final text = caption.text;
  final painter =
      captionTextPainter(
          text,
          captionTextStyle(text, layout.captionFontSize, ink),
        )
        ..maxLines = layout.captionMaxLines
        ..ellipsis = '…'
        ..layout(maxWidth: layout.captionTextMaxWidth);
  final textTop = box.top + layout.captionPadding;
  // The shadow look has no box, so its blur may spill past the block.
  canvas
    ..save()
    ..clipRect(boxColour == null ? box.inflate(layout.captionPadding) : box);
  painter.paint(canvas, Offset(box.center.dx - painter.width / 2, textTop));
  canvas.restore();
  painter.dispose();
}

void _paintBranding(Canvas canvas, OverlayLayout layout) {
  final logo = layout.logoSize;
  final padding = logo * brandingPillPadding;
  final label = TextPainter(
    text: TextSpan(text: brandingText, style: brandingTextStyle(logo)),
    textDirection: TextDirection.ltr,
  )..layout();
  final pill =
      layout.brandingOrigin &
      Size(
        padding * 2 + logo + logo * _brandingGap + label.width,
        logo + padding * 2,
      );
  canvas.drawRRect(
    RRect.fromRectAndRadius(pill, Radius.circular(logo)),
    Paint()..color = ReelColors.scrim.withValues(alpha: 0.45),
  );
  final logoOrigin = pill.topLeft + Offset(padding, padding);
  canvas
    ..save()
    ..translate(logoOrigin.dx, logoOrigin.dy);
  LogoPainter(
    tile: LogoColors.tile,
    ink: LogoColors.ink,
  ).paint(canvas, Size.square(logo));
  canvas.restore();
  label.paint(
    canvas,
    Offset(
      logoOrigin.dx + logo + logo * _brandingGap,
      pill.center.dy - label.height / 2,
    ),
  );
  label.dispose();
}
