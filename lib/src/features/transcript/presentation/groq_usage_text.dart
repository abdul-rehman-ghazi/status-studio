import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/features/settings/application/groq_settings_controller.dart';
import 'package:status_studio/src/features/transcript/application/groq_usage_controller.dart';
import 'package:status_studio/src/features/transcript/domain/groq_usage.dart';
import 'package:status_studio/src/theme/app_theme.dart';

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

Duration allowanceOf(AllowancePeriod period) => switch (period) {
  AllowancePeriod.hour => freeHourlyAudio,
  AllowancePeriod.day => freeDailyAudio,
};

/// Below this share left the bar turns to the error colour.
const _lowShare = 0.15;

/// How much of an allowance is left, as a filled bar (spec FR-45).
class AllowanceBar extends StatelessWidget {
  const AllowanceBar({required this.left, required this.of, super.key});

  final Duration left;
  final Duration of;

  static const _thickness = 8.0;

  @override
  Widget build(BuildContext context) {
    final share = (left.inSeconds / of.inSeconds).clamp(0.0, 1.0);
    final fill = share < _lowShare
        ? Theme.of(context).colorScheme.error
        : context.palette.accent;
    return ClipRRect(
      borderRadius: BorderRadius.circular(_thickness / 2),
      child: LinearProgressIndicator(
        value: share,
        minHeight: _thickness,
        color: fill,
        // Muted rather than a surface colour: the bar sits both on the
        // page and on Fine-tune · Lyrics' surface card.
        backgroundColor: context.palette.textMuted.withValues(alpha: 0.2),
        semanticsLabel: 'Groq audio left',
        semanticsValue: '${audioAmount(left)} of ${audioAmount(of)}',
      ),
    );
  }
}

/// A bar of what is left and "About 41 min of Groq audio left this hour"
/// under Get (spec FR-45), shown once a key is saved.
class GroqUsageHint extends ConsumerWidget {
  const GroqUsageHint({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasKey = ref.watch(groqKeySavedProvider).value ?? false;
    final usage = ref.watch(groqUsageProvider).value;
    if (!hasKey || usage == null) {
      return const SizedBox.shrink();
    }
    final now = DateTime.now();
    final allowance = usage.firstToRunOutAt(now);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AllowanceBar(left: allowance.left, of: allowanceOf(allowance.period)),
          const SizedBox(height: 4),
          HintText(_text(context, usage, now)),
        ],
      ),
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

/// Settings' bars under "Key works" (spec FR-45).
class GroqUsageDetails extends ConsumerWidget {
  const GroqUsageDetails({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(groqUsageProvider).value;
    if (usage == null) {
      return const SizedBox.shrink();
    }
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PeriodBar(
            name: 'This hour',
            left: usage.leftThisHourAt(now),
            of: freeHourlyAudio,
          ),
          const SizedBox(height: 10),
          _PeriodBar(
            name: 'Today',
            left: usage.leftTodayAt(now),
            of: freeDailyAudio,
          ),
          const SizedBox(height: 6),
          HintText(_source(context, usage, now)),
        ],
      ),
    );
  }

  String _source(BuildContext context, GroqUsage usage, DateTime now) {
    if (usage.blockedUntil case final until? when usage.isBlockedAt(now)) {
      return "Groq's limit is reached until ${_clock(context, until)}";
    }
    return 'Estimates, counted on this phone (free plan)';
  }
}

/// "This hour        41 min of 2 h left" over its bar.
class _PeriodBar extends StatelessWidget {
  const _PeriodBar({required this.name, required this.left, required this.of});

  final String name;
  final Duration left;
  final Duration of;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(name)),
            HintText('${audioAmount(left)} of ${audioAmount(of)} left'),
          ],
        ),
        const SizedBox(height: 4),
        AllowanceBar(left: left, of: of),
      ],
    );
  }
}
