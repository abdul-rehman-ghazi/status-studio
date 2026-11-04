import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/branding/presentation/launch_splash.dart';

Future<void> _pumpSplash(
  WidgetTester tester, {
  MediaQueryData media = const MediaQueryData(),
  VoidCallback? onAppTap,
}) => tester.pumpWidget(
  MediaQuery(
    data: media,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: LaunchSplash(
        child: GestureDetector(
          onTap: onAppTap,
          child: const ColoredBox(
            color: Color(0xFFFFFFFF),
            child: Center(child: Text('Home')),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('splash_covers_the_app_on_the_first_frame', (tester) async {
    await _pumpSplash(tester);

    expect(find.byKey(LaunchSplash.overlayKey), findsOneWidget);
  });

  testWidgets('app_is_built_under_the_splash', (tester) async {
    await _pumpSplash(tester);

    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('splash_is_removed_when_the_animation_ends', (tester) async {
    await _pumpSplash(tester);

    await tester.pumpAndSettle();

    expect(find.byKey(LaunchSplash.overlayKey), findsNothing);
  });

  testWidgets('splash_is_skipped_when_animations_are_disabled', (tester) async {
    await _pumpSplash(
      tester,
      media: const MediaQueryData(disableAnimations: true),
    );

    expect(find.byKey(LaunchSplash.overlayKey), findsNothing);
  });

  testWidgets('taps_do_not_reach_the_app_while_the_splash_shows', (
    tester,
  ) async {
    var appTaps = 0;
    await _pumpSplash(tester, onAppTap: () => appTaps++);

    await tester.tapAt(const Offset(10, 10));

    expect(appTaps, 0);
  });
}
