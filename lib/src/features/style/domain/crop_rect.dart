import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';

// The epsilon stops values like 575.9999999 (from 1920 × 0.3) losing a pixel.
const _epsilon = 1e-6;

/// A rectangle in whole source pixels.
@immutable
class PixelRect {
  const PixelRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int x;
  final int y;
  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is PixelRect &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'PixelRect($x, $y, $width × $height)';
}

/// A crop in normalised device coordinates, as Media3's `Crop` takes it
/// (spec §6.3.1): x from −1 (left) to 1, y from −1 (bottom) to 1.
@immutable
class NdcRect {
  const NdcRect({
    required this.left,
    required this.right,
    required this.bottom,
    required this.top,
  });

  final double left;
  final double right;
  final double bottom;
  final double top;

  @override
  bool operator ==(Object other) =>
      other is NdcRect &&
      other.left == left &&
      other.right == right &&
      other.bottom == bottom &&
      other.top == top;

  @override
  int get hashCode => Object.hash(left, right, bottom, top);
}

/// The part of [source] that [frame] keeps (spec §6.3). Sizes are rounded
/// down to even numbers and offsets to whole pixels.
///
/// Throws [ArgumentError] for blur and 16:9, which keep the whole frame.
PixelRect cropRectFor(FrameSettings frame, OutputSize source) {
  if (frame.preset == AspectPreset.free) {
    return _freeCrop(frame.freeCrop, source);
  }
  if (frame.preset == AspectPreset.landscape16x9 ||
      frame.fill == FillMode.blur) {
    throw ArgumentError.value(frame, 'frame', 'keeps the whole frame');
  }
  return _fillCrop(frame, source);
}

PixelRect _freeCrop(FreeCropRect crop, OutputSize source) {
  return PixelRect(
    x: _floor(source.width * crop.left),
    y: _floor(source.height * crop.top),
    width: _floorToEven(source.width * crop.width),
    height: _floorToEven(source.height * crop.height),
  );
}

/// The largest rectangle of the preset's aspect inside the source, placed
/// by the focus and centred vertically.
PixelRect _fillCrop(FrameSettings frame, OutputSize source) {
  final target = outputSizeFor(frame, source);
  final targetAspect = target.width / target.height;
  final sourceIsWider = source.width / source.height > targetAspect;
  final width = sourceIsWider
      ? _floorToEven(source.height * targetAspect)
      : _floorToEven(source.width.toDouble());
  final height = sourceIsWider
      ? _floorToEven(source.height.toDouble())
      : _floorToEven(source.width / targetAspect);
  return PixelRect(
    x: _focusX(frame.focus, source.width - width),
    y: (source.height - height) ~/ 2,
    width: width,
    height: height,
  );
}

int _focusX(CropFocus focus, int spareWidth) => switch (focus) {
  CropFocus.left => 0,
  CropFocus.center => spareWidth ~/ 2,
  CropFocus.right => spareWidth,
};

/// [rect] in Media3's normalised device coordinates (spec §6.3.1).
NdcRect toNdc(PixelRect rect, OutputSize source) {
  return NdcRect(
    left: 2 * rect.x / source.width - 1,
    right: 2 * (rect.x + rect.width) / source.width - 1,
    top: 1 - 2 * rect.y / source.height,
    bottom: 1 - 2 * (rect.y + rect.height) / source.height,
  );
}

int _floor(double pixels) => (pixels + _epsilon).floor();

int _floorToEven(double pixels) => _floor(pixels) ~/ 2 * 2;
