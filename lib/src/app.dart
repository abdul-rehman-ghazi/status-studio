import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/branding/presentation/launch_splash.dart';
import 'package:status_studio/src/features/source/presentation/shared_video_listener.dart';
import 'package:status_studio/src/routing/app_router.dart';
import 'package:status_studio/src/theme/app_theme.dart';

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
        return splashEnabled ? LaunchSplash(child: routed) : routed;
      },
    );
  }
}
