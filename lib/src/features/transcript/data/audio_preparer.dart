import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:status_studio/src/core/ffmpeg/audio_arguments.dart';
import 'package:status_studio/src/core/ffmpeg/ffmpeg_runner.dart';
import 'package:status_studio/src/features/source/domain/source_errors.dart';
import 'package:status_studio/src/features/transcript/domain/audio_piece.dart';

/// Cuts a kept video's audio into the pieces Groq transcribes.
class AudioPreparer {
  AudioPreparer(this.runner);

  final FfmpegRunner runner;

  /// The latest cut's own handle, so [stopRunning] stops that cut and not
  /// another FFmpeg run (a waveform's), and a stop is never forgotten by a
  /// cut that starts after it.
  FfmpegCancelHandle? _currentCut;

  /// The cleaned audio of [video] as FLAC pieces of [chunkSeconds], in
  /// order, in a folder beside it (spec FR-3, FR-26). [onProcessed] hears
  /// how much of the video FFmpeg has read.
  ///
  /// A finished cut is reused, so a retry or another language doesn't clean
  /// again. The folder's name holds the filter chain, so a changed chain
  /// never reuses old pieces; folders of other chains and unfinished cuts
  /// are deleted.
  ///
  /// Throws [VideoUnreadableException] when FFmpeg wrote no segment list.
  /// A video with no audio makes FFmpeg fail instead; the importer already
  /// turns those away (spec FR-1).
  Future<List<AudioPiece>> cutScriptPieces(
    File video, {
    required void Function(Duration processed) onProcessed,
    int chunkSeconds = 90,
  }) async {
    final cut = _currentCut = FfmpegCancelHandle();
    final folder = _piecesFolder(video, chunkSeconds);
    // Checked between the folder steps: a cancelled cut that carried on
    // would delete the folder a quick retry has started writing to.
    _throwIfCancelled(cut);
    await _deleteOtherPieceFolders(video.parent, keep: folder);
    if (await _isFinished(folder)) {
      return _readPieces(folder);
    }
    _throwIfCancelled(cut);
    await _emptied(folder);
    _throwIfCancelled(cut);
    return _cutAndMark(
      ScriptPieces(
        inputPath: video.path,
        folderPath: folder.path,
        chunkSeconds: chunkSeconds,
      ),
      cut,
      onProcessed,
    );
  }

  Future<List<AudioPiece>> _cutAndMark(
    ScriptPieces pieces,
    FfmpegCancelHandle cut,
    void Function(Duration processed) onProcessed,
  ) async {
    await runner.run(
      scriptPiecesArguments(pieces),
      onTime: onProcessed,
      cancelHandle: cut,
    );
    if (!await File(pieces.segmentListPath).exists()) {
      throw const VideoUnreadableException('FFmpeg wrote no audio pieces');
    }
    final folder = Directory(pieces.folderPath);
    final cutPieces = await _readPieces(folder);
    // FFmpeg appends to the segment list as it goes, so the list alone
    // can't tell a finished cut from one that was cut short.
    await File('${folder.path}/$_finishedMarkerName').writeAsString('');
    return cutPieces;
  }

  /// Stops the FFmpeg run, if one is still going.
  Future<void> stopRunning() async => _currentCut?.cancel();

  Directory _piecesFolder(File video, int chunkSeconds) {
    return Directory(
      '${video.parent.path}/$_piecesFolderPrefix${chunkSeconds}_'
      '${_commandId(chunkSeconds)}',
    );
  }

  /// Names the whole FFmpeg command, not only the filter chain: a changed
  /// sample rate or format must not reuse pieces cut with the old one.
  String _commandId(int chunkSeconds) {
    final command = scriptPiecesArguments(
      ScriptPieces(inputPath: '', folderPath: '', chunkSeconds: chunkSeconds),
    );
    return sha256
        .convert(command.join('\n').codeUnits)
        .toString()
        .substring(0, 8);
  }

  Future<void> _deleteOtherPieceFolders(
    Directory videoFolder, {
    required Directory keep,
  }) async {
    await for (final entry in videoFolder.list()) {
      final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (entry is Directory &&
          name.startsWith(_piecesFolderPrefix) &&
          entry.path != keep.path) {
        await _deleteIfPresent(entry);
      }
    }
  }

  /// A cancelled cut and its retry can both be clearing the same folder.
  Future<void> _deleteIfPresent(Directory folder) async {
    try {
      await folder.delete(recursive: true);
    } on PathNotFoundException {
      return;
    }
  }

  Future<bool> _isFinished(Directory folder) async {
    if (!await File('${folder.path}/$_finishedMarkerName').exists()) {
      return false;
    }
    try {
      final pieces = await _readPieces(folder);
      return await _allExist(pieces);
    } on FileSystemException {
      return false;
    } on VideoUnreadableException {
      return false;
    }
  }

  Future<List<AudioPiece>> _readPieces(Directory folder) async {
    final list = File('${folder.path}/$segmentListName');
    return parseSegmentList(await list.readAsString(), folder: folder);
  }

  Future<bool> _allExist(List<AudioPiece> pieces) async {
    for (final piece in pieces) {
      if (!await piece.file.exists()) {
        return false;
      }
    }
    return true;
  }

  void _throwIfCancelled(FfmpegCancelHandle cut) {
    if (cut.isCancelled) {
      throw const FfmpegFailedException('stopped before it started');
    }
  }

  Future<void> _emptied(Directory folder) async {
    await _deleteIfPresent(folder);
    await folder.create(recursive: true);
  }
}

const _piecesFolderPrefix = 'pieces_';
const _finishedMarkerName = 'finished';

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
