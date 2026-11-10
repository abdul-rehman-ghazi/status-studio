import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/presentation/section_label.dart';
import 'package:status_studio/src/features/appearance/application/theme_choice_controller.dart';
import 'package:status_studio/src/features/appearance/domain/theme_choice.dart';

/// Light, Dark or System, applied as soon as it is tapped (spec FR-32).
class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chosen = ref.watch(themeChoiceProvider);
    return RadioGroup<ThemeChoice>(
      groupValue: chosen,
      onChanged: (choice) {
        if (choice == null) {
          return;
        }
        unawaited(ref.read(themeChoiceProvider.notifier).choose(choice));
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Theme'),
          for (final choice in ThemeChoice.values) _ChoiceRow(choice),
        ],
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow(this.choice);

  final ThemeChoice choice;

  @override
  Widget build(BuildContext context) {
    return RadioListTile<ThemeChoice>(
      value: choice,
      contentPadding: EdgeInsets.zero,
      title: Text(choice.label),
      subtitle: choice == ThemeChoice.system
          ? const Text("Follows the phone's dark mode")
          : null,
    );
  }
}
