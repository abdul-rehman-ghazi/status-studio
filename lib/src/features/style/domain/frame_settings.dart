import 'dart:math' as math;

import 'package:flutter/foundation.dart';

@immutable
class OutputSize {
  const OutputSize(this.width, this.height);

  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is OutputSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '$width × $height';
}

enum AspectPreset {
  story9x16('9:16'),
  portrait4x5('4:5'),
  square1x1('1:1'),
  landscape16x9('16:9'),
  free('Free');

  const AspectPreset(this.label);

  final String label;
}

enum FillMode { crop, blur }

enum CropFocus { left, center, right }

/// A crop rectangle in fractions of the source frame (spec FR-6).
@immutable
class FreeCropRect {
  const FreeCropRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  static const initial = FreeCropRect(
    left: 0.30,
    top: 0.04,
    width: 0.40,
    height: 0.92,
  );
  static const minimumSide = 0.12;

  final double left;
  final double top;
  final double width;
  final double height;

  /// Moves the rectangle, keeping it inside the frame.
  FreeCropRect moveBy(double dx, double dy) {
    return copyWith(
      left: _clamp(left + dx, 0, 1 - width),
      top: _clamp(top + dy, 0, 1 - height),
    );
  }

  /// Resizes from the bottom-right corner, keeping it inside the frame and
  /// no smaller than [minimumSide].
  FreeCropRect resizeBy(double dx, double dy) {
    return copyWith(
      width: _clamp(width + dx, minimumSide, 1 - left),
      height: _clamp(height + dy, minimumSide, 1 - top),
    );
  }

  FreeCropRect copyWith({
    double? left,
    double? top,
    double? width,
    double? height,
  }) {
    return FreeCropRect(
      left: left ?? this.left,
      top: top ?? this.top,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FreeCropRect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);
}

double _clamp(double value, double lowest, double highest) =>
    math.min(highest, math.max(lowest, value));

@immutable
class FrameSettings {
  const FrameSettings({
    this.preset = AspectPreset.story9x16,
    this.fill = FillMode.crop,
    this.focus = CropFocus.center,
    this.freeCrop = FreeCropRect.initial,
  });

  final AspectPreset preset;
  final FillMode fill;
  final CropFocus focus;
  final FreeCropRect freeCrop;

  bool get offersFill =>
      preset != AspectPreset.landscape16x9 && preset != AspectPreset.free;

  bool get offersFocus => offersFill && fill == FillMode.crop;

  FrameSettings copyWith({
    AspectPreset? preset,
    FillMode? fill,
    CropFocus? focus,
    FreeCropRect? freeCrop,
  }) {
    return FrameSettings(
      preset: preset ?? this.preset,
      fill: fill ?? this.fill,
      focus: focus ?? this.focus,
      freeCrop: freeCrop ?? this.freeCrop,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FrameSettings &&
      other.preset == preset &&
      other.fill == fill &&
      other.focus == focus &&
      other.freeCrop == freeCrop;

  @override
  int get hashCode => Object.hash(preset, fill, focus, freeCrop);
}

const _maximumFreeSide = 1920;

/// Output size for [frame] cut from a [source] video (spec FR-6).
OutputSize outputSizeFor(FrameSettings frame, OutputSize source) {
  return switch (frame.preset) {
    AspectPreset.story9x16 => const OutputSize(1080, 1920),
    AspectPreset.portrait4x5 => const OutputSize(1080, 1350),
    AspectPreset.square1x1 => const OutputSize(1080, 1080),
    AspectPreset.landscape16x9 => const OutputSize(1920, 1080),
    AspectPreset.free => _freeCropSize(frame.freeCrop, source),
  };
}

OutputSize _freeCropSize(FreeCropRect crop, OutputSize source) {
  final cropWidth = source.width * crop.width;
  final cropHeight = source.height * crop.height;
  final scale = math.min(
    1.0,
    _maximumFreeSide / math.max(cropWidth, cropHeight),
  );
  return OutputSize(
    _roundDownToEven(cropWidth * scale),
    _roundDownToEven(cropHeight * scale),
  );
}

// The epsilon stops values like 575.9999999 (from 1920 × 0.3) losing a pixel.
int _roundDownToEven(double pixels) => (pixels + 1e-6).floor() ~/ 2 * 2;
