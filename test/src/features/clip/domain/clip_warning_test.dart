import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/clip/domain/clip_range.dart';
import 'package:status_studio/src/features/clip/domain/clip_warning.dart';

ClipRange clipOf(Duration length) => ClipRange(
  start: const Duration(seconds: 10),
  end: length + const Duration(seconds: 10),
);

void main() {
  test('warns_only_above_sixty_seconds', () {
    final exactlySixty = clipOf(const Duration(seconds: 60));
    final justOver = clipOf(const Duration(milliseconds: 60500));

    final warnings = [
      isLongerThanStatusLimit(exactlySixty),
      isLongerThanStatusLimit(justOver),
    ];

    expect(warnings, [false, true]);
  });
}
