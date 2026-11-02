import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/ffmpeg/audio_arguments.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';

/// Turns downloaded audio into the WAV chunks Whisper transcribes.
class AudioPreparer {
  AudioPreparer(this.runner);

  final FfmpegRunner runner;

  /// `audio.wav` next to [audio], reused if already made (M4's waveform
  /// reads it too).
  Future<File> toWav(File audio) async {
    final wav = File('${audio.parent.path}/audio.wav');
    if (await wav.exists()) {
      return wav;
    }
    // Converted under another name so a half-written WAV is never reused.
    final converting = File('${wav.path}.converting.wav');
    await runner.run(
      wavArguments(inputPath: audio.path, outputPath: converting.path),
    );
    return converting.rename(wav.path);
  }

  /// [wav] cut into pieces of [chunkSeconds], in playback order.
  Future<List<File>> splitIntoChunks(File wav, {int chunkSeconds = 90}) async {
    final folder = Directory('${wav.parent.path}/chunks_$chunkSeconds');
    if (await folder.exists()) {
      await folder.delete(recursive: true);
    }
    await folder.create(recursive: true);
    await runner.run(
      chunkArguments(
        wavPath: wav.path,
        outputPattern: '${folder.path}/chunk_%03d.wav',
        chunkSeconds: chunkSeconds,
      ),
    );
    final entries = await folder.list().toList();
    return entries.whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }
}

final audioPreparerProvider = Provider<AudioPreparer>(
  (ref) => AudioPreparer(ref.watch(ffmpegRunnerProvider)),
);
