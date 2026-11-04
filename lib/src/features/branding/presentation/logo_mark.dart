import 'package:flutter/material.dart';
import 'package:status_studio/src/features/branding/domain/logo_pose.dart';
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
  LogoPainter({
    required this.tile,
    required this.ink,
    this.pose = LogoPose.rest,
  });

  final Color tile;
  final Color ink;
  final LogoPose pose;

  static const _barXs = [38.0, 44.0, 50.0, 56.0, 62.0];
  static const _barCentreY = 50.0;

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
    final inset = pose.bracketInset;
    final left = Path()
      ..moveTo(33 + inset, 24)
      ..lineTo(24 + inset, 24)
      ..lineTo(24 + inset, 76)
      ..lineTo(33 + inset, 76);
    final right = Path()
      ..moveTo(67 - inset, 24)
      ..lineTo(76 - inset, 24)
      ..lineTo(76 - inset, 76)
      ..lineTo(67 - inset, 76);
    canvas
      ..drawPath(left, stroke)
      ..drawPath(right, stroke);
  }

  void _paintBars(Canvas canvas) {
    final stroke = _inkStroke(4.5);
    for (final (index, x) in _barXs.indexed) {
      final halfLength = pose.barHalfLengths[index];
      canvas.drawLine(
        Offset(x, _barCentreY - halfLength),
        Offset(x, _barCentreY + halfLength),
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
      oldDelegate.tile != tile ||
      oldDelegate.ink != ink ||
      oldDelegate.pose != pose;
}
