import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/branding/presentation/launch_splash.dart';
import 'package:status_studio/src/features/source/presentation/shared_video_listener.dart';
import 'package:status_studio/src/routing/app_router.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// The phone's text size is followed up to this, so every screen keeps
/// its layout; the owner chose a cap over unlimited growth (spec §4, M34).
const maxTextScale = 1.3;

class StatusStudioApp extends ConsumerWidget {
  const StatusStudioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final splashEnabled = ref.watch(launchSplashEnabledProvider);
    return MaterialApp.router(
      title: 'Status Studio',
      theme: AppTheme.dark(),
      routerConfig: ref.watch(appRouterProvider),
      debugShowCheckedModeBanner: false,
      builder: (context, router) {
        final routed = SharedVideoListener(
          child: router ?? const SizedBox.shrink(),
        );
        return MediaQuery.withClampedTextScaling(
          maxScaleFactor: maxTextScale,
          child: splashEnabled ? LaunchSplash(child: routed) : routed,
        );
      },
    );
  }
}
