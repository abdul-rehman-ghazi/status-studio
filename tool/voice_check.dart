/// Does cleaning the voice (spec FR-26) make Groq's lyrics more accurate?
/// Spec §10 item 8.
///
/// ```sh
/// GROQ_API_KEY=... fvm dart run tool/voice_check.dart <video> <expected.txt>
/// ```
///
/// Builds the FFmpeg arguments with the app's own `audio_arguments.dart`,
/// runs them with the `ffmpeg` on the PATH, sends the pieces to Groq with the
/// app's own `GroqClient`, and scores raw and cleaned audio, each with
/// automatic language and with `ur`, against the expected lyrics.
///
/// The key is read from the environment only. It is never written to a file
/// or printed. Network access stays in `tool/`; app tests never touch it.
library;

import 'dart:io';

import 'package:status_studio/src/core/ffmpeg/audio_arguments.dart';
import 'package:status_studio/src/features/transcript/data/groq_client.dart';

import 'voice_check/lyrics_score.dart';

const _pieceSeconds = 90;
const _passCerCeiling = 0.15;
const _keyVariable = 'GROQ_API_KEY';
const _noKeyExitCode = 2;
const _usageExitCode = 64;

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln('Usage: voice_check.dart <video> <expected.txt>');
    exit(_usageExitCode);
  }
  final apiKey = Platform.environment[_keyVariable] ?? '';
  if (apiKey.isEmpty) {
    stderr.writeln('$_keyVariable is not set: the check is waiting for it.');
    exit(_noKeyExitCode);
  }
  final expectedLines = await _readExpectedLines(File(arguments[1]));
  final workFolder = await Directory.systemTemp.createTemp('voice_check_');
  try {
    final ffmpegVersion = await _ffmpegVersion();
    final scores = await _scoreAllVariants(
      GroqClient(apiKey: apiKey),
      video: File(arguments[0]),
      expectedLines: expectedLines,
      workFolder: workFolder,
    );
    _printReport(ffmpegVersion, scores);
  } finally {
    await workFolder.delete(recursive: true);
  }
}

class _Variant {
  const _Variant({required this.cleaned, required this.languageCode});

  final bool cleaned;
  final String? languageCode;

  String get audioName => cleaned ? 'cleaned' : 'raw';
  String get languageName => languageCode ?? 'auto';
}

class _Score {
  const _Score({
    required this.variant,
    required this.errorRate,
    required this.missing,
    required this.heard,
  });

  final _Variant variant;
  final double errorRate;
  final List<String> missing;
  final String heard;
}

const _variants = [
  _Variant(cleaned: false, languageCode: null),
  _Variant(cleaned: true, languageCode: null),
  _Variant(cleaned: false, languageCode: 'ur'),
  _Variant(cleaned: true, languageCode: 'ur'),
];

Future<List<String>> _readExpectedLines(File file) async {
  final lines = (await file.readAsLines())
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .toList();
  if (lines.isEmpty) {
    throw StateError('${file.path} has no lyrics');
  }
  final unfinished = lines.where((line) => line.startsWith('TODO'));
  if (unfinished.isNotEmpty) {
    throw StateError('${file.path} is unfinished: ${unfinished.first}');
  }
  return [for (final line in lines) normalizeLyrics(line)];
}

Future<String> _ffmpegVersion() async {
  final result = await Process.run('ffmpeg', ['-version']);
  if (result.exitCode != 0) {
    throw StateError('ffmpeg is not on the PATH');
  }
  return (result.stdout as String).split('\n').first;
}

Future<List<_Score>> _scoreAllVariants(
  GroqClient groq, {
  required File video,
  required List<String> expectedLines,
  required Directory workFolder,
}) async {
  final pieces = {
    true: await _cutPieces(video, workFolder, cleaned: true),
    false: await _cutPieces(video, workFolder, cleaned: false),
  };
  final scores = <_Score>[];
  for (final variant in _variants) {
    final heard = await _transcribe(
      groq,
      pieces[variant.cleaned]!,
      variant.languageCode,
    );
    scores.add(_score(variant, heard, expectedLines));
  }
  return scores;
}

