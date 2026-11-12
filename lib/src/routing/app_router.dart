import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/features/about/presentation/about_section.dart';
import 'package:status_studio/src/features/about/presentation/support_section.dart';
import 'package:status_studio/src/features/appearance/presentation/appearance_section.dart';
import 'package:status_studio/src/features/clip/presentation/fine_tune_screen.dart';
import 'package:status_studio/src/features/clip/presentation/lyrics_screen.dart';
import 'package:status_studio/src/features/export/presentation/done_screen.dart';
import 'package:status_studio/src/features/export/presentation/export_screen.dart';
import 'package:status_studio/src/features/home/presentation/home_screen.dart';
import 'package:status_studio/src/features/settings/presentation/background_work_section.dart';
import 'package:status_studio/src/features/settings/presentation/downloader_section.dart';
import 'package:status_studio/src/features/settings/presentation/groq_section.dart';
import 'package:status_studio/src/features/settings/presentation/settings_page.dart';
import 'package:status_studio/src/features/settings/presentation/settings_screen.dart';
import 'package:status_studio/src/features/source/domain/incoming_video.dart';
import 'package:status_studio/src/features/source/presentation/link_screen.dart';
import 'package:status_studio/src/features/source/presentation/source_screen.dart';
import 'package:status_studio/src/features/topic/domain/topic_request.dart';
import 'package:status_studio/src/features/topic/presentation/review_cuts_screen.dart';

abstract final class AppRoutes {
  static const home = '/';
  static const source = '/source';
  static const link = '/link';
  static const reviewCuts = '/link/cuts';
  static const fineTune = '/fine-tune';
  static const lyrics = '/fine-tune/lyrics';
  static const export = '/export';
  static const done = '/done';

  /// Done for the recent reel [reelId] (FR-11).
  static String doneFor(String reelId) =>
      Uri(path: done, queryParameters: {'id': reelId}).toString();
  static const settings = '/settings';

  /// One screen per Settings category (spec FR-12a, FR-16, FR-31, FR-32).
  static const appearanceSettings = '/settings/appearance';
  static const groqSettings = '/settings/groq';
  static const backgroundSettings = '/settings/background';
  static const downloaderSettings = '/settings/downloader';
  static const supportSettings = '/settings/support';
  static const aboutSettings = '/settings/about';
}

/// Lets screens react when another screen covers them, e.g. to pause.
final routeObserverProvider = Provider<RouteObserver<ModalRoute<void>>>(
  (ref) => RouteObserver<ModalRoute<void>>(),
);

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.home,
    observers: [ref.watch(routeObserverProvider)],
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.source,
        builder: (context, state) => SourceScreen(
          sharedVideo: state.extra is IncomingVideo
              ? state.extra! as IncomingVideo
              : null,
        ),
      ),
      GoRoute(
        path: AppRoutes.link,
        builder: (context, state) => LinkScreen(
          sharedLink: switch (state.extra) {
            IncomingLink(:final link) => link,
            _ => null,
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.fineTune,
        builder: (context, state) => const FineTuneScreen(),
      ),
      GoRoute(
        path: AppRoutes.lyrics,
        builder: (context, state) => const LyricsScreen(),
      ),
      GoRoute(
        path: AppRoutes.export,
        builder: (context, state) => const ExportScreen(),
      ),
      GoRoute(
        path: AppRoutes.done,
        builder: (context, state) =>
            DoneScreen(reelId: state.uri.queryParameters['id'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.reviewCuts,
        builder: (context, state) =>
            ReviewCutsScreen(request: state.extra! as TopicRequest),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
        routes: [
          GoRoute(
            path: 'appearance',
            builder: (context, state) => const SettingsPage(
              title: 'Appearance',
              section: AppearanceSection(),
            ),
          ),
          GoRoute(
            path: 'groq',
            builder: (context, state) =>
                const SettingsPage(title: 'Groq key', section: GroqSection()),
          ),
          GoRoute(
            path: 'background',
            builder: (context, state) => const SettingsPage(
              title: 'Background work',
              section: BackgroundWorkSection(),
            ),
          ),
          GoRoute(
            path: 'downloader',
            builder: (context, state) => const SettingsPage(
              title: 'Downloader',
              section: DownloaderSection(),
            ),
          ),
          GoRoute(
            path: 'support',
            builder: (context, state) =>
                const SettingsPage(title: 'Support', section: SupportSection()),
          ),
          GoRoute(
            path: 'about',
            builder: (context, state) =>
                const SettingsPage(title: 'About', section: AboutSection()),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
