import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/features/clip/domain/clip_window.dart';
import 'package:status_studio/src/features/clip/domain/waveform.dart';

const sampleRate = 16000;

Duration at(int minutes, int seconds) =>
    Duration(minutes: minutes, seconds: seconds);

/// A 16 kHz mono PCM16 WAV of [seconds], with [loud] samples set to
/// [amplitude] and everything else silent.
Uint8List wav({
  required double seconds,
  List<({double fromSecond, double toSecond, int amplitude})> loud = const [],
}) {
  final sampleCount = (seconds * sampleRate).round();
  final samples = Int16List(sampleCount);
  for (final burst in loud) {
    final from = (burst.fromSecond * sampleRate).round();
    final to = (burst.toSecond * sampleRate).round();
    for (var index = from; index < to && index < sampleCount; index++) {
      samples[index] = index.isEven ? burst.amplitude : -burst.amplitude;
    }
  }
  final pcm = samples.buffer.asUint8List();
  final header = ByteData(44)
    ..setUint32(0, 0x52494646) // RIFF
    ..setUint32(4, 36 + pcm.length, Endian.little)
    ..setUint32(8, 0x57415645) // WAVE
    ..setUint32(12, 0x666d7420) // fmt
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(36, 0x64617461) // data
    ..setUint32(40, pcm.length, Endian.little);
  return Uint8List.fromList([...header.buffer.asUint8List(), ...pcm]);
}

WaveformRequest request({
  required Duration offset,
  required ClipWindow window,
}) => WaveformRequest(wavPath: 'clip.wav', offset: offset, window: window);

void main() {
  test('peaks_use_source_offset', () {
    final bytes = wav(
      seconds: 50,
      loud: [(fromSecond: 10, toSecond: 10.1, amplitude: 20000)],
    );
    final window = ClipWindow(start: at(0, 55), end: at(1, 45));

    final peaks = waveformPeaks(
      bytes,
      request(offset: at(0, 55), window: window),
      buckets: 60,
    );

    // 1:05 is 10 s into a 50 s window of 60 buckets: bucket 12.
    expect(peaks.indexOf(1), 12);
  });

  test('peaks_normalised_to_loudest_bucket', () {
    final bytes = wav(
      seconds: 10,
      loud: [
        (fromSecond: 1, toSecond: 2, amplitude: 10000),
        (fromSecond: 6, toSecond: 7, amplitude: 5000),
      ],
    );
    final window = ClipWindow(start: Duration.zero, end: at(0, 10));

    final peaks = waveformPeaks(
      bytes,
      request(offset: Duration.zero, window: window),
      buckets: 10,
    );

    expect([peaks[1], peaks[6]], [1.0, 0.5]);
  });

  test('silent_audio_yields_zero_peaks', () {
    final bytes = wav(seconds: 5);
    final window = ClipWindow(start: Duration.zero, end: at(0, 5));

    final peaks = waveformPeaks(
      bytes,
      request(offset: Duration.zero, window: window),
      buckets: 20,
    );

    expect(peaks, everyElement(0.0));
  });

  test('short_audio_yields_requested_bucket_count', () {
    final bytes = wav(
      seconds: 0.001,
      loud: [(fromSecond: 0, toSecond: 0.001, amplitude: 3000)],
    );
    final window = ClipWindow(start: Duration.zero, end: at(0, 30));

    final peaks = waveformPeaks(
      bytes,
      request(offset: Duration.zero, window: window),
      buckets: 60,
    );

    expect(peaks, hasLength(60));
  });

  test('peaks_skip_extra_header_chunks', () {
    // FFmpeg writes a LIST chunk before `data` unless told not to.
    final plain = wav(
      seconds: 2,
      loud: [(fromSecond: 1, toSecond: 2, amplitude: 8000)],
    );
    final list = [
      ...'LIST'.codeUnits,
      4, 0, 0, 0, //
      ...'INFO'.codeUnits,
    ];
    final withList = Uint8List.fromList([
      ...plain.sublist(0, 36),
      ...list,
      ...plain.sublist(36),
    ]);
    final window = ClipWindow(start: Duration.zero, end: at(0, 2));

    final peaks = waveformPeaks(
      withList,
      request(offset: Duration.zero, window: window),
      buckets: 2,
    );

    expect(peaks, [0.0, 1.0]);
  });
}
