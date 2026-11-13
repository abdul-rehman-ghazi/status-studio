import 'package:flutter/material.dart';

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
