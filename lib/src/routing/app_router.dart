import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/features/clip/presentation/fine_tune_screen.dart';
import 'package:status_studio/src/features/export/presentation/done_screen.dart';
import 'package:status_studio/src/features/export/presentation/export_screen.dart';
import 'package:status_studio/src/features/home/presentation/home_screen.dart';
import 'package:status_studio/src/features/settings/presentation/settings_screen.dart';
import 'package:status_studio/src/features/source/presentation/source_screen.dart';
import 'package:status_studio/src/features/style/presentation/style_screen.dart';
import 'package:status_studio/src/features/transcript/presentation/processing_screen.dart';
import 'package:status_studio/src/features/transcript/presentation/script_screen.dart';

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
      GoRoute(
        path: AppRoutes.processing,
        builder: (context, state) => const ProcessingScreen(),
      ),
      GoRoute(
        path: AppRoutes.script,
        builder: (context, state) => const ScriptScreen(),
      ),
      GoRoute(
        path: AppRoutes.fineTune,
        builder: (context, state) => const FineTuneScreen(),
      ),
      GoRoute(
        path: AppRoutes.style,
        builder: (context, state) => const StyleScreen(),
      ),
      GoRoute(
        path: AppRoutes.export,
        builder: (context, state) => const ExportScreen(),
      ),
      GoRoute(
        path: AppRoutes.done,
        builder: (context, state) => const DoneScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
