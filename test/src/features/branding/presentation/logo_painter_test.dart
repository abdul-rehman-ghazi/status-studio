import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/branding/domain/logo_pose.dart';
import 'package:status_studio/src/features/branding/presentation/logo_mark.dart';
import 'package:status_studio/src/theme/app_theme.dart';

void main() {
  test('logo_painter_uses_the_rest_pose_by_default', () {
    final painter = LogoPainter(
      tile: AppColors.accent,
      ink: AppColors.onAccent,
    );

    expect(painter.pose, same(LogoPose.rest));
  });

  test('logo_painter_repaints_when_the_pose_changes', () {
    final before = LogoPainter(tile: AppColors.accent, ink: AppColors.onAccent);
    final after = LogoPainter(
      tile: AppColors.accent,
      ink: AppColors.onAccent,
      pose: const LogoPose(bracketInset: 3, barHalfLengths: [8, 15, 20, 13, 7]),
    );

    expect(after.shouldRepaint(before), isTrue);
  });
}
