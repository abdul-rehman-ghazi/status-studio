import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/presentation/option_row.dart';
import 'package:status_studio/src/core/presentation/section_label.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/style/domain/caption_settings.dart';
import 'package:status_studio/src/features/style/presentation/caption_appearance_controls.dart';

/// Caption style (spec FR-7, M30, M37): where the lyrics sit, how big, and
/// their look and colour, in a sheet so the player above shows each change.
Future<void> showCaptionStyleSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    barrierColor: Colors.black26,
    builder: (_) => const _CaptionStyleSheet(),
  );
}

class _CaptionStyleSheet extends ConsumerWidget {
  const _CaptionStyleSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caption = ref.watch(reelDraftProvider.select((d) => d.caption));
    // Scrolls so the taller sheet still fits small phones with large text.
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Caption style',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _CaptionLayoutControls(
              caption: caption,
              onChanged: ref.read(reelDraftProvider.notifier).updateCaption,
            ),
            const SizedBox(height: 16),
            CaptionAppearanceControls(
              appearance: caption.appearance,
              onChanged: (appearance) => ref
                  .read(reelDraftProvider.notifier)
                  .updateCaption(caption.copyWith(appearance: appearance)),
            ),
            const SizedBox(height: 12),
            const HintText(
              'App name and logo are added to every reel, opposite the '
              'caption.',
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptionLayoutControls extends StatelessWidget {
  const _CaptionLayoutControls({
    required this.caption,
    required this.onChanged,
  });

  final CaptionSettings caption;
  final ValueChanged<CaptionSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Position'),
              OptionRow<CaptionPosition>(
                options: const [
                  (value: CaptionPosition.top, label: 'Top'),
                  (value: CaptionPosition.bottom, label: 'Bottom'),
                ],
                selected: caption.position,
                onSelected: (position) =>
                    onChanged(caption.copyWith(position: position)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Size'),
              OptionRow<CaptionSize>(
                options: const [
                  (value: CaptionSize.small, label: 'S'),
                  (value: CaptionSize.medium, label: 'M'),
                  (value: CaptionSize.large, label: 'L'),
                ],
                selected: caption.size,
                onSelected: (size) => onChanged(caption.copyWith(size: size)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
