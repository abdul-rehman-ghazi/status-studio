import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';
import 'package:status_studio/src/core/ffmpeg/thumbnail_arguments.dart';
import 'package:status_studio/src/features/library/data/recent_reels_repository.dart';
import 'package:status_studio/src/features/library/domain/recent_reel.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';

/// The Recent list on Home (spec FR-11), newest first.
final recentReelsProvider =
    AsyncNotifierProvider<RecentReelsController, List<RecentReel>>(
      RecentReelsController.new,
    );

class RecentReelsController extends AsyncNotifier<List<RecentReel>> {
  @override
  Future<List<RecentReel>> build() =>
      ref.watch(recentReelsRepositoryProvider).load();

  /// Records the reel rendered to [videoPath] from [draft] at [size], with
  /// a thumbnail of its first frame beside it.
  Future<RecentReel> keep(
    String videoPath,
    ReelDraft draft,
    OutputSize size,
  ) async {
    final id = _idOf(videoPath);
    final reel = RecentReel(
      id: id,
      title: _titleOf(draft),
      videoPath: videoPath,
      thumbnailPath: '${File(videoPath).parent.path}/$id.jpg',
      duration: draft.clip?.length ?? Duration.zero,
      size: size,
      createdAt: DateTime.now(),
    );
    await _writeThumbnail(reel);
    await ref.read(recentReelsRepositoryProvider).add(reel);
    ref.invalidateSelf();
    return reel;
  }

  Future<void> delete(String id) async {
    await ref.read(recentReelsRepositoryProvider).delete(id);
    ref.invalidateSelf();
  }

  /// A missing thumbnail only costs the list its picture, so no failure
  /// of the FFmpeg run, including a plugin error, stops the reel being
  /// kept.
  Future<void> _writeThumbnail(RecentReel reel) async {
    try {
      await ref
          .read(ffmpegRunnerProvider)
          .run(
            thumbnailArguments(
              videoPath: reel.videoPath,
              outputPath: reel.thumbnailPath,
            ),
          );
    } on Exception {
      return;
    }
  }
}

String _idOf(String videoPath) {
  final name = File(videoPath).uri.pathSegments.last;
  return name.endsWith('.mp4') ? name.substring(0, name.length - 4) : name;
}

/// The caption's first line, or the video's title for a reel without one.
String _titleOf(ReelDraft draft) {
  final firstLine = draft.caption.text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .firstOrNull;
  return firstLine ?? draft.video?.title ?? 'Reel';
}
