// Run with `fvm flutter test tool/export_logo_test.dart` to regenerate the
// launcher icon sources from the app's own LogoPainter (spec §7).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/branding/presentation/logo_mark.dart';
import 'package:status_studio/src/theme/app_theme.dart';

const _size = 1024.0;

/// Android masks adaptive icons to as little as a circle 66 % across; the
/// bracket corners must stay inside it.
const _foregroundScale = 0.85;

Future<void> _writePng(String path, void Function(Canvas canvas) paint) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final image = await recorder.endRecording().toImage(
    _size.toInt(),
    _size.toInt(),
  );
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  await File(path).writeAsBytes(png!.buffer.asUint8List());
}

/// Full-bleed: iOS rejects transparency and rounds the corners itself.
void _paintFull(Canvas canvas) {
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, _size, _size),
    Paint()..color = AppColors.accent,
  );
  LogoPainter(
    tile: AppColors.accent,
    ink: AppColors.onAccent,
  ).paint(canvas, const Size.square(_size));
}

/// Ink only, for the adaptive icon over its accent background.
void _paintForeground(Canvas canvas) {
  const inset = _size * (1 - _foregroundScale) / 2;
  canvas.translate(inset, inset);
  LogoPainter(
    tile: Colors.transparent,
    ink: AppColors.onAccent,
  ).paint(canvas, const Size.square(_size * _foregroundScale));
}

void main() {
  testWidgets('exports_launcher_icon_sources', (tester) async {
    await tester.runAsync(() async {
      await Directory('assets/branding').create(recursive: true);
      await _writePng('assets/branding/logo_1024.png', _paintFull);
      await _writePng(
        'assets/branding/logo_foreground_1024.png',
        _paintForeground,
      );
    });

    expect(
      File('assets/branding/logo_foreground_1024.png').existsSync(),
      isTrue,
    );
  });
}
