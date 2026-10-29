import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/routing/app_router.dart';
import 'package:status_studio/src/theme/app_theme.dart';

class StatusStudioApp extends ConsumerWidget {
  const StatusStudioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Status Studio',
      theme: AppTheme.dark(),
      routerConfig: ref.watch(appRouterProvider),
      debugShowCheckedModeBanner: false,
    );
  }
}
