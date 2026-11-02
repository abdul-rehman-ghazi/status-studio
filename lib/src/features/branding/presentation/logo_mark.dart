import 'package:flutter/material.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// The "Trim" logo: brackets around a five-bar waveform on a rounded tile.
class LogoMark extends StatelessWidget {
  const LogoMark({
    super.key,
    required this.size,
    this.tile = AppColors.accent,
    this.ink = AppColors.onAccent,
  });

  final double size;
  final Color tile;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: LogoPainter(tile: tile, ink: ink),
      ),
    );
  }
}

/// Paints the logo from spec §7's 100-unit box, scaled to the canvas width.
class LogoPainter extends CustomPainter {
  LogoPainter({required this.tile, required this.ink});

  final Color tile;
  final Color ink;

  static const _bars = [
    (x: 38.0, top: 42.0, bottom: 58.0),
    (x: 44.0, top: 35.0, bottom: 65.0),
    (x: 50.0, top: 30.0, bottom: 70.0),
    (x: 56.0, top: 37.0, bottom: 63.0),
    (x: 62.0, top: 43.0, bottom: 57.0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100);
    _paintTile(canvas);
    _paintBrackets(canvas);
    _paintBars(canvas);
  }

  void _paintTile(Canvas canvas) {
    final tileRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0, 0, 100, 100),
      const Radius.circular(24),
    );
    canvas.drawRRect(tileRect, Paint()..color = tile);
  }

  void _paintBrackets(Canvas canvas) {
    final stroke = _inkStroke(6)..strokeJoin = StrokeJoin.round;
    final left = Path()
      ..moveTo(33, 24)
      ..lineTo(24, 24)
      ..lineTo(24, 76)
      ..lineTo(33, 76);
    final right = Path()
      ..moveTo(67, 24)
      ..lineTo(76, 24)
      ..lineTo(76, 76)
      ..lineTo(67, 76);
    canvas
      ..drawPath(left, stroke)
      ..drawPath(right, stroke);
  }

  void _paintBars(Canvas canvas) {
    final stroke = _inkStroke(4.5);
    for (final bar in _bars) {
      canvas.drawLine(
        Offset(bar.x, bar.top),
        Offset(bar.x, bar.bottom),
        stroke,
      );
    }
  }

  Paint _inkStroke(double width) => Paint()
    ..color = ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round;

  @override
  bool shouldRepaint(LogoPainter oldDelegate) =>
      oldDelegate.tile != tile || oldDelegate.ink != ink;
}
