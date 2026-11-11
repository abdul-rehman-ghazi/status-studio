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

/// Whether the caption sits on a box or casts a shadow (spec FR-7, M37).
enum CaptionLook { box, shadow }

/// Text on box, for [CaptionLook.box].
enum BoxColours { whiteOnBlack, blackOnWhite, yellowOnBlack, whiteOnGreen }

/// Text and its shadow, for [CaptionLook.shadow].
enum ShadowColours { white, yellow, blackGlow, gold }

/// The caption's look and the colour each look last had, so switching looks
/// back and forth keeps both colours (spec FR-7).
@immutable
class CaptionAppearance {
  const CaptionAppearance({
    this.look = CaptionLook.box,
    this.boxColours = BoxColours.whiteOnBlack,
    this.shadowColours = ShadowColours.white,
  });

  final CaptionLook look;
  final BoxColours boxColours;
  final ShadowColours shadowColours;

  CaptionAppearance copyWith({
    CaptionLook? look,
    BoxColours? boxColours,
    ShadowColours? shadowColours,
  }) {
    return CaptionAppearance(
      look: look ?? this.look,
      boxColours: boxColours ?? this.boxColours,
      shadowColours: shadowColours ?? this.shadowColours,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CaptionAppearance &&
      other.look == look &&
      other.boxColours == boxColours &&
      other.shadowColours == shadowColours;

  @override
  int get hashCode => Object.hash(look, boxColours, shadowColours);
}

@immutable
class CaptionSettings {
  const CaptionSettings({
    this.text = '',
    this.position = CaptionPosition.bottom,
    this.size = CaptionSize.medium,
    this.appearance = const CaptionAppearance(),
  });

  final String text;
  final CaptionPosition position;
  final CaptionSize size;
  final CaptionAppearance appearance;

  CaptionSettings copyWith({
    String? text,
    CaptionPosition? position,
    CaptionSize? size,
    CaptionAppearance? appearance,
  }) {
    return CaptionSettings(
      text: text ?? this.text,
      position: position ?? this.position,
      size: size ?? this.size,
      appearance: appearance ?? this.appearance,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CaptionSettings &&
      other.text == text &&
      other.position == position &&
      other.size == size &&
      other.appearance == appearance;

  @override
  int get hashCode => Object.hash(text, position, size, appearance);
}
