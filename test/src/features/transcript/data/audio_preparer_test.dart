import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';
import 'package:status_studio/src/features/transcript/data/audio_preparer.dart';

class _RecordingRunner extends FfmpegRunner {
  _RecordingRunner(this.outputNames);

  final List<String> outputNames;
  late List<String> arguments;

  @override
  Future<void> run(
    List<String> arguments, {
    void Function(Duration processed)? onTime,
  }) async {
    this.arguments = arguments;
    final pattern = arguments.last;
    for (final name in outputNames) {
      File(pattern.replaceFirst('chunk_%03d', name)).createSync();
    }
  }
}

void main() {
  late Directory folder;
  late File audio;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('audio_preparer_test');
    audio = File('${folder.path}/audio.m4a')..writeAsBytesSync([0]);
  });

  tearDown(() => folder.deleteSync(recursive: true));

  test('split_audio_copy_stream_copies_into_m4a_pieces', () async {
    final runner = _RecordingRunner(['chunk_000', 'chunk_001']);

    await AudioPreparer(runner).splitAudioCopy(audio);

    expect(runner.arguments, containsAllInOrder(['-c', 'copy']));
    expect(runner.arguments.last, endsWith('/pieces_90/chunk_%03d.m4a'));
  });

  test('split_audio_copy_returns_pieces_in_playback_order', () async {
    final runner = _RecordingRunner(['chunk_001', 'chunk_000']);

    final pieces = await AudioPreparer(runner).splitAudioCopy(audio);

    expect(pieces.map((piece) => piece.path.split('/').last), [
      'chunk_000.m4a',
      'chunk_001.m4a',
    ]);
  });
}
