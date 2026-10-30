import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';

const _preferredContainer = 'mp4';

/// One downloadable stream, reduced to what stream choice needs.
@immutable
class StreamChoice {
  const StreamChoice({
    required this.height,
    required this.container,
    required this.bitrate,
    required this.index,
  });

  /// Video height in pixels; 0 for audio.
  final int height;
  final String container;

  /// Bits per second.
  final int bitrate;

  /// Position in the manifest list this choice came from.
  final int index;

  bool get isPreferredContainer => container == _preferredContainer;

  @override
  bool operator ==(Object other) =>
      other is StreamChoice &&
      other.height == height &&
      other.container == container &&
      other.bitrate == bitrate &&
      other.index == index;

  @override
  int get hashCode => Object.hash(height, container, bitrate, index);
}

/// The highest MP4 stream at or below [maxHeight]; failing that, the lowest
/// MP4 above it; then the same two steps for any other container.
StreamChoice pickVideoStream(
  List<StreamChoice> videoStreams, {
  int maxHeight = 720,
}) {
  if (videoStreams.isEmpty) {
    throw const VideoUnavailableException('No video streams.');
  }
  final mp4 = videoStreams.where((s) => s.isPreferredContainer).toList();
  final others = videoStreams.where((s) => !s.isPreferredContainer).toList();
  return _bestWithinCap(mp4, maxHeight) ??
      _lowestAboveCap(mp4) ??
      _bestWithinCap(others, maxHeight) ??
      _lowestAboveCap(others)!;
}

/// The highest-bitrate MP4 audio stream, else the highest-bitrate of any.
StreamChoice pickAudioStream(List<StreamChoice> audioStreams) {
  if (audioStreams.isEmpty) {
    throw const VideoUnavailableException('No audio streams.');
  }
  final mp4 = audioStreams.where((s) => s.isPreferredContainer).toList();
  final candidates = mp4.isEmpty ? audioStreams : mp4;
  return candidates.reduce((a, b) => b.bitrate > a.bitrate ? b : a);
}

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
