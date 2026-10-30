import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/ffmpeg/audio_arguments.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';
import 'package:status_studio/src/features/clip/domain/waveform.dart';
import 'package:status_studio/src/features/source/domain/clip_source.dart';

const waveformBars = 60;

/// Peaks for the clip window's waveform. The WAV is made once from the clip
/// file, which exists even when the script came from captions.
final waveformProvider = FutureProvider.family<List<double>, ClipSource>((
  ref,
  source,
) async {
  final wav = await _clipWav(source.file, ref.watch(ffmpegRunnerProvider));
  final request = WaveformRequest(
    wavPath: wav.path,
    offset: source.offset,
    window: source.window,
  );
  return Isolate.run(() => _peaksFromFile(request));
});

Future<List<double>> _peaksFromFile(WaveformRequest request) async {
  final bytes = await File(request.wavPath).readAsBytes();
  return waveformPeaks(bytes, request, buckets: waveformBars);
}

/// `clip_….wav` next to the clip, reused if already made.
Future<File> _clipWav(File clip, FfmpegRunner ffmpeg) async {
  final wav = File(clip.path.replaceFirst(RegExp(r'\.mp4$'), '.wav'));
  if (await wav.exists()) {
    return wav;
  }
  // Converted under another name so a half-written WAV is never reused.
  final converting = File('${wav.path}.converting.wav');
  await ffmpeg.run(
    wavArguments(inputPath: clip.path, outputPath: converting.path),
  );
  return converting.rename(wav.path);
}
