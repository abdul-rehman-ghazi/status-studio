/// Does cleaning the voice (spec FR-26) make Groq's lyrics more accurate?
/// Spec §10 item 8.
///
/// ```sh
/// read -rs GROQ_API_KEY && export GROQ_API_KEY
/// fvm dart run tool/voice_check.dart <video> <expected.txt>
/// ```
///
/// (`read` keeps the key out of the shell history.)
///
/// Builds the FFmpeg arguments with the app's own `audio_arguments.dart`,
/// runs them with the `ffmpeg` on the PATH, sends the pieces to Groq with the
/// app's own `GroqClient`, and scores raw and cleaned audio, each with
/// automatic language and with `ur`, against the expected lyrics.
///
/// The key is read from the environment only. It is never written to a file
/// or printed. Network access stays in `tool/`; app tests never touch it.
/// Groq's text is kept as the app keeps it: segments above the no-speech
/// cutoff are dropped (the app also drops English phantom phrases such as
/// "thank you", which cannot be in Urdu lyrics).
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
      expectedLines,
      await _cutBothKinds(File(arguments[0]), workFolder),
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
  final written = (await file.readAsLines())
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .toList();
  final unfinished = written.where((line) => line.startsWith('TODO'));
  if (unfinished.isNotEmpty) {
    throw StateError('${file.path} is unfinished: ${unfinished.first}');
  }
  final lines = written
      .map(normalizeLyrics)
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.isEmpty) {
    throw StateError('${file.path} has no lyrics');
  }
  return lines;
}

Future<String> _ffmpegVersion() async {
  try {
    final result = await Process.run('ffmpeg', ['-version']);
    return (result.stdout as String).split('\n').first;
  } on ProcessException {
    throw StateError('ffmpeg is not on the PATH');
  }
}

/// The pieces of one run of the app's FFmpeg command: [cleaned] has the
/// `-af` filter, [raw] is the same command without it.
class _CutPieces {
  const _CutPieces({required this.cleaned, required this.raw});

  final List<File> cleaned;
  final List<File> raw;

  List<File> of(_Variant variant) => variant.cleaned ? cleaned : raw;
}

Future<_CutPieces> _cutBothKinds(File video, Directory workFolder) async {
  final cleanedFolder = await Directory('${workFolder.path}/cleaned').create();
  final rawFolder = await Directory('${workFolder.path}/raw').create();
  final appArguments = _appArguments(video, cleanedFolder);
  return _CutPieces(
    cleaned: await _runFfmpeg(appArguments, cleanedFolder),
    raw: await _runFfmpeg(
      _withoutFilter(_appArguments(video, rawFolder)),
      rawFolder,
    ),
  );
}

List<String> _appArguments(File video, Directory folder) {
  return scriptPiecesArguments(
    ScriptPieces(
      inputPath: video.path,
      folderPath: folder.path,
      chunkSeconds: _pieceSeconds,
    ),
  );
}

Future<List<File>> _runFfmpeg(List<String> arguments, Directory folder) async {
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

Future<List<_Score>> _scoreAllVariants(
  GroqClient groq,
  List<String> expectedLines,
  _CutPieces pieces,
) async {
  final scores = <_Score>[];
  for (final variant in _variants) {
    final heard = await _transcribe(groq, pieces.of(variant), variant);
    scores.add(_score(variant, heard, expectedLines));
  }
  return scores;
}

Future<String> _transcribe(
  GroqClient groq,
  List<File> pieces,
  _Variant variant,
) async {
  final texts = <String>[];
  for (final piece in pieces) {
    final segments = await groq.transcribe(
      piece,
      languageCode: variant.languageCode,
    );
    texts.addAll(
      segments
          .where((segment) => segment.noSpeechProbability < groqNoSpeechCutoff)
          .map((segment) => segment.text),
    );
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
    ..writeln();
  _printTable(scores);
  stdout.writeln();
  for (final languageCode in const <String?>[null, 'ur']) {
    stdout.writeln(_verdict(scores, languageCode));
  }
  stdout.writeln();
  _printWhatWasHeard(scores);
}

void _printTable(List<_Score> scores) {
  stdout
    ..writeln('| Audio | Language | CER | Lines missing |')
    ..writeln('|---|---|---|---|');
  for (final score in scores) {
    stdout.writeln(
      '| ${score.variant.audioName} | ${score.variant.languageName} '
      '| ${(score.errorRate * 100).toStringAsFixed(1)} % '
      '| ${score.missing.length} |',
    );
  }
}

void _printWhatWasHeard(List<_Score> scores) {
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
