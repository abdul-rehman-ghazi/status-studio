import 'package:flutter/material.dart';
import 'package:status_studio/src/core/presentation/screen_title.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// App bar for the numbered steps: the title with the step under it, and
/// any actions on the right. The step sits under the title, not beside the
/// actions, so the title keeps its size with Lyrics' Undo and Redo there.
class FlowAppBar extends StatelessWidget implements PreferredSizeWidget {
  const FlowAppBar({
    super.key,
    required this.title,
    required this.stepLabel,
    this.actions = const [],
  });

  final String title;
  final String stepLabel;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenTitle(title),
          Text(
            stepLabel,
            maxLines: 1,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: context.palette.textMuted),
          ),
        ],
      ),
      actions: [...actions, const SizedBox(width: 8)],
    );
  }
}
