import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/ffmpeg/media_probe.dart';
import 'package:status_studio/src/features/source/domain/clip_source.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';

/// The clip file's frame size: crops, the free size and the preview are
/// measured in its pixels.
final clipFrameSizeProvider = FutureProvider.family<OutputSize, ClipSource>(
  (ref, source) => ref.watch(mediaProbeProvider).videoSize(source.file.path),
);
