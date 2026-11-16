import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:status_studio/src/core/ffmpeg/media_probe.dart';
import 'package:status_studio/src/features/export/application/media3_renderer.dart';
import 'package:status_studio/src/features/export/data/loudness_meter.dart';
import 'package:status_studio/src/features/export/data/overlay_painter.dart';
import 'package:status_studio/src/features/export/domain/render_errors.dart';
import 'package:status_studio/src/features/reel/domain/reel_draft.dart';
import 'package:status_studio/src/features/source/application/clip_source_controller.dart';
import 'package:status_studio/src/features/source/domain/clip_source.dart';

sealed class RenderProgress {
  const RenderProgress();
}

class RenderRunning extends RenderProgress {
  const RenderRunning(this.fraction);

  /// Share of the clip duration processed, from 0 to 1.
  final double fraction;
}

class RenderFinished extends RenderProgress {
  const RenderFinished(this.videoPath);

  final String videoPath;
}

abstract interface class Renderer {
  Stream<RenderProgress> render(ReelDraft draft);

  Future<void> cancel();
}

final rendererProvider = Provider<Renderer>(
  (ref) => Media3Renderer(
    RenderServices(
      clipSourceFor: (draft) => _clipSourceFor(ref, draft),
      probe: ref.watch(mediaProbeProvider),
      loudnessMeter: ref.watch(loudnessMeterProvider),
      paintOverlay: paintOverlayPng,
      outputDirectory: reelsDirectory(),
    ),
  ),
);

/// The kept video for the draft; Fine-tune normally has it open already, so
/// this only opens it if the app was restarted since (FR-1).
Future<ClipSource> _clipSourceFor(Ref ref, ReelDraft draft) async {
  final video = draft.video;
  if (video == null || draft.clip == null) {
    throw StateError('Export started without a video and a clip.');
  }
  final clipSource = clipSourceProvider(video.videoId);
  await ref.read(clipSource.notifier).open(video);
  final source = ref.read(clipSource).requireValue;
  if (source == null) {
    throw const RenderFailedException('The video was not opened.');
  }
  return source;
}

/// Where reels and their thumbnails are written (FR-9, FR-11).
Future<Directory> reelsDirectory() async {
  final documents = await getApplicationDocumentsDirectory();
  return Directory('${documents.path}/reels');
}
