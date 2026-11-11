import 'package:flutter/material.dart';
import 'package:status_studio/src/core/presentation/screen_title.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// App bar for the numbered steps: title on the left, step on the right.
class FlowAppBar extends StatelessWidget implements PreferredSizeWidget {
  const FlowAppBar({
    super.key,
    required this.title,
    required this.stepLabel,
    this.actions = const [],
  });

  final String title;
  final String stepLabel;

  /// Shown before the step label.
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: ScreenTitle(title),
      actions: [
        ...actions,
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Center(
            child: Text(
              stepLabel,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: context.palette.textMuted),
            ),
          ),
        ),
      ],
    );
  }
}
