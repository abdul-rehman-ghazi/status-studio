import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/ffmpeg/audio_arguments.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/transcript/domain/audio_piece.dart';

/// Cuts a kept video's audio into the pieces Groq transcribes.
class AudioPreparer {
  AudioPreparer(this.runner);

  final FfmpegRunner runner;

  /// The audio of [video] as FLAC pieces of [chunkSeconds], in order, in a
  /// folder beside it (spec FR-3). [onProcessed] hears how much of the video
  /// FFmpeg has read.
  ///
  /// Throws [VideoUnreadableException] when FFmpeg wrote no segment list.
  /// A video with no audio makes FFmpeg fail instead; the importer already
  /// turns those away (spec FR-1).
  Future<List<AudioPiece>> cutScriptPieces(
    File video, {
    required void Function(Duration processed) onProcessed,
    int chunkSeconds = 90,
  }) async {
    final folder = Directory('${video.parent.path}/pieces_$chunkSeconds');
    await _emptied(folder);
    await runner.run(
      scriptPiecesArguments(
        ScriptPieces(
          inputPath: video.path,
          folderPath: folder.path,
          chunkSeconds: chunkSeconds,
        ),
      ),
      onTime: onProcessed,
    );
    final list = File('${folder.path}/$segmentListName');
    if (!await list.exists()) {
      throw const VideoUnreadableException('FFmpeg wrote no audio pieces');
    }
    return parseSegmentList(await list.readAsString(), folder: folder);
  }

  /// Stops the FFmpeg run, if one is still going.
  Future<void> stopRunning() => runner.cancel();

  Future<void> _emptied(Directory folder) async {
    if (await folder.exists()) {
      await folder.delete(recursive: true);
    }
    await folder.create(recursive: true);
  }
}

/// The pieces in FFmpeg's CSV segment list: one `name,start,end` row per
/// piece, times in seconds.
///
/// Throws [VideoUnreadableException] when there is no row or one is
/// malformed.
List<AudioPiece> parseSegmentList(String csv, {required Directory folder}) {
  final rows = csv.split('\n').map((row) => row.trim()).where(_isRow).toList();
  if (rows.isEmpty) {
    throw const VideoUnreadableException('the segment list is empty');
  }
  return [for (final row in rows) _pieceOf(row, folder)];
}

bool _isRow(String row) => row.isNotEmpty;

AudioPiece _pieceOf(String row, Directory folder) {
  final columns = row.split(',');
  final startSeconds = columns.length < 3 ? null : double.tryParse(columns[1]);
  if (startSeconds == null) {
    throw VideoUnreadableException('a segment list row is malformed: $row');
  }
  return AudioPiece(
    file: File('${folder.path}/${columns.first}'),
    start: Duration(
      microseconds: (startSeconds * Duration.microsecondsPerSecond).round(),
    ),
  );
}

final audioPreparerProvider = Provider<AudioPreparer>(
  (ref) => AudioPreparer(ref.watch(ffmpegRunnerProvider)),
);
