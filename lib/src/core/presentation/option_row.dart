import 'package:flutter/material.dart';
import 'package:status_studio/src/theme/app_theme.dart';

typedef Option<T> = ({T value, String label});

/// A row of mutually exclusive choice chips.
class OptionRow<T> extends StatelessWidget {
  const OptionRow({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<Option<T>> options;

  /// None when the current value isn't one of the options.
  final T? selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          ChoiceChip(
            label: Text(option.label),
            selected: option.value == selected,
            showCheckmark: false,
            selectedColor: context.palette.accent,
            labelStyle: TextStyle(
              color: option.value == selected
                  ? context.palette.onAccent
                  : context.palette.textPrimary,
            ),
            onSelected: (_) => onSelected(option.value),
          ),
      ],
    );
  }
}
