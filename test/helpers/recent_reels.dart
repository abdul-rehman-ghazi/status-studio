import 'dart:io';

import 'package:status_studio/src/features/library/domain/recent_reel.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';

/// A finished reel whose MP4 exists in [folder], [minutesOld] old.
RecentReel recentReel(
  Directory folder, {
  required String title,
  required int minutesOld,
}) {
  final id = 'reel_$minutesOld';
  final video = File('${folder.path}/$id.mp4')..writeAsStringSync('mp4');
  return RecentReel(
    id: id,
    title: title,
    videoPath: video.path,
    thumbnailPath: '${folder.path}/$id.jpg',
    duration: const Duration(milliseconds: 27400),
    size: const OutputSize(1080, 1920),
    createdAt: DateTime(
      2026,
      11,
      2,
      12,
    ).subtract(Duration(minutes: minutesOld)),
  );
}
