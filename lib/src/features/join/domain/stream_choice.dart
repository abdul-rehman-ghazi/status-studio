import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/join/domain/join_errors.dart';

const _mp4 = 'mp4';
const _h264CodecPrefix = 'avc1';
const _drcSuffix = '-drc';

/// The joined clip's picture: 1080p at most (spec FR-37).
const clipVideoHeight = 1080;

/// Play on a card: small, since it is only for checking a moment.
const previewVideoHeight = 480;

/// One stream yt-dlp lists that can be fetched in byte ranges (spec FR-37).
@immutable
class StreamFormat {
  const StreamFormat({
    required this.formatId,
    required this.url,
    required this.container,
    required this.codec,
    required this.height,
    required this.bitrate,
    this.isDefaultTrack = true,
  });

  /// yt-dlp's ID, e.g. `299`, or `140-drc` for dynamic-range-compressed
  /// audio.
  final String formatId;
  final Uri url;

  /// `mp4` for MP4 video and `m4a` audio, else yt-dlp's extension.
  final String container;

  /// As YouTube reports it, e.g. `avc1.64002A`; empty for audio.
  final String codec;

  /// The short side in pixels, so a vertical 1080 × 1920 Short is 1080p;
  /// 0 for audio.
  final int height;

  /// Bits per second.
  final int bitrate;

  /// False for dubbed or descriptive audio tracks.
  final bool isDefaultTrack;

  /// Only MP4 streams carry the segment index the cuts are fetched by.
  bool get isMp4 => container == _mp4;

  bool get isH264 => codec.startsWith(_h264CodecPrefix);

  bool get isCompressedRange => formatId.endsWith(_drcSuffix);

  @override
  bool operator ==(Object other) =>
      other is StreamFormat &&
      other.formatId == formatId &&
      other.url == url &&
      other.container == container &&
      other.codec == codec &&
      other.height == height &&
      other.bitrate == bitrate &&
      other.isDefaultTrack == isDefaultTrack;

  @override
  int get hashCode => Object.hash(
    formatId,
    url,
    container,
    codec,
    height,
    bitrate,
    isDefaultTrack,
  );
}

/// Everything a linked video offers, split into picture-only and
/// sound-only streams (YouTube offers no stream with both, §10 item 10).
@immutable
class LinkedFormats {
  const LinkedFormats({required this.video, required this.audio});

  final List<StreamFormat> video;
  final List<StreamFormat> audio;
}

/// The two streams a cut is made from.
@immutable
class CutStreams {
  const CutStreams({required this.video, required this.audio});

  final StreamFormat video;
  final StreamFormat audio;

  /// Names the cut files made from these streams, so a cut downloaded at
  /// another quality is never taken for this one.
  String get key => '${video.formatId}+${audio.formatId}';
}

/// For the joined clip (spec FR-37). Throws
/// [NotDownloadableInPartsException] without an MP4 picture or sound.
CutStreams streamsForClip(LinkedFormats formats) => CutStreams(
  video: pickVideoStream(formats.video, maxHeight: clipVideoHeight),
  audio: pickAudioStream(formats.audio),
);

/// For Play on a card (spec FR-37). Throws
/// [NotDownloadableInPartsException] as [streamsForClip] does.
CutStreams streamsForPreview(LinkedFormats formats) => CutStreams(
  video: pickVideoStream(formats.video, maxHeight: previewVideoHeight),
  audio: pickAudioStream(formats.audio),
);

/// MP4 only: H.264 first, then any other codec (AV1); in each the highest
/// at or under [maxHeight], failing that the lowest above it.
StreamFormat pickVideoStream(
  List<StreamFormat> streams, {
  required int maxHeight,
}) {
  final mp4 = streams.where((stream) => stream.isMp4).toList();
  final groups = [
    mp4.where((stream) => stream.isH264).toList(),
    mp4.where((stream) => !stream.isH264).toList(),
  ];
  for (final group in groups) {
    final picked = _bestWithinCap(group, maxHeight) ?? _lowestAboveCap(group);
    if (picked != null) {
      return picked;
    }
  }
  throw const NotDownloadableInPartsException('No MP4 video stream.');
}

/// MP4 (`m4a`) only: the original track over dubs, a regular stream over a
/// dynamic-range-compressed one, then the highest bitrate.
StreamFormat pickAudioStream(List<StreamFormat> streams) {
  final mp4 = streams.where((stream) => stream.isMp4).toList();
  if (mp4.isEmpty) {
    throw const NotDownloadableInPartsException('No MP4 audio stream.');
  }
  final original = _preferred(mp4, (stream) => stream.isDefaultTrack);
  final regular = _preferred(original, (stream) => !stream.isCompressedRange);
  return regular.reduce((a, b) => b.bitrate > a.bitrate ? b : a);
}

/// The streams that pass [test], or all of them when none does.
List<StreamFormat> _preferred(
  List<StreamFormat> streams,
  bool Function(StreamFormat stream) test,
) {
  final passing = streams.where(test).toList();
  return passing.isEmpty ? streams : passing;
}

StreamFormat? _bestWithinCap(List<StreamFormat> streams, int maxHeight) {
  final withinCap = streams.where((stream) => stream.height <= maxHeight);
  if (withinCap.isEmpty) {
    return null;
  }
  return withinCap.reduce((a, b) => _compareQuality(b, a) > 0 ? b : a);
}

StreamFormat? _lowestAboveCap(List<StreamFormat> streams) {
  if (streams.isEmpty) {
    return null;
  }
  return streams.reduce((a, b) => b.height < a.height ? b : a);
}

int _compareQuality(StreamFormat a, StreamFormat b) {
  final byHeight = a.height.compareTo(b.height);
  return byHeight != 0 ? byHeight : a.bitrate.compareTo(b.bitrate);
}
