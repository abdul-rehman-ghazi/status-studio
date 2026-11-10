import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:status_studio/src/app.dart';
import 'package:status_studio/src/core/cache_cleanup.dart';
import 'package:status_studio/src/features/appearance/application/theme_choice_controller.dart';
import 'package:status_studio/src/features/appearance/data/theme_choice_store.dart';
import 'package:status_studio/src/features/appearance/domain/theme_choice.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer(
    overrides: [
      savedThemeChoiceProvider.overrideWithValue(await _savedThemeChoice()),
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
  });
}

/// Read while the native launch screen still shows, so the first frame
/// is already in the chosen theme (spec FR-32).
Future<ThemeChoice> _savedThemeChoice() async {
  try {
    return await ThemeChoiceStore(SharedPreferencesAsync()).read();
  } on Object catch (error, stackTrace) {
    // Unreadable settings must not stop the app opening; System is the
    // default anyway.
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'theme choice',
      ),
    );
    return ThemeChoice.system;
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
