import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:status_studio/src/core/presentation/hint_text.dart';
import 'package:status_studio/src/core/time_format.dart';
import 'package:status_studio/src/features/export/data/reel_actions.dart';
import 'package:status_studio/src/features/library/application/recent_reels_controller.dart';
import 'package:status_studio/src/features/library/domain/recent_reel.dart';
import 'package:status_studio/src/routing/app_router.dart';
import 'package:status_studio/src/theme/app_theme.dart';

const _previewMaxHeight = 360.0;

/// A finished reel, just exported or reopened from Recent (FR-10, FR-11).
class DoneScreen extends ConsumerWidget {
  const DoneScreen({super.key, required this.reelId});

  final String reelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reels = ref.watch(recentReelsProvider);
    final reel = reels.value
        ?.where((candidate) => candidate.id == reelId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Done')),
      body: switch ((reels.isLoading, reel)) {
        (_, final RecentReel found) => _ReelSummary(reel: found),
        (true, _) => const Center(child: CircularProgressIndicator()),
        _ => const Center(
          child: HintText('This reel is no longer on your phone.'),
        ),
      },
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (reel != null) _ReelActions(reel: reel),
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
}

class _ReelSummary extends StatelessWidget {
  const _ReelSummary({required this.reel});

  final RecentReel reel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: _previewMaxHeight,
              child: AspectRatio(
                aspectRatio: reel.size.width / reel.size.height,
                child: _Thumbnail(path: reel.thumbnailPath),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Reel ready',
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Center(
          child: HintText(
            '${reel.size} · ${formatSeconds(reel.duration)} · MP4',
          ),
        ),
      ],
    );
  }
}

/// The reel's first frame; a plain tile if the thumbnail couldn't be made.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    const placeholder = ColoredBox(
      color: AppColors.surface,
      child: Icon(Icons.movie_outlined, color: AppColors.textMuted),
    );
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => placeholder,
    );
  }
}

class _ReelActions extends ConsumerStatefulWidget {
  const _ReelActions({required this.reel});

  final RecentReel reel;

  @override
  ConsumerState<_ReelActions> createState() => _ReelActionsState();
}

class _ReelActionsState extends ConsumerState<_ReelActions> {
  var _saved = false;

  @override
  Widget build(BuildContext context) {
    return Row(
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
              ref.read(reelActionsProvider).share(widget.reel.videoPath),
            ),
            icon: const Icon(Icons.share),
            label: const Text('Share'),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final actions = ref.read(reelActionsProvider);
    try {
      await actions.saveToGallery(widget.reel.videoPath);
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
