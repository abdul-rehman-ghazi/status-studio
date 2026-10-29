import 'package:flutter/foundation.dart';

enum CaptionVariant { original, roman, english }

enum CaptionPosition { top, bottom }

enum CaptionSize {
  small(0.045),
  medium(0.055),
  large(0.068);

  const CaptionSize(this.widthFraction);

  /// Font size as a fraction of the output width (spec FR-7).
  final double widthFraction;
}

@immutable
class CaptionSettings {
  const CaptionSettings({
    this.variant = CaptionVariant.original,
    this.text = '',
    this.position = CaptionPosition.bottom,
    this.size = CaptionSize.medium,
  });

  final CaptionVariant variant;
  final String text;
  final CaptionPosition position;
  final CaptionSize size;

  CaptionSettings copyWith({
    CaptionVariant? variant,
    String? text,
    CaptionPosition? position,
    CaptionSize? size,
  }) {
    return CaptionSettings(
      variant: variant ?? this.variant,
      text: text ?? this.text,
      position: position ?? this.position,
      size: size ?? this.size,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CaptionSettings &&
      other.variant == variant &&
      other.text == text &&
      other.position == position &&
      other.size == size;

  @override
  int get hashCode => Object.hash(variant, text, position, size);
}
