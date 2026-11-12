import 'package:flutter/material.dart';
import 'package:status_studio/src/features/topic/domain/clip_transition.dart';
import 'package:status_studio/src/theme/app_theme.dart';

/// The four transitions in a sheet, two by two; returns the one tapped, or
/// null when closed (spec FR-36).
Future<ClipTransition?> showTransitionSheet(
  BuildContext context,
  ClipTransition chosen,
) => showModalBottomSheet<ClipTransition>(
  context: context,
  showDragHandle: true,
  builder: (context) => Padding(
    padding: const EdgeInsets.fromLTRB(17, 0, 17, 24),
    child: TransitionPicker(
      chosen: chosen,
      onChosen: (transition) => Navigator.of(context).pop(transition),
    ),
  ),
);

/// Four tiles, each looping a small preview of its transition (spec FR-36).
class TransitionPicker extends StatelessWidget {
  const TransitionPicker({
    required this.chosen,
    required this.onChosen,
    super.key,
  });

  final ClipTransition chosen;
  final ValueChanged<ClipTransition> onChosen;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      childAspectRatio: 1.25,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final transition in ClipTransition.values)
          _TransitionTile(
            transition: transition,
            selected: transition == chosen,
            onTap: () => onChosen(transition),
          ),
      ],
    );
  }
}

class _TransitionTile extends StatelessWidget {
  const _TransitionTile({
    required this.transition,
    required this.selected,
    required this.onTap,
  });

  final ClipTransition transition;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      selected: selected,
      button: true,
      label: transition.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? palette.accent : palette.surface,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: _TransitionPreview(transition: transition),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                transition.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Two panels, A and B, swapping every 1.6 s in the transition's way.
class _TransitionPreview extends StatefulWidget {
  const _TransitionPreview({required this.transition});

  final ClipTransition transition;

  @override
  State<_TransitionPreview> createState() => _TransitionPreviewState();
}

class _TransitionPreviewState extends State<_TransitionPreview>
    with SingleTickerProviderStateMixin {
  late final _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AnimatedBuilder(
      animation: _loop,
      builder: (context, _) => _frame(
        _blendAt(_loop.value),
        first: ColoredBox(color: palette.accent),
        second: ColoredBox(color: palette.textMuted),
      ),
    );
  }

  /// Holds A, changes over the middle fifth, holds B.
  double _blendAt(double loopValue) =>
      ((loopValue - 0.4) / 0.2).clamp(0.0, 1.0);

  Widget _frame(double blend, {required Widget first, required Widget second}) {
    return switch (widget.transition) {
      ClipTransition.cut => blend < 0.5 ? first : second,
      ClipTransition.crossfade => Stack(
        fit: StackFit.expand,
        children: [
          first,
          Opacity(opacity: blend, child: second),
        ],
      ),
      ClipTransition.fadeThroughBlack => Stack(
        fit: StackFit.expand,
        children: [
          if (blend < 0.5) first else second,
          ColoredBox(
            color: Colors.black.withValues(alpha: 1 - (2 * blend - 1).abs()),
          ),
        ],
      ),
      ClipTransition.slide => LayoutBuilder(
        builder: (context, constraints) => Stack(
          fit: StackFit.expand,
          children: [
            first,
            Transform.translate(
              offset: Offset(constraints.maxWidth * (1 - blend), 0),
              child: second,
            ),
          ],
        ),
      ),
    };
  }
}
