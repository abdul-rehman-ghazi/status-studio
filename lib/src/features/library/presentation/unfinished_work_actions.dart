import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/features/reel/application/fine_tune_draft_saver.dart';
import 'package:status_studio/src/features/reel/application/fine_tune_drafts_controller.dart';
import 'package:status_studio/src/features/reel/application/fine_tune_resumer.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/reel/domain/fine_tune_draft.dart';
import 'package:status_studio/src/features/source/application/is_video_kept.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/transcript/application/script_opening_notice.dart';
import 'package:status_studio/src/features/transcript/application/script_progress_controller.dart';
import 'package:status_studio/src/routing/app_router.dart';

/// What a row says when its video's kept file is gone (spec FR-1).
const chooseAgainHint = 'Choose or share the video again';

/// Asks with a one-item sheet, as long-press menus do on Android.
Future<bool> confirmAction(BuildContext context, String label) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    builder: (context) => SafeArea(
      child: ListTile(
        leading: const Icon(Icons.delete_outline),
        title: Text(label),
        onTap: () => Navigator.of(context).pop(true),
      ),
    ),
  );
  return confirmed ?? false;
}

/// A row shows "choose again" from a cached answer; the video may have been
/// imported since, so a tap that finds "gone" looks at the phone again.
Future<bool> isStillKept(WidgetRef ref, String videoId) async {
  if (ref.read(isVideoKeptProvider(videoId)).value ?? true) {
    return true;
  }
  return ref.refresh(isVideoKeptProvider(videoId).future);
}

/// The kept video is gone: say so and open Source. The script and the kept
/// fine-tune stay, and the same video chosen again finds them (spec FR-1).
void askForTheVideoAgain(BuildContext context, WidgetRef ref, String videoId) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(errorMessageFor(KeptVideoMissingException(videoId))),
    ),
  );
  ref.read(reelDraftProvider.notifier).startNew();
  unawaited(context.push(AppRoutes.source));
}

/// Continues a kept fine-tune (spec FR-24): Fine-tune opens as left, or
/// with the notice when its script is gone or changed. With the kept video
/// gone the user is asked for it again.
Future<void> continueFineTune(
  BuildContext context,
  WidgetRef ref,
  SavedFineTune fineTune,
) async {
  final videoId = fineTune.video.videoId;
  if (!await isStillKept(ref, videoId)) {
    if (context.mounted) askForTheVideoAgain(context, ref, videoId);
    return;
  }
  final outcome = await ref.read(fineTuneResumerProvider).resume(fineTune);
  if (!context.mounted) {
    return;
  }
  _openResumed(context, ref, (fineTune: fineTune, outcome: outcome));
  if (outcome is! FineTuneReady) {
    // The resumer deleted the kept fine-tune.
    ref.invalidate(fineTuneDraftsProvider);
  }
}

typedef _Resumed = ({SavedFineTune fineTune, FineTuneResume outcome});

void _openResumed(BuildContext context, WidgetRef ref, _Resumed resumed) {
  final video = resumed.fineTune.video;
  final notices = ref.read(scriptOpeningNoticeProvider.notifier);
  final draft = ref.read(reelDraftProvider.notifier);
  notices.clear();
  switch (resumed.outcome) {
    case FineTuneReady(draft: final restored):
      draft.restore(restored);
      unawaited(ref.read(fineTuneDraftSaverProvider).rememberKept(restored));
      _startScript(ref, resumed.fineTune);
    case FineTuneScriptGone(:final startOver):
      draft.restore(startOver);
      // Lyrics offers to get the script again; nothing starts unasked.
      notices.show(video.videoId, ScriptOpeningNotice.fineTuneScriptGone);
    case FineTuneScriptChanged(:final startOver):
      draft.restore(startOver);
      notices.show(video.videoId, ScriptOpeningNotice.fineTuneScriptChanged);
      _startScript(ref, resumed.fineTune);
  }
  unawaited(context.push(AppRoutes.fineTune));
}

/// Reads the saved script back, or resumes one still being written. A
/// fine-tune kept before it had lines starts nothing: Lyrics offers the
/// script (M30).
void _startScript(WidgetRef ref, SavedFineTune fineTune) {
  if (fineTune.draft.lines == null) {
    return;
  }
  ref
      .read(scriptProgressProvider.notifier)
      .start(fineTune.video, fineTune.draft.language);
}
