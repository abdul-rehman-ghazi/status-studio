import 'package:status_studio/src/features/clip/domain/clip_range.dart';

/// The preview plays only the clip range and stops at its end (FR-5).
bool shouldStopPlayback(Duration position, ClipRange clip) =>
    position >= clip.end;
