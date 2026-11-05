import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/application/saved_scripts_controller.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';

import 'fixtures.dart';

/// A finished Urdu script of a video titled [title], [minutesOld] old.
SavedScript savedScript({required String title, required int minutesOld}) {
  return SavedScript(
    video: SourceVideo(
      videoId: 'video_$minutesOld',
      title: title,
      duration: const Duration(minutes: 6, seconds: 48),
    ),
    language: ScriptLanguage.auto,
    saved: SavedTranscript(
      transcript: fixture,
      source: 'captions',
      savedAt: DateTime(
        2026,
        11,
        2,
        12,
      ).subtract(Duration(minutes: minutesOld)),
    ),
  );
}

/// Serves [scripts] without touching the disk; widget tests can't wait on
/// real file reads.
class FakeSavedScriptsController extends SavedScriptsController {
  FakeSavedScriptsController(this.scripts);

  final List<SavedScript> scripts;

  @override
  Future<List<SavedScript>> build() async => scripts;

  @override
  Future<void> delete(SavedScript script) async {
    state = AsyncData([
      for (final kept in state.value ?? scripts)
        if (kept != script) kept,
    ]);
  }
}
