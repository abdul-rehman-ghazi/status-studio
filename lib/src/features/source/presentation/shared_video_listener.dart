import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/features/reel/application/fine_tune_draft_saver.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/source/data/incoming_video_source.dart';
import 'package:status_studio/src/features/source/domain/incoming_video.dart';
import 'package:status_studio/src/routing/app_router.dart';

final _incomingVideosProvider = StreamProvider<IncomingVideo>(
  (ref) => ref.watch(incomingVideoSourceProvider).videos,
);

/// Screens where no reel is being made, so a shared video needs no question.
const _screensWithoutAReel = {
  AppRoutes.home,
  AppRoutes.source,
  AppRoutes.done,
  AppRoutes.settings,
};

/// Whether opening a shared video would close a reel the user is making.
bool sharedVideoWouldCloseAReel({
  required String currentPath,
  required ReelDraft draft,
}) => draft.video != null && !_screensWithoutAReel.contains(currentPath);

/// Opens Source for every video shared into the app, asking first when it
/// would close a reel in progress (spec FR-1).
class SharedVideoListener extends ConsumerStatefulWidget {
  const SharedVideoListener({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<SharedVideoListener> createState() =>
      _SharedVideoListenerState();
}

class _SharedVideoListenerState extends ConsumerState<SharedVideoListener> {
  var _asking = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(_incomingVideosProvider, (previous, next) {
      switch (next) {
        case AsyncData(:final value):
          unawaited(_open(value));
        case AsyncError(:final error):
          _showFailure(error);
        case AsyncLoading():
          break;
      }
    });
    return widget.child;
  }

  Future<void> _open(IncomingVideo video) async {
    final router = ref.read(appRouterProvider);
    final wouldClose = sharedVideoWouldCloseAReel(
      currentPath: _currentPath(router),
      draft: ref.read(reelDraftProvider),
    );
    if (wouldClose && !await _confirmNewReel()) {
      await _deleteStagedCopy(video);
      return;
    }
    // The top screen is animated out, not removed, so it is still mounted
    // when the draft is reset and would then keep the empty draft instead of
    // the last edits (FR-24): save them here.
    if (_isOnFineTune(router)) {
      await ref
          .read(fineTuneDraftSaverProvider)
          .save(ref.read(reelDraftProvider));
    }
    router.go(AppRoutes.home);
    // The screens of the old reel read the draft until they are gone, so it
    // is only reset once Home has replaced them.
    await SchedulerBinding.instance.endOfFrame;
    ref.read(reelDraftProvider.notifier).startNew();
    unawaited(router.push<void>(AppRoutes.source, extra: video));
  }

  /// Only a reel that has reached Fine-tune is worth keeping (FR-24); a
  /// script still being written is saved by its own file.
  bool _isOnFineTune(GoRouter router) => const {
    AppRoutes.fineTune,
    AppRoutes.lyrics,
    AppRoutes.style,
  }.contains(_currentPath(router));

  /// The shared file waits in the app's incoming folder; leaving it would
  /// keep a large video until the stale-copy sweep.
  Future<void> _deleteStagedCopy(IncomingVideo video) async {
    try {
      await File(video.path).delete();
    } on FileSystemException {
      // Already gone, or the sweep will take it.
    }
  }

  /// `currentConfiguration.uri` stays at the first route when screens are
  /// pushed, so the top route's state is the one to read.
  String _currentPath(GoRouter router) {
    final configuration = router.routerDelegate.currentConfiguration;
    return configuration.isEmpty ? AppRoutes.home : router.state.uri.path;
  }

  Future<bool> _confirmNewReel() async {
    final context = _navigatorContext();
    if (context == null || _asking) {
      return false;
    }
    _asking = true;
    try {
      final start = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Start a new reel from this video?'),
          content: const Text("The one you're making will close."),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Start'),
            ),
          ],
        ),
      );
      return start ?? false;
    } finally {
      _asking = false;
    }
  }

  void _showFailure(Object error) {
    final context = _navigatorContext();
    if (context == null) {
      return;
    }
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(errorMessageFor(error))));
  }

  BuildContext? _navigatorContext() =>
      ref.read(appRouterProvider).routerDelegate.navigatorKey.currentContext;
}
