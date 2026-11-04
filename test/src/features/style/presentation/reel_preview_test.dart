import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/app.dart';
import 'package:status_studio/src/features/source/application/clip_source_controller.dart';
import 'package:status_studio/src/features/style/presentation/reel_preview.dart';
import 'package:status_studio/src/features/transcript/application/fake_script_pipeline.dart';
import 'package:status_studio/src/routing/app_router.dart';
import 'package:video_player/video_player.dart';

import '../../../../helpers/fake_video_player.dart';
import '../../../../helpers/fixtures.dart';
import '../../../../helpers/pump_app.dart';

/// Style with the clip already downloaded, as after Fine-tune.
Future<void> pumpStyleWithClip(
  WidgetTester tester, {
  VideoPlayerController Function(File source)? playerFactory,
}) async {
  await pumpRoutes(
    tester,
    [AppRoutes.style],
    setup: TestSetup(
      overrides: [draftOverride(pickedDraft)],
      playerFactory: playerFactory ?? fakePlayerFactory,
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(StatusStudioApp)),
  );
  await container
      .read(clipSourceProvider(sampleVideo.videoId).notifier)
      .prepareFor(sampleVideo, pickedDraft.clip!);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('preview_shows_clip_frame_once_downloaded', (tester) async {
    await pumpStyleWithClip(tester);

    expect(
      find.descendant(
        of: find.byType(ReelPreview),
        matching: find.byType(VideoPlayer),
      ),
      findsWidgets,
    );
  });

  testWidgets('preview_frame_is_at_clip_start', (tester) async {
    final players = <FakeVideoPlayerController>[];
    await pumpStyleWithClip(
      tester,
      playerFactory: (source) {
        final player = FakeVideoPlayerController();
        players.add(player);
        return player;
      },
    );

    // The fake clip file starts 5 s before the clip.
    expect(players.single.value.position, const Duration(seconds: 5));
  });

  testWidgets('unplayable_clip_keeps_placeholder', (tester) async {
    await pumpStyleWithClip(tester, playerFactory: brokenPlayerFactory);

    expect(
      find.descendant(
        of: find.byType(ReelPreview),
        matching: find.byIcon(Icons.movie_outlined),
      ),
      findsOneWidget,
    );
  });

  testWidgets('preview_shows_only_the_first_caption_line', (tester) async {
    await pumpStyleWithClip(tester);

    Finder inPreview(String text) => find.descendant(
      of: find.byType(ReelPreview),
      matching: find.text(text),
    );
    expect(inPreview(sampleTranscript.lines[1].text), findsOneWidget);
    expect(inPreview(sampleTranscript.lines[2].text), findsNothing);
  });
}
