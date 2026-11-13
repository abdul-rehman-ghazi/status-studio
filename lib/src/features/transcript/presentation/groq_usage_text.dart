import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/features/settings/application/groq_settings_controller.dart';
import 'package:status_studio/src/features/transcript/application/groq_usage_controller.dart';
import 'package:status_studio/src/features/transcript/domain/groq_usage.dart';

/// "41 min", "6 h 20 min" or "8 h"; whole minutes, rounded down.
String audioAmount(Duration amount) {
  final hours = amount.inHours;
  final minutes = amount.inMinutes % 60;
  if (hours == 0) {
    return '$minutes min';
  }
  return minutes == 0 ? '$hours h' : '$hours h $minutes min';
}

String periodName(AllowancePeriod period) => switch (period) {
  AllowancePeriod.hour => 'this hour',
  AllowancePeriod.day => 'today',
};

String _clock(BuildContext context, DateTime time) =>
    MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(time));

/// "About 41 min of Groq audio left this hour" under Get (spec FR-45),
/// shown once a key is saved.
class GroqUsageHint extends ConsumerWidget {
  const GroqUsageHint({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasKey = ref.watch(groqKeySavedProvider).value ?? false;
    final usage = ref.watch(groqUsageProvider).value;
    if (!hasKey || usage == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: HintText(_text(context, usage, DateTime.now())),
    );
  }

  String _text(BuildContext context, GroqUsage usage, DateTime now) {
    if (usage.blockedUntil case final until? when usage.isBlockedAt(now)) {
      return "Groq's limit is reached until ${_clock(context, until)}";
    }
    final AudioLeft(:left, :period) = usage.firstToRunOutAt(now);
    return 'About ${audioAmount(left)} of Groq audio left ${periodName(period)}';
  }
}

/// Settings' lines under "Key works" (spec FR-45).
class GroqUsageDetails extends ConsumerWidget {
  const GroqUsageDetails({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(groqUsageProvider).value;
    if (usage == null) {
      return const SizedBox.shrink();
    }
    final now = DateTime.now();
    final hour = audioAmount(usage.leftThisHourAt(now));
    final day = audioAmount(usage.leftTodayAt(now));
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('About $hour of ${audioAmount(freeHourlyAudio)} left this hour'),
          Text('About $day of ${audioAmount(freeDailyAudio)} left today'),
          HintText(_source(context, usage, now)),
        ],
      ),
    );
  }

  String _source(BuildContext context, GroqUsage usage, DateTime now) {
    if (usage.blockedUntil case final until? when usage.isBlockedAt(now)) {
      return "Groq's limit is reached until ${_clock(context, until)}";
    }
    return 'Counted on this phone, free plan';
  }
}
