import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

const _preferredContainer = 'mp4';
const _preferredVideoCodec = 'avc1';

/// One downloadable stream, reduced to what stream choice needs.
@immutable
class StreamChoice {
  const StreamChoice({
    required this.height,
    required this.container,
    required this.bitrate,
    required this.index,
    this.codec = '',
    this.isDefaultTrack = true,
  });

  /// Video quality in pixels (the short side, see [qualityHeight]); 0 for
  /// audio.
  final int height;
  final String container;

  /// Bits per second.
  final int bitrate;

  /// Position in the manifest list this choice came from.
  final int index;

  /// Codec string as YouTube reports it, e.g. `avc1.4d401f`.
  final String codec;

  /// False for dubbed or alternative audio tracks.
  final bool isDefaultTrack;

  bool get isPreferredContainer => container == _preferredContainer;

  /// MP4 with H.264: plays on every Android version and every FFmpeg build.
  bool get isMostCompatibleVideo =>
      isPreferredContainer && codec.startsWith(_preferredVideoCodec);

  @override
  bool operator ==(Object other) =>
      other is StreamChoice &&
      other.height == height &&
      other.container == container &&
      other.bitrate == bitrate &&
      other.index == index &&
      other.codec == codec &&
      other.isDefaultTrack == isDefaultTrack;

  @override
  int get hashCode =>
      Object.hash(height, container, bitrate, index, codec, isDefaultTrack);
}

/// "720p" means the short side, so a vertical 720 × 1280 Short is 720p.
int qualityHeight({required int width, required int height}) =>
    math.min(width, height);

/// Picks by compatibility first (H.264 MP4, other MP4, anything else); in
/// each group the highest quality at or below [maxHeight], failing that the
/// lowest above it.
StreamChoice pickVideoStream(
  List<StreamChoice> videoStreams, {
  int maxHeight = 720,
}) {
  if (videoStreams.isEmpty) {
    throw const VideoUnavailableException('No video streams.');
  }
  final groups = [
    videoStreams.where((s) => s.isMostCompatibleVideo),
    videoStreams.where(
      (s) => s.isPreferredContainer && !s.isMostCompatibleVideo,
    ),
    videoStreams.where((s) => !s.isPreferredContainer),
  ];
  return groups
      .map((group) => _pickWithinGroup(group.toList(), maxHeight))
      .nonNulls
      .first;
}

/// The original-language track over dubs, MP4 over other containers, then
/// the highest bitrate.
StreamChoice pickAudioStream(List<StreamChoice> audioStreams) {
  if (audioStreams.isEmpty) {
    throw const VideoUnavailableException('No audio streams.');
  }
  final original = audioStreams.where((s) => s.isDefaultTrack).toList();
  final tracks = original.isEmpty ? audioStreams : original;
  final mp4 = tracks.where((s) => s.isPreferredContainer).toList();
  final candidates = mp4.isEmpty ? tracks : mp4;
  return candidates.reduce((a, b) => b.bitrate > a.bitrate ? b : a);
}

StreamChoice? _pickWithinGroup(List<StreamChoice> group, int maxHeight) =>
    _bestWithinCap(group, maxHeight) ?? _lowestAboveCap(group);

StreamChoice? _bestWithinCap(List<StreamChoice> streams, int maxHeight) {
  final withinCap = streams.where((s) => s.height <= maxHeight);
  if (withinCap.isEmpty) {
    return null;
  }
  return withinCap.reduce((a, b) => _compareQuality(b, a) > 0 ? b : a);
}

StreamChoice? _lowestAboveCap(List<StreamChoice> streams) {
  if (streams.isEmpty) {
    return null;
  }
  return streams.reduce((a, b) => b.height < a.height ? b : a);
}

int _compareQuality(StreamChoice a, StreamChoice b) {
  final byHeight = a.height.compareTo(b.height);
  return byHeight != 0 ? byHeight : a.bitrate.compareTo(b.bitrate);
}
