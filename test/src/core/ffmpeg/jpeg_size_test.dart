import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/core/ffmpeg/jpeg_size.dart';

/// The start of a JPEG: SOI, a small APP0 segment, then a baseline frame
/// header with [width] × [height].
Uint8List jpegHeader({required int width, required int height}) {
  return Uint8List.fromList([
    0xFF, 0xD8, // start of image
    0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00, // APP0, two bytes of payload
    0xFF, 0xC0, 0x00, 0x11, 0x08, // start of frame, 8-bit samples
    height >> 8, height & 0xFF,
    width >> 8, width & 0xFF,
    0x03,
  ]);
}

void main() {
  test('reads_the_width_and_height_from_the_frame_header', () {
    final size = jpegSize(jpegHeader(width: 640, height: 360));

    expect((size.width, size.height), (640, 360));
  });

  test('reads_a_size_over_255_in_both_bytes', () {
    final size = jpegSize(jpegHeader(width: 1080, height: 1920));

    expect((size.width, size.height), (1080, 1920));
  });

  test('a_file_that_is_not_a_jpeg_is_refused', () {
    expect(
      () => jpegSize(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47])),
      throwsFormatException,
    );
  });

  test('a_jpeg_cut_off_before_its_frame_header_is_refused', () {
    expect(
      () => jpegSize(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00])),
      throwsFormatException,
    );
  });
}
