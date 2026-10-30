import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/export/data/overlay_painter.dart';
import 'package:status_studio/src/features/export/domain/overlay_layout.dart';
import 'package:status_studio/src/features/style/domain/caption_settings.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';

/// Width and height from a PNG's IHDR chunk.
(int, int) pngSize(Uint8List png) {
  final header = ByteData.sublistView(png);
  return (header.getUint32(16), header.getUint32(20));
}

void main() {
  testWidgets('overlay_png_has_output_dimensions', (tester) async {
    const spec = OverlaySpec(
      output: OutputSize(1080, 1350),
      caption: CaptionSettings(text: 'محنت کامیابی کی کنجی ہے'),
    );

    final png = await tester.runAsync(() => paintOverlayPng(spec));

    expect(pngSize(png!), (1080, 1350));
  });
}
