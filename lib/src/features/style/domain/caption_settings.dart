import 'package:flutter/foundation.dart';

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
    this.text = '',
    this.position = CaptionPosition.bottom,
    this.size = CaptionSize.medium,
  });

  final String text;
  final CaptionPosition position;
  final CaptionSize size;

  CaptionSettings copyWith({
    String? text,
    CaptionPosition? position,
    CaptionSize? size,
  }) {
    return CaptionSettings(
      text: text ?? this.text,
      position: position ?? this.position,
      size: size ?? this.size,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CaptionSettings &&
      other.text == text &&
      other.position == position &&
      other.size == size;

  @override
  int get hashCode => Object.hash(text, position, size);
}
