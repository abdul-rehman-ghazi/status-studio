import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/ffmpeg/audio_arguments.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';

/// Cuts downloaded audio into the pieces Groq transcribes.
class AudioPreparer {
  AudioPreparer(this.runner);

  final FfmpegRunner runner;

  /// [audio] cut into `.m4a` pieces of [chunkSeconds] by stream copy, the
  /// small files Groq is sent (spec FR-12a). Cuts fall on audio packets, so
  /// a piece can start a few milliseconds late; that doesn't add up.
  Future<List<File>> splitAudioCopy(File audio, {int chunkSeconds = 90}) =>
      _split(
        audio,
        folderName: 'pieces_$chunkSeconds',
        chunkSeconds: chunkSeconds,
      );

  Future<List<File>> _split(
    File source, {
    required String folderName,
    required int chunkSeconds,
  }) async {
    final folder = Directory('${source.parent.path}/$folderName');
    if (await folder.exists()) {
      await folder.delete(recursive: true);
    }
    await folder.create(recursive: true);
    final extension = source.path.split('.').last;
    await runner.run(
      chunkArguments(
        inputPath: source.path,
        outputPattern: '${folder.path}/chunk_%03d.$extension',
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
