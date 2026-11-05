import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/error_messages.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/source/data/incoming_video_source.dart';
import 'package:status_studio/src/features/source/domain/incoming_video.dart';
import 'package:status_studio/src/routing/app_router.dart';

final _incomingVideosProvider = StreamProvider<IncomingVideo>(
  (ref) => ref.watch(incomingVideoSourceProvider).videos,
);

/// Screens where no reel is being made, so a shared video needs no question.
const _screensWithoutAReel = {AppRoutes.home, AppRoutes.source, AppRoutes.done};

/// Whether opening a shared video would close a reel the user is making.
bool sharedVideoWouldCloseAReel({
  required String currentPath,
  required ReelDraft draft,
}) => draft.video != null && !_screensWithoutAReel.contains(currentPath);

/// Opens Source for every video shared into the app, asking first when it
/// would close a reel in progress (spec FR-1).
class SharedVideoListener extends ConsumerWidget {
  const SharedVideoListener({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(_incomingVideosProvider, (previous, next) {
      switch (next) {
        case AsyncData(:final value):
          unawaited(_open(ref, value));
        case AsyncError(:final error):
          _showFailure(ref, error);
        case AsyncLoading():
          break;
      }
    });
    return child;
  }

  Future<void> _open(WidgetRef ref, IncomingVideo video) async {
    final router = ref.read(appRouterProvider);
    final wouldClose = sharedVideoWouldCloseAReel(
      currentPath: router.routerDelegate.currentConfiguration.uri.path,
      draft: ref.read(reelDraftProvider),
    );
    if (wouldClose && !await _confirmNewReel(ref)) {
      return;
    }
    ref.read(reelDraftProvider.notifier).startNew();
    router.go(AppRoutes.home);
    unawaited(router.push<void>(AppRoutes.source, extra: video));
  }

  Future<bool> _confirmNewReel(WidgetRef ref) async {
    final context = _navigatorContext(ref);
    if (context == null) {
      return false;
    }
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
  }

  void _showFailure(WidgetRef ref, Object error) {
    final context = _navigatorContext(ref);
    if (context == null) {
      return;
    }
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(errorMessageFor(error))));
  }

  BuildContext? _navigatorContext(WidgetRef ref) =>
      ref.read(appRouterProvider).routerDelegate.navigatorKey.currentContext;
}
