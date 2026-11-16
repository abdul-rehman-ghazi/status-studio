// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recent_reel.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_RecentReel _$RecentReelFromJson(Map<String, dynamic> json) =>
    $checkedCreate('_RecentReel', json, ($checkedConvert) {
      final val = _RecentReel(
        id: $checkedConvert('id', (v) => v as String),
        title: $checkedConvert('title', (v) => v as String),
        videoPath: $checkedConvert('videoPath', (v) => v as String),
        thumbnailPath: $checkedConvert('thumbnailPath', (v) => v as String),
        duration: $checkedConvert(
          'durationMs',
          (v) => const MillisecondsConverter().fromJson((v as num).toInt()),
        ),
        size: $checkedConvert(
          'size',
          (v) =>
              const _OutputSizeConverter().fromJson(v as Map<String, Object?>),
          readValue: readWholeObject,
        ),
        createdAt: $checkedConvert(
          'createdAt',
          (v) => DateTime.parse(v as String),
        ),
        sourceVideoId: $checkedConvert('sourceVideoId', (v) => v as String),
        videoKey: $checkedConvert('youtubeId', (v) => v as String?),
        usedRanges: $checkedConvert(
          'usedRanges',
          (v) => const _SourceRangesConverter().fromJson(v as List),
        ),
      );
      return val;
    }, fieldKeyMap: const {'duration': 'durationMs', 'videoKey': 'youtubeId'});
