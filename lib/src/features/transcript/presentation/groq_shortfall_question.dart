import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/transcript/application/groq_allowance_controller.dart';
import 'package:status_studio/src/features/transcript/presentation/groq_allowance_text.dart';

/// Asks first when [needed] is more audio than Groq has left this hour
/// (spec FR-45); true to go on. Nothing to ask without a figure.
Future<bool> goOnWhenGroqIsShort(
  BuildContext context,
  WidgetRef ref,
  Duration needed,
) async {
  final allowance = await ref.read(groqAllowanceProvider.future);
  final now = DateTime.now();
  if (allowance == null ||
      needed <= allowance.leftAt(now) ||
      !context.mounted) {
    return true;
  }
  final neededMinutes = (needed.inSeconds / 60).ceil();
  final left = minutesLeft(allowance, now);
  final reset = minutesUntilReset(allowance, now);
  final goOn = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Not enough Groq time left'),
      content: Text(
        'This needs about $neededMinutes min of audio; $left min are left '
        'this hour. Groq stops when it runs out. The lines written so far '
        'are kept, and getting the script again carries on after the reset, '
        'in $reset min.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Go on'),
        ),
      ],
    ),
  );
  return goOn ?? false;
}
