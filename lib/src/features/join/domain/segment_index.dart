import 'package:flutter/foundation.dart';
import 'package:status_studio/src/features/clip/domain/clip_window.dart';

/// A byte range with both ends inclusive, as in an HTTP `Range` header.
@immutable
class ByteRange {
  const ByteRange(this.first, this.last);

  final int first;
  final int last;

  int get length => last - first + 1;

  @override
  bool operator ==(Object other) =>
      other is ByteRange && other.first == first && other.last == last;

  @override
  int get hashCode => Object.hash(first, last);

  @override
  String toString() => 'ByteRange($first, $last)';
}

/// One independently decodable piece of a fragmented MP4 stream.
@immutable
class MediaSegment {
  const MediaSegment({
    required this.bytes,
    required this.start,
    required this.duration,
  });

  final ByteRange bytes;
  final Duration start;
  final Duration duration;

  Duration get end => start + duration;

  @override
  bool operator ==(Object other) =>
      other is MediaSegment &&
      other.bytes == bytes &&
      other.start == start &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(bytes, start, duration);

  @override
  String toString() => 'MediaSegment($bytes, $start, $duration)';
}

/// Where a stream's header and each of its segments sit in the file.
@immutable
class SegmentIndex {
  const SegmentIndex({required this.init, required this.segments});

  /// `ftyp` + `moov`: everything before the `sidx` box.
  final ByteRange init;
  final List<MediaSegment> segments;

  @override
  bool operator ==(Object other) =>
      other is SegmentIndex &&
      other.init == init &&
      listEquals(other.segments, segments);

  @override
  int get hashCode => Object.hash(init, Object.hashAll(segments));
}

/// The head ended before the `sidx` box did; fetch [bytesNeeded] and retry.
class SegmentIndexNotFoundException implements Exception {
  const SegmentIndexNotFoundException(this.bytesNeeded);

  final int bytesNeeded;

  @override
  String toString() => 'SegmentIndexNotFoundException: need $bytesNeeded';
}

/// The stream has media before any `sidx`, so it has no segment index.
class NoSegmentIndexException implements Exception {
  const NoSegmentIndexException();

  @override
  String toString() => 'NoSegmentIndexException';
}

/// The contiguous run of segments from the one holding [window]'s start to
/// the one holding its end.
List<MediaSegment> segmentsCovering(SegmentIndex index, ClipWindow window) {
  return index.segments
      .where(
        (segment) => segment.end > window.start && segment.start <= window.end,
      )
      .toList();
}

/// One range from the first segment's first byte to the last one's last.
ByteRange mergedRange(List<MediaSegment> segments) =>
    ByteRange(segments.first.bytes.first, segments.last.bytes.last);

const _boxHeaderBytes = 8;
const _largeBoxHeaderBytes = 16;
const _mediaBoxTypes = {'moof', 'mdat'};

/// Reads the segment index from the first bytes of an MP4 stream by
/// walking its top-level boxes until `sidx`.
SegmentIndex parseSegmentIndex(Uint8List head) {
  final data = ByteData.sublistView(head);
  var boxStart = 0;
  while (true) {
    final box = _readBoxHeader(data, boxStart);
    if (_mediaBoxTypes.contains(box.type) || box.size == 0) {
      throw const NoSegmentIndexException();
    }
    if (box.type == 'sidx') {
      return _parseSidx(data, box);
    }
    boxStart += box.size;
  }
}

/// A whole MP4 whose `moov` (with its `mvhd`) comes first states its
/// length there (spec FR-50, M74): Instagram's whole files do. Throws
/// [NoMovieLengthException] when the head holds no `mvhd`, or a zero
/// length, as a fragmented stream's does.
Duration parseMovieLength(Uint8List head) {
  final data = ByteData.sublistView(head);
  try {
    final moov = _topLevelBox(data, 'moov');
    final mvhd = _childBox(data, moov, 'mvhd');
    return _movieLength(data, mvhd);
  } on SegmentIndexNotFoundException {
    throw const NoMovieLengthException();
  }
}

/// The head of an MP4 states no length.
class NoMovieLengthException implements Exception {
  const NoMovieLengthException();

  @override
  String toString() => 'NoMovieLengthException';
}

