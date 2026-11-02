import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/clip/domain/clip_window.dart';
import 'package:status_studio/src/features/source/domain/segment_index.dart';

import '../../../../helpers/mp4_fixture.dart';

const initBytes = 800;
const references = [(100000, 5000), (120000, 5000)];

/// Bytes of a version-0 `sidx` box holding two references.
const sidxV0Bytes = 8 + 12 + 8 + 4 + 2 * 12;

void main() {
  test('parses_segments_from_version_0_sidx', () {
    final head = buildMp4Head(
      initBytes: initBytes,
      timescale: 1000,
      references: references,
    );

    final index = parseSegmentIndex(head);

    expect(index.segments, const [
      MediaSegment(
        bytes: ByteRange(
          initBytes + sidxV0Bytes,
          initBytes + sidxV0Bytes + 99999,
        ),
        start: Duration.zero,
        duration: Duration(seconds: 5),
      ),
      MediaSegment(
        bytes: ByteRange(
          initBytes + sidxV0Bytes + 100000,
          initBytes + sidxV0Bytes + 219999,
        ),
        start: Duration(seconds: 5),
        duration: Duration(seconds: 5),
      ),
    ]);
  });

  test('parses_version_1_sidx_with_64_bit_times', () {
    final head = buildMp4Head(
      initBytes: initBytes,
      timescale: 90000,
      references: [(5000, 450000), (6000, 450000)],
      version: 1,
    );

    final index = parseSegmentIndex(head);

    expect(index.segments.map((segment) => segment.start), const [
      Duration.zero,
      Duration(seconds: 5),
    ]);
  });

  test('init_range_ends_before_sidx', () {
    final head = buildMp4Head(
      initBytes: initBytes,
      timescale: 1000,
      references: references,
    );

    expect(parseSegmentIndex(head).init, const ByteRange(0, initBytes - 1));
  });

  test('short_head_throws_not_found_with_bytes_needed', () {
    final head = buildMp4Head(
      initBytes: initBytes,
      timescale: 1000,
      references: references,
    );

    expect(
      () => parseSegmentIndex(Uint8List.sublistView(head, 0, initBytes + 10)),
      throwsA(
        isA<SegmentIndexNotFoundException>().having(
          (error) => error.bytesNeeded,
          'bytesNeeded',
          initBytes + sidxV0Bytes,
        ),
      ),
    );
  });

  test('moof_before_sidx_throws_no_index', () {
    final head =
        (BytesBuilder()
              ..add(box('ftyp', List.filled(8, 0)))
              ..add(box('moof', List.filled(8, 0))))
            .toBytes();

    expect(
      () => parseSegmentIndex(head),
      throwsA(isA<NoSegmentIndexException>()),
    );
  });

  test('segment_end_is_start_plus_duration', () {
    const segment = MediaSegment(
      bytes: ByteRange(0, 9),
      start: Duration(seconds: 5),
      duration: Duration(seconds: 5),
    );

    expect(segment.end, const Duration(seconds: 10));
  });

  test('byte_range_length_includes_both_ends', () {
    expect(const ByteRange(10, 19).length, 10);
  });

  SegmentIndex fiveSecondSegments(int count) => SegmentIndex(
    init: const ByteRange(0, 99),
    segments: [
      for (var i = 0; i < count; i++)
        MediaSegment(
          bytes: ByteRange(100 + i * 1000, 100 + i * 1000 + 999),
          start: Duration(seconds: 5 * i),
          duration: const Duration(seconds: 5),
        ),
    ],
  );

  test('selects_segments_overlapping_window', () {
    const window = ClipWindow(
      start: Duration(seconds: 12),
      end: Duration(seconds: 31),
    );

    final covering = segmentsCovering(fiveSecondSegments(10), window);

    expect(covering.map((segment) => segment.start.inSeconds), [
      10,
      15,
      20,
      25,
      30,
    ]);
  });

  test('merged_range_spans_first_to_last_segment', () {
    final segments = fiveSecondSegments(10).segments.sublist(2, 5);

    expect(mergedRange(segments), const ByteRange(2100, 5099));
  });
}
