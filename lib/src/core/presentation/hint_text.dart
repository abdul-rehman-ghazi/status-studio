import 'package:flutter/material.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// Small muted helper text under a field or control.
class HintText extends StatelessWidget {
  const HintText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: AppColors.textMuted),
    );
  }
}
