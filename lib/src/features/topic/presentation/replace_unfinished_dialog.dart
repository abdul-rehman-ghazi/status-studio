import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/topic/application/unfinished_link_work.dart';

/// Asked before anything replaces a video's unfinished work (spec FR-43,
/// FR-44). True for Start.
Future<bool> askToReplaceUnfinished(BuildContext context) async {
  final start = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: const Text(
        'Start new clips from this video? The unfinished one will be '
        'deleted.',
      ),
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

/// One unfinished piece of work per linked video (spec FR-43): with some,
/// asks first and deletes it on Start. False when the user keeps it.
Future<bool> clearUnfinishedLinkWork(
  BuildContext context,
  WidgetRef ref,
  String youTubeId,
) async {
  final works = ref.read(unfinishedLinkWorksProvider);
  final unfinished = await works.unfinishedLinkWork(youTubeId);
  if (unfinished.isEmpty) {
    return true;
  }
  if (!context.mounted || !await askToReplaceUnfinished(context)) {
    return false;
  }
  await works.delete(unfinished);
  return true;
}