/// The pieces the app would send, cleaned or, for the baseline, the same
/// command without the `-af` filter.
Future<List<File>> _cutPieces(
  File video,
  Directory workFolder, {
  required bool cleaned,
}) async {
  final folder = Directory('${workFolder.path}/${cleaned ? 'cleaned' : 'raw'}');
  await folder.create();
  final appArguments = scriptPiecesArguments(
    ScriptPieces(
      inputPath: video.path,
      folderPath: folder.path,
      chunkSeconds: _pieceSeconds,
    ),
  );
  final arguments = cleaned ? appArguments : _withoutFilter(appArguments);
  final result = await Process.run('ffmpeg', [
    '-hide_banner',
    '-loglevel',
    'error',
    ...arguments,
  ]);
  if (result.exitCode != 0) {
    throw StateError('ffmpeg failed: ${result.stderr}');
  }
  final files =
      folder
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.flac'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    throw StateError('ffmpeg wrote no pieces');
  }
  return files;
}

List<String> _withoutFilter(List<String> arguments) {
  final filterAt = arguments.indexOf('-af');
  return [...arguments]..removeRange(filterAt, filterAt + 2);
}

Future<String> _transcribe(
  GroqClient groq,
  List<File> pieces,
  String? languageCode,
) async {
  final texts = <String>[];
  for (final piece in pieces) {
    final segments = await groq.transcribe(piece, languageCode: languageCode);
    texts.addAll(segments.map((segment) => segment.text));
  }
  return normalizeLyrics(texts.join(' '));
}

_Score _score(_Variant variant, String heard, List<String> expectedLines) {
  return _Score(
    variant: variant,
    errorRate: characterErrorRate(
      reference: expectedLines.join(' '),
      heard: heard,
    ),
    missing: missingLines(expectedLines: expectedLines, heard: heard),
    heard: heard,
  );
}

void _printReport(String ffmpegVersion, List<_Score> scores) {
  stdout
    ..writeln(ffmpegVersion)
    ..writeln('Groq whisper-large-v3-turbo, pieces of $_pieceSeconds s')
    ..writeln('Filter: $cleanVoiceFilter')
    ..writeln()
    ..writeln('| Audio | Language | CER | Lines missing |')
    ..writeln('|---|---|---|---|');
  for (final score in scores) {
    stdout.writeln(
      '| ${score.variant.audioName} | ${score.variant.languageName} '
      '| ${(score.errorRate * 100).toStringAsFixed(1)} % '
      '| ${score.missing.length} |',
    );
  }
  stdout.writeln();
  for (final languageCode in const <String?>[null, 'ur']) {
    stdout.writeln(_verdict(scores, languageCode));
  }
  stdout.writeln();
  for (final score in scores) {
    stdout
      ..writeln('${score.variant.audioName}/${score.variant.languageName}:')
      ..writeln('  heard: ${score.heard}');
    for (final line in score.missing) {
      stdout.writeln('  missing: $line');
    }
  }
}

String _verdict(List<_Score> scores, String? languageCode) {
  final sameLanguage = scores.where(
    (score) => score.variant.languageCode == languageCode,
  );
  final raw = sameLanguage.firstWhere((score) => !score.variant.cleaned);
  final cleaned = sameLanguage.firstWhere((score) => score.variant.cleaned);
  final passes =
      cleaned.errorRate < raw.errorRate && cleaned.errorRate <= _passCerCeiling;
  return '${languageCode ?? 'auto'}: ${passes ? 'PASS' : 'FAIL'} '
      '(cleaned ${(cleaned.errorRate * 100).toStringAsFixed(1)} % '
      'against raw ${(raw.errorRate * 100).toStringAsFixed(1)} %)';
}
