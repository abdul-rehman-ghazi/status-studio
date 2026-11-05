import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/app.dart';
import 'package:status_studio/src/core/cache_cleanup.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';

void main() {
  final container = ProviderContainer();
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
