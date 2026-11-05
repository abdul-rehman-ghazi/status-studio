import 'dart:io';

import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/clip/presentation/clip_player.dart';
import 'package:status_studio/src/features/reel/application/fine_tune_draft_saver.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/transcript/application/script_editing_service.dart';
import 'package:status_studio/src/features/transcript/data/transcript_store.dart';
import 'package:status_studio/src/features/transcript/domain/transcript.dart';

import 'fake_video_player.dart';
import 'fixtures.dart';
import 'pump_app.dart';

/// Remembers what Fine-tune saves instead of writing files.
class RecordingScriptEditingService extends ScriptEditingService {
  RecordingScriptEditingService()
    : super(
        store: Future.value(
          TranscriptStore(
            Directory.systemTemp.createTempSync('fine_tune'),
            clock: DateTime.now,
          ),
        ),
      );

  final saved = <Transcript>[];

  @override
  Future<void> saveCorrected(
    SourceVideo video,
    ScriptLanguage language,
    Transcript corrected,
  ) async => saved.add(corrected);
}

/// Opens [route] (a Fine-tune step) over a draft with lines 1–3 picked.
Future<void> pumpFineTuneStep(
  WidgetTester tester,
  String route, {
  VideoPlayerFactory playerFactory = fakePlayerFactory,
  ReelDraft? draft,
  List<double>? waveformPeaks,
  ScriptEditingService? scriptEditing,
  FineTuneDraftSaver? fineTuneSaver,
  List<Override> overrides = const [],
}) => pumpRoutes(
  tester,
  [route],
  setup: TestSetup(
    overrides: [
      draftOverride(draft ?? pickedDraft),
      scriptEditingServiceProvider.overrideWithValue(
        scriptEditing ?? RecordingScriptEditingService(),
      ),
      ...overrides,
    ],
    playerFactory: playerFactory,
    waveformPeaks: waveformPeaks,
    fineTuneSaver: fineTuneSaver,
  ),
);

/// The fake clip's window starts 5 s before the clip, so its file time is
/// video time minus that start.
Duration fileTime(Duration videoTime) =>
    videoTime - (pickedDraft.clip!.start - const Duration(seconds: 5));
