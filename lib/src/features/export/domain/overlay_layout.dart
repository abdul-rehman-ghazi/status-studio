import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/style/domain/caption_font.dart';
import 'package:status_studio/src/features/style/domain/caption_settings.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';

// Shares of the output size, from spec FR-7 and FR-8.
const _captionPadding = 0.02;
const _captionEdgeMargin = 0.06;
const _captionMaxHeight = 0.35;
const _captionMaxWidth = 0.92;
const _shrinkStep = 0.05;
const _smallestFont = 0.6;
const _brandingInset = 0.04;
const _logoSize = 0.045;

/// Space above and below the logo inside the branding pill, as a share of
/// the logo size.
const brandingPillPadding = 0.2;

/// Measures [text] laid out at [fontSize] within [maxWidth].
typedef MeasureText = Size Function(
  String text,
  double fontSize,
  double maxWidth,
);

@immutable
class OverlaySpec {
  const OverlaySpec({required this.output, required this.caption});

  final OutputSize output;
  final CaptionSettings caption;

  @override
  bool operator ==(Object other) =>
      other is OverlaySpec &&
      other.output == output &&
      other.caption == caption;

  @override
  int get hashCode => Object.hash(output, caption);
}

/// Where the caption and branding go, in output pixels.
@immutable
class OverlayLayout {
  const OverlayLayout({
    required this.captionBox,
    required this.captionFontSize,
    required this.captionMaxLines,
    required this.captionPadding,
    required this.captionTextMaxWidth,
    required this.brandingOrigin,
    required this.logoSize,
  });

  /// The dark block behind the caption, padding included.
  final Rect captionBox;
  final double captionFontSize;

  /// Lines beyond this are cut and the last one ends with an ellipsis.
  final int captionMaxLines;
  final double captionPadding;

  /// The width the caption text wraps at; the box shrinks to the text.
  final double captionTextMaxWidth;

  /// Top-left corner of the branding pill.
  final Offset brandingOrigin;
  final double logoSize;
}

/// Caption and branding geometry (spec FR-7, FR-8). Shared by the export
/// overlay and the Style preview, so both look the same.
OverlayLayout layoutOverlay(
  OverlaySpec spec, {
  required MeasureText measureText,
}) {
  final width = spec.output.width.toDouble();
  final height = spec.output.height.toDouble();
  final padding = width * _captionPadding;
  final maxBlockHeight = height * _captionMaxHeight;
  final textMaxWidth = width * _captionMaxWidth - 2 * padding;
  final fitted = _fitCaption(
    spec,
    maxTextSize: Size(textMaxWidth, maxBlockHeight - 2 * padding),
    measureText: measureText,
  );
  final boxSize = Size(
    fitted.textSize.width + 2 * padding,
    math.min(fitted.textSize.height + 2 * padding, maxBlockHeight),
  );
  final captionOnTop = spec.caption.position == CaptionPosition.top;
  final edgeMargin = height * _captionEdgeMargin;
  final captionTop = captionOnTop
      ? edgeMargin
      : height - edgeMargin - boxSize.height;
  final lineHeight = fitted.fontSize * captionLineHeight(spec.caption.text);
  return OverlayLayout(
    captionBox: Offset((width - boxSize.width) / 2, captionTop) & boxSize,
    captionFontSize: fitted.fontSize,
    captionMaxLines: math.max(
      1,
      ((maxBlockHeight - 2 * padding) / lineHeight).floor(),
    ),
    captionPadding: padding,
    captionTextMaxWidth: textMaxWidth,
    brandingOrigin: _brandingOrigin(spec.output, captionOnTop: captionOnTop),
    logoSize: width * _logoSize,
  );
}

/// The chosen font size, or the first 5 % step down that fits, stopping at
/// 60 % (spec FR-7). Text that still doesn't fit is clipped by the painter.
({double fontSize, Size textSize}) _fitCaption(
  OverlaySpec spec, {
  required Size maxTextSize,
  required MeasureText measureText,
}) {
  final chosen = spec.output.width * spec.caption.size.widthFraction;
  final steps = ((1 - _smallestFont) / _shrinkStep).round();
  var fitted = (fontSize: chosen, textSize: Size.zero);
  for (var step = 0; step <= steps; step++) {
    final fontSize = chosen * (1 - _shrinkStep * step);
    final textSize = measureText(
      spec.caption.text,
      fontSize,
      maxTextSize.width,
    );
    fitted = (fontSize: fontSize, textSize: textSize);
    if (textSize.height <= maxTextSize.height) {
      return fitted;
    }
  }
  return fitted;
}

/// Top-left when the caption is at the bottom; bottom-left otherwise.
Offset _brandingOrigin(OutputSize output, {required bool captionOnTop}) {
  final inset = output.width * _brandingInset;
  final pillHeight = output.width * _logoSize * (1 + 2 * brandingPillPadding);
  return Offset(
    inset,
    captionOnTop ? output.height - inset - pillHeight : inset,
  );
}
