import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/style/presentation/caption_style_sheet.dart';
import 'package:status_studio/src/features/transcript/application/script_progress_controller.dart';
import 'package:status_studio/src/features/transcript/presentation/script_run_section.dart';

/// The lyrics' tools above the lines on Fine-tune · Lyrics (spec FR-7,
/// FR-14, M30): Aa Style and Get again, and where the lines came from when
/// they are a saved script.
class LyricsTools extends ConsumerWidget {
  const LyricsTools({required this.onGetAgain, super.key});

  final VoidCallback onGetAgain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(scriptProgressProvider);
    final isWriting = isScriptBeingWritten(run);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              style: _toolButtonStyle,
              onPressed: () => unawaited(showCaptionStyleSheet(context)),
              icon: const Icon(Icons.text_fields),
              label: const Text('Style'),
            ),
            TextButton.icon(
              style: _toolButtonStyle,
              onPressed: isWriting ? null : onGetAgain,
              icon: const Icon(Icons.refresh),
              label: const Text('Get again'),
            ),
          ],
        ),
        if (run.value?.savedAt case final savedAt?)
          HintText(
            'Using the saved script from ${formatDayMonth(savedAt.toLocal())}',
          ),
      ],
    );
  }
}

/// Compact, so the tools fit one row and the lines keep their room.
final _toolButtonStyle = TextButton.styleFrom(
  visualDensity: VisualDensity.compact,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);
