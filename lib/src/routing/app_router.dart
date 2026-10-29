import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/features/home/presentation/home_screen.dart';
import 'package:status_studio/src/features/settings/presentation/settings_screen.dart';
import 'package:status_studio/src/features/source/presentation/source_screen.dart';

abstract final class AppRoutes {
  static const home = '/';
  static const source = '/source';
  static const processing = '/processing';
  static const script = '/script';
  static const fineTune = '/fine-tune';
  static const style = '/style';
  static const export = '/export';
  static const done = '/done';
  static const settings = '/settings';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.source,
        builder: (context, state) => const SourceScreen(),
      ),
      _placeholderRoute(AppRoutes.processing),
      _placeholderRoute(AppRoutes.script),
      _placeholderRoute(AppRoutes.fineTune),
      _placeholderRoute(AppRoutes.style),
      _placeholderRoute(AppRoutes.export),
      _placeholderRoute(AppRoutes.done),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

GoRoute _placeholderRoute(String path) => GoRoute(
  path: path,
  builder: (context, state) => Scaffold(appBar: AppBar(title: Text(path))),
);
