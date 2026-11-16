import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:status_studio/src/app.dart';
import 'package:status_studio/src/core/cache_cleanup.dart';
import 'package:status_studio/src/features/appearance/application/theme_choice_controller.dart';
import 'package:status_studio/src/features/appearance/data/theme_choice_store.dart';
import 'package:status_studio/src/features/appearance/domain/theme_choice.dart';
import 'package:status_studio/src/features/export/application/renderer.dart';
import 'package:status_studio/src/features/library/data/recent_reels_repository.dart';
import 'package:status_studio/src/features/source/application/yt_dlp_updater.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/style/application/caption_appearance_memory.dart';
import 'package:status_studio/src/features/style/data/caption_appearance_store.dart';
import 'package:status_studio/src/features/style/domain/caption_settings.dart';
import 'package:status_studio/src/features/topic/data/topic_store.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer(
    overrides: [
      savedThemeChoiceProvider.overrideWithValue(await _savedThemeChoice()),
      savedCaptionAppearanceProvider.overrideWithValue(
        await _savedCaptionAppearance(),
      ),
    ],
  );
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const StatusStudioApp(),
    ),
  );
  // After the first frame, so housekeeping never delays the app opening.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_cleanUp(container));
    if (defaultTargetPlatform == TargetPlatform.android &&
        _weeklyYtDlpUpdates) {
      unawaited(_updateYtDlp(container));
    }
  });
}

/// Linked videos' transcripts never expire (FR-44); files of the topic
/// search go (FR-43).
Future<void> _deleteOldTopics(ProviderContainer container) async {
  final topics = await container.read(topicStoreProvider.future);
  await topics.deleteRetired();
}

/// Reels made before M54 recorded no source; the owner chose to delete
/// them rather than keep an "Older reels" section (FR-44).
Future<void> _deleteReelsWithoutSource(ProviderContainer container) =>
    container.read(recentReelsRepositoryProvider).deleteWithoutSource();

/// A render killed halfway leaves its MP4 and caption images (FR-49).
Future<void> _deleteStrayReelFiles(ProviderContainer container) async =>
    container
        .read(recentReelsRepositoryProvider)
        .deleteStrayFiles(await reelsDirectory(), now: DateTime.now());

/// F-Droid's build turns the weekly update off with
/// `--dart-define=WEEKLY_YTDLP_UPDATES=false`, as F-Droid's build of Seal
/// (another youtubedl-android app) does: F-Droid frowns on code fetched
/// without asking. Update downloader in Settings still works (FR-35).
const _weeklyYtDlpUpdates = bool.fromEnvironment(
  'WEEKLY_YTDLP_UPDATES',
  defaultValue: true,
);

/// A failed update isn't recorded, so the next start tries again (FR-35).
Future<void> _updateYtDlp(ProviderContainer container) async {
  try {
    await container.read(ytDlpUpdaterProvider).updateIfDue(DateTime.now());
  } on Exception catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'yt-dlp update',
      ),
    );
  }
}

/// Read while the native launch screen still shows, so the first frame
/// is already in the chosen theme (spec FR-32).
Future<ThemeChoice> _savedThemeChoice() => _readSetting(
  ThemeChoiceStore(SharedPreferencesAsync()).read,
  fallback: ThemeChoice.system,
  library: 'theme choice',
);

/// Read with the theme, so the first new reel starts from the caption
/// appearance used last (spec FR-7).
Future<CaptionAppearance> _savedCaptionAppearance() => _readSetting(
  CaptionAppearanceStore(SharedPreferencesAsync()).read,
  fallback: const CaptionAppearance(),
  library: 'caption appearance',
);

Future<T> _readSetting<T>(
  Future<T> Function() read, {
  required T fallback,
  required String library,
}) async {
  try {
    return await read();
  } on Object catch (error, stackTrace) {
    // Unreadable settings must not stop the app opening; the fallback is
    // the default anyway.
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: library,
      ),
    );
    return fallback;
  }
}

Future<void> _cleanUp(ProviderContainer container) async {
  try {
    await cleanUpOnStart(
      sources: container
          .read(sourceCacheProvider.future)
          .then((cache) => cache.root),
      scripts: container.read(transcriptStoreProvider.future),
      now: DateTime.now(),
    );
    await _deleteOldTopics(container);
    await _deleteReelsWithoutSource(container);
    await _deleteStrayReelFiles(container);
  } on Object catch (error, stackTrace) {
    // A failed cleanup only leaves old files behind; report and carry on.
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'startup cleanup',
      ),
    );
  }
}
