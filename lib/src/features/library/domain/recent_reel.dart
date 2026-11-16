import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:status_studio/src/core/json_converters.dart';
import 'package:status_studio/src/features/library/domain/used_ranges.dart';
import 'package:status_studio/src/features/style/domain/frame_settings.dart';

part 'recent_reel.freezed.dart';
part 'recent_reel.g.dart';

/// A finished reel in the Recent list (spec §6.1, FR-11), and where it came
/// from, for History (FR-44). A stored reel without [sourceVideoId] (made
/// before M54) is unreadable.
///
/// Saved flat: the size is `width` and `height` beside the other keys, so
/// `toJson` is written by hand.
@Freezed(toJson: false)
abstract class RecentReel with _$RecentReel {
  @JsonSerializable(createToJson: false)
  const factory RecentReel({
    required String id,

    /// The caption's first line, shown in the list.
    required String title,
    required String videoPath,
    required String thumbnailPath,
    @JsonKey(name: 'durationMs')
    @MillisecondsConverter()
    required Duration duration,

    /// The MP4's frame size, shown on Done.
    @JsonKey(readValue: readWholeObject)
    @_OutputSizeConverter()
    required OutputSize size,
    required DateTime createdAt,

    /// The fingerprint of the video it was rendered from.
    required String sourceVideoId,

    /// The key of the linked video a joined clip came from (FR-50); null
    /// otherwise.
    @JsonKey(name: 'youtubeId') String? videoKey,

    /// What it used of its source, in source order (spec FR-44).
    @_SourceRangesConverter() required List<SourceRange> usedRanges,
  }) = _RecentReel;

  const RecentReel._();

  /// Throws [CheckedFromJsonException] for a malformed entry.
  factory RecentReel.fromJson(Map<String, Object?> json) =>
      _$RecentReelFromJson(json);

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'videoPath': videoPath,
    'thumbnailPath': thumbnailPath,
    'durationMs': const MillisecondsConverter().toJson(duration),
    ...const _OutputSizeConverter().toJson(size),
    'createdAt': createdAt.toIso8601String(),
    'sourceVideoId': sourceVideoId,
    'youtubeId': videoKey,
    'usedRanges': const _SourceRangesConverter().toJson(usedRanges),
  };
}

class _SourceRangesConverter
    implements JsonConverter<List<SourceRange>, List<Object?>> {
  const _SourceRangesConverter();

  @override
  List<SourceRange> fromJson(List<Object?> json) =>
      json.map(SourceRange.fromJson).toList();

  @override
  List<Object?> toJson(List<SourceRange> ranges) => [
    for (final range in ranges) range.toJson(),
  ];
}

class _OutputSizeConverter
    implements JsonConverter<OutputSize, Map<String, Object?>> {
  const _OutputSizeConverter();

  /// Throws [FormatException] when [json] has no whole-number size.
  @override
  OutputSize fromJson(Map<String, Object?> json) {
    if (json case {'width': final int width, 'height': final int height}) {
      return OutputSize(width, height);
    }
    throw const FormatException('Not a saved size.');
  }

  @override
  Map<String, Object?> toJson(OutputSize size) => {
    'width': size.width,
    'height': size.height,
  };
}
