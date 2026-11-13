import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/features/transcript/application/groq_usage_controller.dart';
import 'package:status_studio/src/features/transcript/presentation/groq_usage_text.dart';

/// Asks first when [needed] is more audio than is left of Groq's allowance
/// as this phone counts it (spec FR-45); true to go on.
Future<bool> goOnWhenGroqIsShort(
  BuildContext context,
  WidgetRef ref,
  Duration needed,
) async {
  final usage = await ref.read(groqUsageProvider.future);
  final allowance = usage.firstToRunOutAt(DateTime.now());
  if (needed <= allowance.left || !context.mounted) {
    return true;
  }
  final neededMinutes = (needed.inSeconds / 60).ceil();
  final goOn = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Not enough Groq time left'),
      content: Text(
        'This needs about $neededMinutes min of audio; about '
        '${audioAmount(allowance.left)} are left '
        '${periodName(allowance.period)}. Groq stops when it runs out. The '
        'lines written so far are kept, and getting the script again carries '
        'on from there later.',
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
