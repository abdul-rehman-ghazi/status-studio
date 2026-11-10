import 'package:flutter/material.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/clip/domain/clip_window.dart';
import 'package:status_studio/src/theme/app_theme.dart';

const _height = 56.0;
const _edgeWidth = 2.0;

/// Bars across the downloaded window, with the clip highlighted.
class WaveformView extends StatelessWidget {
  const WaveformView({
    super.key,
    required this.peaks,
    required this.window,
    required this.clip,
  });

  final List<double> peaks;
  final ClipWindow window;
  final ClipRange clip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: CustomPaint(
        painter: _WaveformPainter(waveform: this, palette: context.palette),
        size: Size.infinite,
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({required this.waveform, required this.palette});

  final WaveformView waveform;
  final AppPalette palette;

  List<double> get peaks => waveform.peaks;
  ClipWindow get window => waveform.window;
  ClipRange get clip => waveform.clip;

  double _fractionOf(Duration time) {
    final length = (window.end - window.start).inMicroseconds;
    if (length <= 0) {
      return 0;
    }
    final fraction = (time - window.start).inMicroseconds / length;
    return fraction.clamp(0, 1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final clipLeft = _fractionOf(clip.start) * size.width;
    final clipRight = _fractionOf(clip.end) * size.width;
    _paintBars(canvas, size, (left: clipLeft, right: clipRight));
    _paintSelection(canvas, size, (left: clipLeft, right: clipRight));
  }

  void _paintBars(Canvas canvas, Size size, _Span selected) {
    if (peaks.isEmpty) {
      return;
    }
    final slot = size.width / peaks.length;
    final inside = Paint()..color = palette.accent;
    final outside = Paint()..color = palette.textMuted.withValues(alpha: 0.4);
    for (final (index, peak) in peaks.indexed) {
      final centre = slot * (index + 0.5);
      final barHeight = (size.height - 8) * peak + 2;
      final bar = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centre, size.height / 2),
          width: slot * 0.6,
          height: barHeight,
        ),
        const Radius.circular(1.5),
      );
      final isInside = centre >= selected.left && centre <= selected.right;
      canvas.drawRRect(bar, isInside ? inside : outside);
    }
  }

  void _paintSelection(Canvas canvas, Size size, _Span selected) {
    final area = Rect.fromLTRB(selected.left, 0, selected.right, size.height);
    canvas.drawRect(
      area,
      Paint()..color = palette.accent.withValues(alpha: 0.12),
    );
    final edge = Paint()..color = palette.accent;
    canvas
      ..drawRect(Rect.fromLTWH(selected.left, 0, _edgeWidth, size.height), edge)
      ..drawRect(
        Rect.fromLTWH(selected.right - _edgeWidth, 0, _edgeWidth, size.height),
        edge,
      );
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.peaks != peaks ||
      oldDelegate.window != window ||
      oldDelegate.clip != clip ||
      oldDelegate.palette != palette;
}

typedef _Span = ({double left, double right});
