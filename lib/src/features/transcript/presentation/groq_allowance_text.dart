import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/features/transcript/application/groq_allowance_controller.dart';
import 'package:status_studio/src/features/transcript/domain/groq_allowance.dart';

/// Whole minutes, rounded down: a part minute isn't a minute of script.
int minutesLeft(GroqAllowance allowance, DateTime now) =>
    allowance.leftAt(now).inMinutes;

/// Rounded up, so a reset 20 s away reads "1 min", never "0 min".
int minutesUntilReset(GroqAllowance allowance, DateTime now) =>
    math.max(1, (allowance.resetsAt.difference(now).inSeconds / 60).ceil());

/// "41 min of Groq audio left this hour" under Get (spec FR-45); nothing
/// before Groq has reported a figure.
class GroqAllowanceHint extends ConsumerWidget {
  const GroqAllowanceHint({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowance = ref.watch(groqAllowanceProvider).value;
    if (allowance == null) {
      return const SizedBox.shrink();
    }
    final minutes = minutesLeft(allowance, DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: HintText('$minutes min of Groq audio left this hour'),
    );
  }
}

/// Settings' lines under "Key works" (spec FR-45).
class GroqAllowanceDetails extends ConsumerWidget {
  const GroqAllowanceDetails({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowance = ref.watch(groqAllowanceProvider).value;
    if (allowance == null) {
      return const SizedBox.shrink();
    }
    final now = DateTime.now();
    final left = minutesLeft(allowance, now);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Audio left: $left of ${allowance.limit.inMinutes} min this hour',
          ),
          HintText(_whenText(context, allowance, now)),
        ],
      ),
    );
  }

  String _whenText(
    BuildContext context,
    GroqAllowance allowance,
    DateTime now,
  ) {
    final localizations = MaterialLocalizations.of(context);
    String clock(DateTime time) =>
        localizations.formatTimeOfDay(TimeOfDay.fromDateTime(time));
    if (allowance.hasRefilledBy(now)) {
      return 'Refilled since ${clock(allowance.resetsAt)}';
    }
    final minutes = minutesUntilReset(allowance, now);
    return 'Resets in $minutes min · from Groq at ${clock(allowance.seenAt)}';
  }
}
