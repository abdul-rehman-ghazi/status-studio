import 'dart:typed_data';

/// The width and height of a JPEG, read from its frame header without
/// decoding it. Face boxes come back in pixels, and turning them into
/// fractions of the frame needs this (spec FR-23).
({int width, int height}) jpegSize(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    throw const FormatException('Not a JPEG.');
  }
  var position = 2;
  while (position + 9 < bytes.length) {
    if (bytes[position] != 0xFF) {
      throw const FormatException('Broken JPEG segment.');
    }
    final marker = bytes[position + 1];
    if (marker == 0xFF) {
      position++;
      continue;
    }
    if (_isFrameHeader(marker)) {
      return (
        width: bytes[position + 7] << 8 | bytes[position + 8],
        height: bytes[position + 5] << 8 | bytes[position + 6],
      );
    }
    position += 2 + (bytes[position + 2] << 8 | bytes[position + 3]);
  }
  throw const FormatException('No frame header in the JPEG.');
}

// The start-of-frame markers, not the table, arithmetic or reset ones that
// sit among them.
bool _isFrameHeader(int marker) =>
    marker >= 0xC0 &&
    marker <= 0xCF &&
    marker != 0xC4 &&
    marker != 0xC8 &&
    marker != 0xCC;
