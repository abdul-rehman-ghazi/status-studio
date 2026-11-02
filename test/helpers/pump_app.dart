import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:status_studio/src/app.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';
import 'package:status_studio/src/features/background/data/background_work_platform.dart';
import 'package:status_studio/src/features/clip/application/waveform_provider.dart';
import 'package:status_studio/src/features/clip/presentation/clip_player.dart';
import 'package:status_studio/src/features/export/application/fake_renderer.dart';
import 'package:status_studio/src/features/export/application/renderer.dart';
import 'package:status_studio/src/features/export/data/reel_actions.dart';
import 'package:status_studio/src/features/library/domain/recent_reel.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/source/data/clip_source_preparer.dart';
import 'package:status_studio/src/features/source/data/fake_video_source.dart';
import 'package:status_studio/src/features/source/data/source_cache.dart';
import 'package:status_studio/src/features/source/data/video_source.dart';
import 'package:status_studio/src/features/source/data/yt_dlp.dart';
import 'package:status_studio/src/features/style/application/clip_frame_size_provider.dart';
import 'package:status_studio/src/features/style/data/caption_translator.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/features/transcript/application/fake_script_pipeline.dart';
import 'package:status_studio/src/features/transcript/application/saved_scripts_controller.dart';
import 'package:status_studio/src/features/transcript/application/script_pipeline.dart';
import 'package:status_studio/src/features/transcript/data/model_manager.dart';
import 'package:status_studio/src/features/transcript/domain/saved_transcript.dart';
import 'package:status_studio/src/routing/app_router.dart';

import 'fake_background_work_platform.dart';
import 'fake_caption_translator.dart';
import 'fake_clip_preparer.dart';
import 'fake_model_manager.dart';
import 'fake_reel_actions.dart';
import 'fake_video_player.dart';
import 'fake_yt_dlp.dart';
import 'recording_ffmpeg.dart';
import 'saved_scripts.dart';

/// What a widget test runs the app with. Services that would touch the
/// network or a platform plugin default to fakes.
class TestSetup {
  const TestSetup({
    this.overrides = const [],
    this.videoSource = const FakeVideoSource(),
    this.playerFactory = fakePlayerFactory,
    this.clipPreparer,
    this.scriptPipeline = const FakeScriptPipeline(step: Duration.zero),
    this.waveformPeaks,
    this.renderer = const FakeRenderer(step: Duration.zero),
    this.translator = const FakeCaptionTranslator(),
    this.reelActions,
    this.recentReels = const [],
    this.savedScripts = const [],
    this.modelManager,
    this.ytDlp,
    this.backgroundWork,
  });

  final List<Override> overrides;
  final VideoSource videoSource;
  final VideoPlayerFactory playerFactory;

  /// Defaults to a fresh [FakeClipSourcePreparer].
  final ClipSourcePreparer? clipPreparer;
  final ScriptPipeline scriptPipeline;

  /// What every clip's waveform resolves to; FFmpeg never runs in tests.
  /// Without peaks the waveform stays loading.
  final List<double>? waveformPeaks;
  final Renderer renderer;
  final CaptionTranslator translator;

  /// Defaults to a fresh [FakeReelActions].
  final ReelActions? reelActions;

  /// Stored in preferences, newest first, before the app starts.
  final List<RecentReel> recentReels;

  /// The finished scripts Home lists, newest first.
  final List<SavedScript> savedScripts;

  /// Defaults to a [FakeModelManager] with nothing downloaded.
  final ModelManager? modelManager;

  /// Defaults to a fresh [FakeYtDlp]; the video source is faked anyway.
  final YtDlp? ytDlp;

  /// Defaults to a fresh [FakeBackgroundWorkPlatform].
  final BackgroundWorkPlatform? backgroundWork;

  List<Override> get allOverrides => [
    videoSourceProvider.overrideWithValue(videoSource),
    rendererProvider.overrideWithValue(renderer),
    captionTranslatorProvider.overrideWithValue(translator),
    reelActionsProvider.overrideWithValue(reelActions ?? FakeReelActions()),
    ffmpegRunnerProvider.overrideWithValue(const SilentFfmpegRunner()),
    modelManagerProvider.overrideWithValue(modelManager ?? FakeModelManager()),
    ytDlpProvider.overrideWithValue(ytDlp ?? FakeYtDlp()),
    backgroundWorkPlatformProvider.overrideWithValue(
      backgroundWork ?? FakeBackgroundWorkPlatform(),
    ),
    // The probe needs FFprobe; every test clip is 1920 × 1080.
    clipFrameSizeProvider.overrideWith(
      (ref, source) async => const OutputSize(1920, 1080),
    ),
    scriptPipelineProvider.overrideWithValue(scriptPipeline),
    savedScriptsProvider.overrideWith(
      () => FakeSavedScriptsController(savedScripts),
    ),
    videoPlayerFactoryProvider.overrideWithValue(playerFactory),
    clipSourcePreparerProvider.overrideWithValue(
      clipPreparer ?? FakeClipSourcePreparer(),
    ),
    waveformProvider.overrideWith(
      (ref, span) => switch (waveformPeaks) {
        final peaks? => Future.value(peaks),
        null => Completer<List<double>>().future,
      },
    ),
    sourceCacheProvider.overrideWith(
      (ref) async => SourceCache(Directory.systemTemp),
    ),
    ...overrides,
  ];
}

/// Pumps the whole app on a phone-sized screen (360 × 780).
Future<void> pumpApp(
  WidgetTester tester, {
  TestSetup setup = const TestSetup(),
}) async {
  tester.view
    ..physicalSize = const Size(1080, 2340)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  // Preferences live in memory, fresh for every test.
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData({
        if (setup.recentReels.isNotEmpty)
          'recentReels': jsonEncode([
            for (final reel in setup.recentReels) reel.toJson(),
          ]),
      });
  await tester.pumpWidget(
    ProviderScope(
      overrides: setup.allOverrides,
      child: const StatusStudioApp(),
    ),
  );
}

/// Opens the Source screen the way a user does: Home → New reel.
Future<void> openSource(
  WidgetTester tester, {
  TestSetup setup = const TestSetup(),
}) async {
  await pumpApp(tester, setup: setup);
  await tester.tap(find.text('New reel'));
  await tester.pumpAndSettle();
}

/// Starts the app and pushes [routes] in order on top of Home.
Future<void> pumpRoutes(
  WidgetTester tester,
  List<String> routes, {
  TestSetup setup = const TestSetup(),
}) async {
  await pumpApp(tester, setup: setup);
  final container = ProviderScope.containerOf(
    tester.element(find.byType(StatusStudioApp)),
  );
  for (final route in routes) {
    container.read(appRouterProvider).push(route).ignore();
    await tester.pumpAndSettle();
  }
}

/// Starts the reel draft at [draft] instead of an empty one.
Override draftOverride(ReelDraft draft) =>
    reelDraftProvider.overrideWith(() => _PresetDraftController(draft));

class _PresetDraftController extends ReelDraftController {
  _PresetDraftController(this.initialDraft);

  final ReelDraft initialDraft;

  @override
  ReelDraft build() => initialDraft;
}
