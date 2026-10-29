import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/features/style/presentation/reel_preview.dart';
import 'package:status_studio/src/routing/app_router.dart';

const _previewMaxHeight = 360.0;

class DoneScreen extends ConsumerWidget {
  const DoneScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(reelDraftProvider);
    final output = outputSizeFor(draft.frame, assumedSourceSize);
    final length = draft.clip?.length ?? Duration.zero;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Done')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          LayoutBuilder(
            builder: (context, constraints) => Center(
              child: ReelPreview(
                draft: draft,
                maxWidth: math.min(
                  constraints.maxWidth,
                  _previewMaxHeight * output.width / output.height,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Reel ready',
            textAlign: TextAlign.center,
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Center(child: HintText('$output · ${formatSeconds(length)} · MP4')),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _showComingLater(context),
                    icon: const Icon(Icons.download),
                    label: const Text('Save'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _showComingLater(context),
                    icon: const Icon(Icons.share),
                    label: const Text('Share'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => context.go(AppRoutes.home),
                child: const Text('Make another'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Save and Share arrive in M6.
  void _showComingLater(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Available in a later update')),
    );
  }
}
