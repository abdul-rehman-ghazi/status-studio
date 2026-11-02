import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/export/data/reel_actions.dart';
import 'package:status_studio/src/features/reel/application/reel_draft_controller.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';
import 'package:status_studio/src/features/style/presentation/reel_preview.dart';
import 'package:status_studio/src/routing/app_router.dart';

const _previewMaxHeight = 360.0;

class DoneScreen extends ConsumerStatefulWidget {
  const DoneScreen({super.key, required this.videoPath});

  /// The finished MP4.
  final String videoPath;

  @override
  ConsumerState<DoneScreen> createState() => _DoneScreenState();
}

class _DoneScreenState extends ConsumerState<DoneScreen> {
  var _saved = false;

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(reelDraftProvider);
    final output = outputSizeFor(draft.frame, previewSourceSize(ref, draft));
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
                    onPressed: _saved ? null : _save,
                    icon: Icon(_saved ? Icons.check : Icons.download),
                    label: Text(_saved ? 'Saved' : 'Save'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => unawaited(
                      ref.read(reelActionsProvider).share(widget.videoPath),
                    ),
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

  Future<void> _save() async {
    final actions = ref.read(reelActionsProvider);
    try {
      await actions.saveToGallery(widget.videoPath);
      if (mounted) {
        setState(() => _saved = true);
      }
    } on GalleryAccessDeniedException {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Allow Photos access in Settings to save reels.'),
          action: SnackBarAction(
            label: 'Open settings',
            onPressed: () => unawaited(actions.openAppSettings()),
          ),
        ),
      );
    }
  }
}