_BoxHeader _topLevelBox(ByteData data, String type) {
  var boxStart = 0;
  while (true) {
    final box = _readBoxHeader(data, boxStart);
    if (box.type == type) {
      return box;
    }
    if (_mediaBoxTypes.contains(box.type) || box.size == 0) {
      throw const NoMovieLengthException();
    }
    boxStart += box.size;
  }
}

_BoxHeader _childBox(ByteData data, _BoxHeader parent, String type) {
  var boxStart = parent.start + parent.headerSize;
  final parentEnd = parent.start + parent.size;
  while (boxStart < parentEnd) {
    final box = _readBoxHeader(data, boxStart);
    if (box.type == type) {
      return box;
    }
    if (box.size == 0) {
      break;
    }
    boxStart += box.size;
  }
  throw const NoMovieLengthException();
}

/// `mvhd`: version and flags, two times, then the timescale and duration,
/// 32-bit in version 0 and 64-bit times in version 1.
Duration _movieLength(ByteData data, _BoxHeader mvhd) {
  final at = mvhd.start + mvhd.headerSize;
  _require(data, at + 32);
  final version = data.getUint8(at);
  final timescale = data.getUint32(version == 0 ? at + 12 : at + 20);
  final ticks = version == 0
      ? data.getUint32(at + 16)
      : data.getUint64(at + 24);
  if (timescale == 0 || ticks == 0) {
    throw const NoMovieLengthException();
  }
  return _ticksToDuration(ticks, timescale);
}

typedef _BoxHeader = ({int start, int size, int headerSize, String type});

_BoxHeader _readBoxHeader(ByteData data, int start) {
  _require(data, start + _boxHeaderBytes);
  final type = String.fromCharCodes(
    Uint8List.sublistView(data, start + 4, start + 8),
  );
  final size = data.getUint32(start);
  if (size != 1) {
    return (start: start, size: size, headerSize: _boxHeaderBytes, type: type);
  }
  // Size 1 means the real size follows as 64 bits.
  _require(data, start + _largeBoxHeaderBytes);
  return (
    start: start,
    size: data.getUint64(start + 8),
    headerSize: _largeBoxHeaderBytes,
    type: type,
  );
}

SegmentIndex _parseSidx(ByteData data, _BoxHeader box) {
  _require(data, box.start + box.size);
  var at = box.start + box.headerSize;
  final version = data.getUint8(at);
  at += 8; // version, flags, reference_ID
  final timescale = data.getUint32(at);
  at += 4;
  final earliestTime = version == 0 ? data.getUint32(at) : data.getUint64(at);
  final firstOffset = version == 0
      ? data.getUint32(at + 4)
      : data.getUint64(at + 8);
  at += version == 0 ? 8 : 16;
  final referenceCount = data.getUint16(at + 2);
  at += 4; // reserved, reference_count
  return SegmentIndex(
    init: ByteRange(0, box.start - 1),
    segments: _segments(
      data,
      firstByte: box.start + box.size + firstOffset,
      firstTick: earliestTime,
      table: (at: at, count: referenceCount, timescale: timescale),
    ),
  );
}

List<MediaSegment> _segments(
  ByteData data, {
  required int firstByte,
  required int firstTick,
  required ({int at, int count, int timescale}) table,
}) {
  final segments = <MediaSegment>[];
  var byte = firstByte;
  var tick = firstTick;
  for (var reference = 0; reference < table.count; reference++) {
    final entry = table.at + reference * 12;
    final size = data.getUint32(entry) & 0x7fffffff;
    final ticks = data.getUint32(entry + 4);
    segments.add(
      MediaSegment(
        bytes: ByteRange(byte, byte + size - 1),
        start: _ticksToDuration(tick, table.timescale),
        duration: _ticksToDuration(ticks, table.timescale),
      ),
    );
    byte += size;
    tick += ticks;
  }
  return segments;
}

void _require(ByteData data, int bytesNeeded) {
  if (data.lengthInBytes < bytesNeeded) {
    throw SegmentIndexNotFoundException(bytesNeeded);
  }
}

Duration _ticksToDuration(int ticks, int timescale) =>
    Duration(microseconds: ticks * Duration.microsecondsPerSecond ~/ timescale);
