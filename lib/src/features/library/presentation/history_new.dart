import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/features/library/domain/video_history.dart';
import 'package:status_studio/src/features/library/presentation/unfinished_work_actions.dart';
import 'package:status_studio/src/features/reel/application/fine_tune_drafts_controller.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/source/domain/incoming_video.dart';
import 'package:status_studio/src/features/source/domain/script_language.dart';
import 'package:status_studio/src/features/source/domain/source_video.dart';
import 'package:status_studio/src/features/source/domain/video_link.dart';
import 'package:status_studio/src/features/topic/domain/moment_source.dart';
import 'package:status_studio/src/features/topic/domain/topic_request.dart';
import 'package:status_studio/src/features/topic/presentation/replace_unfinished_dialog.dart';
import 'package:status_studio/src/features/transcript/application/script_opening_notice.dart';
import 'package:status_studio/src/features/transcript/application/script_progress_controller.dart';
import 'package:status_studio/src/routing/app_router.dart';

/// New on a History row (spec FR-44): new clips from the same video,
/// reusing its saved script, after asking when unfinished work would go.
Future<void> startNewFrom(
  BuildContext context,
  WidgetRef ref,
  VideoHistory group,
) => switch (group.key) {
  LinkedVideoKey(:final videoKey) => _newFromLink(context, ref, (
    group: group,
    videoKey: videoKey,
  )),
  LocalVideoKey(:final videoId) => _newFromLocal(context, ref, (
    group: group,
    videoId: videoId,
  )),
};

/// Review cuts on the saved script in its language, with no moments; with
/// no saved script it writes one, as Get the script does. A YouTube link
/// whose facts weren't kept (before M53) is read again on From a link
/// (*Claude's call*); another site's page can't be rebuilt from its key,
/// so From a link opens empty (M75).
Future<void> _newFromLink(
  BuildContext context,
  WidgetRef ref,
  ({VideoHistory group, String videoKey}) target,
) async {
  final video = target.group.facts.linkedVideo;
  if (video == null) {
    final key = target.videoKey;
    unawaited(
      context.push(
        AppRoutes.link,
        extra: isYouTubeVideoKey(key)
            ? IncomingLink(youTubeWatchUrl(key))
            : null,
      ),
    );
    return;
  }
  if (!await clearUnfinishedLinkWork(context, ref, target.videoKey)) {
    return;
  }
  if (!context.mounted) {
    return;
  }
  final request = TopicRequest(
    source: LinkedMoments(video),
    outputLanguage: _outputLanguageOf(target.group),
  );
  unawaited(context.push(AppRoutes.reviewCuts, extra: request));
}

/// The saved script's language, or From a link's default when none is
/// saved (*Claude's call*).
ScriptLanguage _outputLanguageOf(VideoHistory group) {
  final saved = group.facts.scriptLanguage;
  return outputLanguages.contains(saved) ? saved! : ScriptLanguage.urdu;
}

/// On Android, Review cuts on the kept video's saved script, as a link's
/// New does (spec FR-51, owner 2026-11-16); on iOS, which has no Review
/// cuts, Fine-tune · Video as before.
Future<void> _newFromLocal(
  BuildContext context,
  WidgetRef ref,
  ({VideoHistory group, String videoId}) target,
) async {
  final video = target.group.facts.localVideo;
  if (video == null || !await isStillKept(ref, target.videoId)) {
    if (context.mounted) askForTheVideoAgain(context, ref, target.videoId);
    return;
  }
  if (!context.mounted) {
    return;
  }
  if (defaultTargetPlatform == TargetPlatform.android) {
    await _momentsFromLocal(context, ref, (group: target.group, video: video));
    return;
  }
  await _wholeVideoFromLocal(context, ref, (group: target.group, video: video));
}

/// Review cuts with no moments, after asking when unfinished work of the
/// video would go (FR-44).
Future<void> _momentsFromLocal(
  BuildContext context,
  WidgetRef ref,
  ({VideoHistory group, SourceVideo video}) target,
) async {
  final video = target.video;
  if (!await clearUnfinishedLinkWork(context, ref, video.videoId)) {
    return;
  }
  if (!context.mounted) {
    return;
  }
  final request = TopicRequest(
    source: LocalMoments(video),
    outputLanguage: _outputLanguageOf(target.group),
  );
  unawaited(context.push(AppRoutes.reviewCuts, extra: request));
}

/// Fine-tune · Video on the kept file, with the saved script read back
/// (FR-14). A kept fine-tune is replaced only after asking.
Future<void> _wholeVideoFromLocal(
  BuildContext context,
  WidgetRef ref,
  ({VideoHistory group, SourceVideo video}) target,
) async {
  final video = target.video;
  if (target.group.unfinished case UnfinishedFineTune(:final fineTune)) {
    if (!context.mounted || !await askToReplaceUnfinished(context)) {
      return;
    }
    await ref.read(fineTuneDraftsProvider.notifier).delete(fineTune);
  }
  if (context.mounted) {
    _openFineTune(context, ref, (
      video: video,
      language: target.group.facts.scriptLanguage,
    ));
  }
}

void _openFineTune(
  BuildContext context,
  WidgetRef ref,
  ({SourceVideo video, ScriptLanguage? language}) opening,
) {
  ref.read(scriptOpeningNoticeProvider.notifier).clear();
  final draft = ref.read(reelDraftProvider.notifier)
    ..startNew()
    ..setVideo(opening.video);
  final language = opening.language;
  if (language != null) {
    draft.setLanguage(language);
    ref.read(scriptProgressProvider.notifier).start(opening.video, language);
  }
  unawaited(context.push(AppRoutes.fineTune));
}
