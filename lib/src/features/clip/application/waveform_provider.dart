import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/ffmpeg/audio_arguments.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';
import 'package:status_studio/src/features/clip/domain/clip_window.dart';
import 'package:status_studio/src/features/clip/domain/waveform.dart';
import 'package:status_studio/src/features/source/domain/clip_source.dart';

const waveformBars = 60;

/// A source and the stretch of it the waveform shows (`waveformWindowFor`).
typedef WaveformSpan = ({ClipSource source, ClipWindow shown});

/// Peaks for the shown stretch. The WAV comes from the clip file, which
/// exists even when the script came from captions. Auto-disposed, so a
/// failed conversion is tried again the next time Fine-tune opens.
final waveformProvider = FutureProvider.autoDispose
    .family<List<double>, WaveformSpan>((ref, span) async {
      final wav = await _shownWav(span, ref.watch(ffmpegRunnerProvider));
      final request = WaveformRequest(
        wavPath: wav.path,
        offset: span.shown.start,
        window: span.shown,
      );
      return Isolate.run(() => _peaksFromFile(request));
    });

Future<List<double>> _peaksFromFile(WaveformRequest request) async {
  final bytes = await File(request.wavPath).readAsBytes();
  return waveformPeaks(bytes, request, buckets: waveformBars);
}

/// `wave_<startMs>_<endMs>.wav` beside the source, reused if already made.
/// Named by video time, so it's the same audio whichever file it came from.
Future<File> _shownWav(WaveformSpan span, FfmpegRunner ffmpeg) async {
  final shown = span.shown;
  final wav = File(
    '${span.source.file.parent.path}/wave_'
    '${shown.start.inMilliseconds}_${shown.end.inMilliseconds}.wav',
  );
  if (await wav.exists()) {
    return wav;
  }
  // Converted under another name so a half-written WAV is never reused.
  final converting = File('${wav.path}.converting.wav');
  try {
    await ffmpeg.run(
      excerptWavArguments(
        WavExcerpt(
          inputPath: span.source.file.path,
          outputPath: converting.path,
          start: shown.start - span.source.offset,
          end: shown.end - span.source.offset,
        ),
      ),
    );
    return await converting.rename(wav.path);
  } catch (_) {
    if (await converting.exists()) {
      await converting.delete();
    }
    rethrow;
  }
}
